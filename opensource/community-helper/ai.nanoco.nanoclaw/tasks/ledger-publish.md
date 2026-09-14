---
schedule: "38 6 * * *"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, git. Push auth injected by the OneCLI proxy for the `github.com`
  # (git) host — a distinct vault entry class from `api.github.com` (REST).
  #
  # WHAT THIS IS FOR. Most of what this agent writes is cache: a cursor, a
  # last-seen snapshot, a dedup list. Losing any of it costs one duplicate
  # report and it rebuilds itself on the next run. Three files are different,
  # and the test that earns a file a place here is not "does it look like
  # history" — it is "could a script rebuild this from scratch tomorrow?"
  #
  #   social-metrics-history.jsonl  NO, never. Facebook, LinkedIn, Instagram and
  #     YouTube each expose the CURRENT follower count and nothing else. There is
  #     no API, page, or export anywhere that will say what the count was last
  #     Tuesday. A day that goes unrecorded is gone for good, at any price. This
  #     is the strongest single reason this task exists.
  #
  #   traffic-history-*.json        PARTLY. GA4 can be re-queried for any date
  #     inside the property's retention window (14 months by default, and
  #     configurable down to 2) and nothing at all from before the property
  #     existed. Recoverable short-term, permanently gone past that horizon —
  #     which is exactly what the year-over-year comparison needs.
  #
  #   metrics-history.json          EFFECTIVELY NO. GitHub returns the CURRENT
  #     star and fork count; reconstructing past values means paging every
  #     stargazer with the special `star+json` Accept header, plus every issue's
  #     comment timestamps for `awaiting_first_response`. Possible in principle,
  #     a multi-thousand-call reconstruction in practice.
  #
  # `contributor-health-history.json` deliberately does NOT ship here, and the
  # reason is worth keeping: it is a rollup over a 90-day window of PR merge and
  # close data, all of which is immutable and permanently queryable. Its value
  # "as of" any past date can be recomputed by re-running the same arithmetic.
  # It is a cache with a history-shaped filename. Don't add it back without
  # first finding a value in it that the API can no longer answer.
  #
  # This system is deliberately destroyed and rebuilt from the templates every
  # few months, and nothing reimports a container backup — so a whole-workspace
  # backup would be a copy nothing ever reads. This task is the narrow
  # alternative: a git repo is a destination a human already opens, not a
  # restore nobody runs.
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
  DATA="/workspace/agent/plugin-data/community-helper"
  mkdir -p "$DATA"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  # Normally the project's marketing repo rather than the product repo — a daily
  # metrics commit has no business near the repo carrying the CI and review
  # burden, and one destination means one place a human looks for "the history of
  # this project's numbers".
  REPO="${LEDGER_REPO:-}"
  if [ -z "$REPO" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set LEDGER_REPO (owner/repo - normally the marketing repo) in plugin-data/community-helper/config.env to publish the metric history; unset means every series stays container-local and is lost at the next rebuild, and the follower counts cannot be re-read from anywhere afterwards"}}'
    exit 0
  fi
  BRANCH="${LEDGER_BRANCH:-agent-metrics}"
  SUBDIR="${LEDGER_PATH:-agent-metrics}"

  # The curated list. Numeric, unrebuildable series only — see the note above.
  # The traffic files are one per configured GA4 property, so they are matched by
  # glob rather than named: adding a property publishes it without a code change.
  #
  # Explicit ifs, not `[ -f x ] && VAR=y`: under `set -e` a false test ends the
  # whole script, which for a task gate means exiting with NO output at all —
  # a silent failure, the one outcome worse than a reported one. The glob needs
  # the same guard for the no-match case, where it stays literal.
  PRESENT=""
  for f in metrics-history.json social-metrics-history.jsonl; do
    if [ -f "$DATA/$f" ]; then PRESENT="$PRESENT $f"; fi
  done
  for f in "$DATA"/traffic-history-*.json; do
    if [ -f "$f" ]; then PRESENT="$PRESENT $(basename "$f")"; fi
  done
  if [ -z "${PRESENT# }" ]; then
    echo '{"wakeAgent": false, "data": {"status": "nothing-to-publish", "hint": "no history files exist yet - dev-metrics-report, social-metrics-snapshot and weekly-analytics-report each build their own on their first run"}}'
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
      git -C "$WORK" config user.name "Community Agent" || true
    fi
    git -C "$WORK" add -A >/dev/null 2>&1 || true
    git -C "$WORK" commit --quiet -m "chore(metrics): history for $(date -u +%Y-%m-%d)" >/dev/null 2>&1 \
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
---
Pure housekeeping: commits this agent's one unrecoverable time series
(`metrics-history.json`) to a branch in the project's marketing repo, so the
history outlives this container. **A successful publish never wakes you** —
you are only invoked when something failed.

**Why you should care that this failed.** Every other file this agent writes
rebuilds itself. This one cannot: GitHub will tell you the star count today
and has no way to tell you what it was last month. Each day this task stays
broken is a day permanently missing from the series once this container is
rebuilt. It is not urgent within the hour, and it *is* worth your manager
hearing about within the day.

- **`not-configured`**: `LEDGER_REPO` isn't set. Say so
  once and stop; don't re-raise it every run. Until it's set the series is
  container-local and will be lost at the next rebuild, which is a real
  consequence worth stating plainly rather than filing as a config nit.
- **`clone-failed`**: most likely `github.com` (the git host, distinct from
  `api.github.com`) isn't allowlisted for this sandbox, or no `github.com` git
  credential with write access exists in the vault. Report which, don't retry
  by hand.
- **`push-failed`**: the commit exists locally and is retried next run, so a
  single occurrence is not data loss. Two in a row means the credential
  probably lacks write access to that repo — report it then.
- **`fetch-failed` / `checkout-failed` / `branch-create-failed`**: report the
  status verbatim. These deliberately refuse to force anything: a history
  whose whole value is being intact is never worth overwriting to make a task
  go green.

**Never work around a failure by pasting the file contents into a channel or
a PR.** The file is the artifact; a copy in a chat log is not the series, and
this task's whole point is that the data lands somewhere durable and
machine-readable.
