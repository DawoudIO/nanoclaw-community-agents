#!/bin/bash
set -euo pipefail
# Deps: bash, git. Push auth injected by the OneCLI proxy for the `github.com`
# (git) host — a distinct vault entry class from `api.github.com` (REST).
#
# WHAT THIS IS FOR. This agent holds the only series in the whole system that
# is unrecoverable by construction, not merely expensive to rebuild.
#
# `social-metrics-history.jsonl` — follower counts. Facebook, LinkedIn,
# Instagram and YouTube all expose the CURRENT number and nothing else. There
# is no API, no page, and no export anywhere that will tell you what the count
# was last Tuesday. Once a day passes unrecorded, that day is gone forever.
# This is the single strongest argument for this task existing at all.
#
# `traffic-history-*.json` — GA4 web traffic. Re-queryable for any date inside
# the property's retention window (14 months by default, and configurable down
# to 2), and nothing at all before the property existed. So: recoverable in
# the short term, permanently gone past the horizon — which is exactly what
# the year-over-year comparison needs and why it is published rather than
# treated as cache.
#
# This system is deliberately destroyed and rebuilt from the templates every
# few months, and nothing reimports a container backup — which is why the old
# whole-workspace backup was removed: it wrote a copy nothing ever read. This
# task is the narrow replacement, and the difference that matters is that a
# git repo is a destination a human already reads, not a restore nobody runs.
# For the follower series specifically, a missed repave means the trend line
# restarts from zero with no way to ever recover the gap.
#
# WHY A DEDICATED BRANCH. Everything published by this system lands on
# LEDGER_BRANCH (default `agent-metrics`) rather than the repo's default
# branch: no PR, no review, and — if the repo's workflows are branch-filtered,
# as most are — no CI run per daily metrics commit. Nothing on the default
# branch is ever touched. It is created as an ORPHAN branch, so it carries
# these files and nothing else instead of forking the repo's whole history.
#
# WHAT IS DELIBERATELY NOT PUBLISHED: anything conversational or operational.
# Community questions, owner instructions, acknowledgment ledgers, injection
# logs, and digest queues all stay inside the container. They can contain a
# community member's words or the owner's private direction, and a repo branch
# is the wrong place for either — publish numbers, never people. Do not widen
# this list without deciding that question again.
DATA="/workspace/agent/plugin-data/community-marketing"
mkdir -p "$DATA"
if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
# The marketing repo: this agent's own home repo, and the one place every
# published series in this system lands, so a human has one destination to
# look at for "the history of this project's numbers".
REPO="${LEDGER_REPO:-${MARKETING_REPO:-}}"
if [ -z "$REPO" ]; then
  echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set LEDGER_REPO (owner/repo, defaults to MARKETING_REPO) in plugin-data/community-marketing/config.env to publish the metric history; unset means the series stays container-local and is lost at the next rebuild"}}'
  exit 0
fi
BRANCH="${LEDGER_BRANCH:-agent-metrics}"
SUBDIR="${LEDGER_PATH:-agent-metrics}/marketing"

# The curated list. Numeric series only — see the note above. The traffic
# files are one per configured GA4 property, so they are matched by glob
# rather than named: a newly added property publishes without a code change.
# Explicit ifs, not `[ -f x ] && VAR=y`: under `set -e` a false test ends the
# whole script, which for a task gate means exiting with NO output at all —
# a silent failure, the one outcome worse than a reported one. The glob below
# also needs the guard for the no-match case, where it stays literal.
PRESENT=""
if [ -f "$DATA/social-metrics-history.jsonl" ]; then
  PRESENT="social-metrics-history.jsonl"
fi
for f in "$DATA"/traffic-history-*.json; do
  if [ -f "$f" ]; then PRESENT="$PRESENT $(basename "$f")"; fi
done
if [ -z "${PRESENT# }" ]; then
  echo '{"wakeAgent": false, "data": {"status": "nothing-to-publish", "hint": "no history files exist yet - social-metrics-snapshot and weekly-analytics-report build them on their own schedules"}}'
  exit 0
fi

fail() { printf '{"wakeAgent": true, "data": {"status": "%s", "hint": "%s"}}\n' "$1" "$2"; exit 0; }

WORK="$DATA/.ledger-repo"
if [ ! -d "$WORK/.git" ]; then
  rm -rf "$WORK"
  git clone --quiet --depth 1 "https://github.com/$REPO.git" "$WORK" >/dev/null 2>&1 || {
    rm -rf "$WORK"
    fail clone-failed "cannot clone the ledger repo - check the repo name, that github.com (git) is allowlisted for this sandbox, and that a github.com git credential with write access exists in the vault"
  }
fi

# Get onto LEDGER_BRANCH, in whichever of the three states this run finds.
if git -C "$WORK" ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  # (1) Upstream has it: take upstream as the truth. This also discards any
  # local commit left behind by an earlier failed push, which is why a failure
  # never leaves a half-published state — the files are simply re-copied below.
  #
  # NOT `--depth 1`. A shallow fetch leaves this branch's history grafted, and
  # git refuses to push a shallow-rooted branch when the remote doesn't already
  # have the base commits ("shallow update not allowed"). That turns one
  # deleted upstream branch into a task that can never publish again while the
  # series quietly piles up container-local — the exact loss this task exists
  # to prevent. The ledger branch is an orphan holding a few small JSON files,
  # so its full history is cheap to carry; the initial clone above stays
  # shallow because the default branch is only ever read, never pushed.
  git -C "$WORK" fetch --quiet --depth 1000000 origin "$BRANCH" >/dev/null 2>&1 \
    && git -C "$WORK" checkout --quiet -B "$BRANCH" FETCH_HEAD >/dev/null 2>&1 \
    || fail fetch-failed "the ledger branch exists upstream but could not be checked out - reporting rather than overwriting whatever is there"
elif git -C "$WORK" show-ref --quiet --verify "refs/heads/$BRANCH"; then
  # (2) Only local has it: a previous run committed but could not push. Stay on
  # it and keep that commit — `checkout --orphan` would fail on an existing
  # branch, and treating this as "nothing changed" would silently drop history
  # that never actually reached the repo.
  git -C "$WORK" checkout --quiet "$BRANCH" >/dev/null 2>&1 \
    || fail checkout-failed "a local ledger branch exists but could not be checked out"
else
  # (3) Brand new: orphan branch, empty tree.
  git -C "$WORK" checkout --quiet --orphan "$BRANCH" >/dev/null 2>&1 \
    || fail branch-create-failed "could not create the ledger branch"
  git -C "$WORK" rm -rq --cached . >/dev/null 2>&1 || true
  find "$WORK" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} + 2>/dev/null || true
fi

mkdir -p "$WORK/$SUBDIR"
for f in $PRESENT; do
  cp "$DATA/$f" "$WORK/$SUBDIR/$f"
done

if [ -n "$(git -C "$WORK" status --porcelain 2>/dev/null)" ]; then
  if ! git -C "$WORK" config user.email >/dev/null 2>&1; then
    git -C "$WORK" config user.email "noreply@localhost" || true
    git -C "$WORK" config user.name "Community Marketing Agent" || true
  fi
  git -C "$WORK" add -A >/dev/null 2>&1 || true
  git -C "$WORK" commit --quiet -m "chore(metrics): marketing history for $(date -u +%Y-%m-%d)" >/dev/null 2>&1 \
    || fail commit-failed "the tree changed but the commit was refused"
fi

# Push whenever the local branch is ahead of (or unknown to) the remote — NOT
# only when this run changed something. A clean tree does not mean published:
# an unpushed commit from a failed earlier run must still get out, or the
# history this task exists to protect is quietly lost.
REMOTE_SHA=$(git -C "$WORK" ls-remote origin "refs/heads/$BRANCH" 2>/dev/null | awk '{print $1}')
LOCAL_SHA=$(git -C "$WORK" rev-parse HEAD 2>/dev/null || echo "")
if [ -n "$REMOTE_SHA" ] && [ "$REMOTE_SHA" = "$LOCAL_SHA" ]; then
  echo '{"wakeAgent": false, "data": {"status": "ok", "note": "no change since the last publish"}}'
  exit 0
fi
# No --force, ever: if someone else moved the branch, this must fail and be
# reported, never overwrite a history whose whole value is being intact.
git -C "$WORK" push --quiet origin "$BRANCH" >/dev/null 2>&1 \
  || fail push-failed "committed locally but could not push - most likely the vault github.com (git) credential lacks write access to the ledger repo, or the branch moved upstream since the last run. The commit is kept and retried next run"
printf '{"wakeAgent": false, "data": {"status": "published", "branch": "%s", "files": "%s"}}\n' "$BRANCH" "${PRESENT# }"
