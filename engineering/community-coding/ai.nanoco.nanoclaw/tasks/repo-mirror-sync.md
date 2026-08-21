---
schedule: "*/15 * * * *"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, git, jq. GitHub auth injected by the OneCLI proxy for the
  # `github.com` (git) host — same vault entry class workspace-backup uses,
  # distinct from `api.github.com` (REST). Public repos need no credential.
  #
  # Keeps a shallow, read-only local mirror of every repo in MIRROR_REPOS
  # current — the project's full repo map (product/docs/site/marketing/wiki),
  # not just the ones triaged for issues/PRs. A GitHub wiki is just a repo
  # named "owner/repo.wiki" — write it into MIRROR_REPOS exactly like that,
  # no special-casing needed here.
  #
  # This is NOT a cache of issues/PRs/releases — those only exist via the
  # GitHub API and still need a live call; this mirror only ever holds the
  # current tree of tracked branches.
  #
  # Wakes on a real content change (so the agent can read what changed and
  # flag anything worth a human's attention — a wiki page contradicting
  # current code, a docs edit that needs review) OR on failure. Silent only
  # when literally nothing moved since the last run.
  DATA="/workspace/agent/plugin-data/community-coding"
  MIRRORS="$DATA/repo-mirror"
  mkdir -p "$MIRRORS"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  REPOS="${MIRROR_REPOS:-${COMMUNITY_REPOS:-}}"
  if [ -z "$REPOS" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set MIRROR_REPOS (or COMMUNITY_REPOS) in plugin-data/community-coding/config.env"}}'
    exit 0
  fi
  FAILED="[]"
  CHANGED="[]"
  for REPO in $REPOS; do
    SAFEREPO=$(printf '%s' "$REPO" | tr '/' '_')
    DIR="$MIRRORS/$SAFEREPO"
    if [ ! -d "$DIR/.git" ]; then
      if ! git clone --quiet --depth 1 "https://github.com/$REPO.git" "$DIR" >/dev/null 2>&1; then
        rm -rf "$DIR"
        FAILED=$(printf '%s' "$FAILED" | jq -c --arg r "$REPO" --arg s "clone-failed" '. + [{repo: $r, symptom: $s}]')
        continue
      fi
      # First clone is a baseline, not a "change" — nothing to diff against yet.
      continue
    fi
    # A dirty or diverged tree means something touched a mirror nothing should
    # write to — surface it rather than silently forcing it back to clean.
    if [ -n "$(git -C "$DIR" status --porcelain 2>/dev/null)" ]; then
      FAILED=$(printf '%s' "$FAILED" | jq -c --arg r "$REPO" --arg s "dirty-tree" '. + [{repo: $r, symptom: $s}]')
      continue
    fi
    OLD_HEAD=$(git -C "$DIR" rev-parse HEAD 2>/dev/null || echo "")
    if ! git -C "$DIR" fetch --quiet --depth 20 origin >/dev/null 2>&1 \
       || ! git -C "$DIR" reset --quiet --hard origin/HEAD >/dev/null 2>&1; then
      FAILED=$(printf '%s' "$FAILED" | jq -c --arg r "$REPO" --arg s "pull-failed" '. + [{repo: $r, symptom: $s}]')
      continue
    fi
    NEW_HEAD=$(git -C "$DIR" rev-parse HEAD 2>/dev/null || echo "")
    if [ -n "$OLD_HEAD" ] && [ "$OLD_HEAD" != "$NEW_HEAD" ]; then
      FILES=$(git -C "$DIR" diff --name-only "$OLD_HEAD" "$NEW_HEAD" 2>/dev/null | head -20 | jq -R -s -c 'split("\n") | map(select(length>0))')
      SUBJECTS=$(git -C "$DIR" log --oneline --format='%s' "$OLD_HEAD..$NEW_HEAD" 2>/dev/null | head -10 | jq -R -s -c 'split("\n") | map(select(length>0))')
      CHANGED=$(printf '%s' "$CHANGED" | jq -c --arg r "$REPO" --argjson f "$FILES" --argjson s "$SUBJECTS" \
        '. + [{repo: $r, files_changed: $f, commits: $s}]')
    fi
  done
  if [ "$(printf '%s' "$FAILED" | jq 'length')" -eq 0 ] && [ "$(printf '%s' "$CHANGED" | jq 'length')" -eq 0 ]; then
    echo '{"wakeAgent": false, "data": {"status": "ok"}}'
  else
    printf '{"wakeAgent": true, "data": {"status": "attention", "failed": %s, "changed": %s}}\n' "$FAILED" "$CHANGED"
  fi
---
Invoked on a sync failure, or when something in the mirror actually
changed — a run where nothing moved stays silent.

**`changed`**: for each entry, `files_changed` (up to 20) and `commits` (up
to 10 subjects) since the last sync. Skim it — this is genuinely "learn
from the update," not a rubber stamp: does a wiki edit contradict current
code or a recent release? Does a docs change need a currency check against
what support has been telling users? Does a product-repo commit touch
something a recent bug report was about? Flag anything real to your lead;
most syncs are ordinary and deserve a one-line "nothing notable" at most,
not a padded readout of every commit message.

**`dirty-tree`**: something modified a mirror directly. Nothing — no task,
no skill, no live session — should ever write into `repo-mirror/`; it's a
read-only local view of the tracked branch, rebuilt by this gate alone.
Report it to your lead as a real anomaly, don't try to clean it up
yourself (the gate will just report it dirty again next run — that's
correct until someone investigates why a write happened at all).

**`clone-failed`/`pull-failed`**: report the repo and symptom. `github.com`
(not `api.github.com`) needs its own sandbox allowlist entry for git's HTTPS
protocol — that's the most likely cause on a fresh install. A private repo
also needs a `github.com` (git) vault credential, the same class
workspace-backup uses; public repos need none.

**What this buys you, and what it doesn't.** `repo-mirror/<repo>/` (one
directory per entry in `MIRROR_REPOS` — the project's full repo map:
product/docs/site/marketing/wiki, not just the repos triaged for
issues/PRs) is a shallow, current-branch checkout — grep it directly
instead of a live API call for file-contents questions ("does this bug
still reproduce in current main", an exact file:line). Refreshed at most
every 15 minutes, not instantly — say "as of the last sync," never imply
real-time. It does **not** help with issues, PRs, releases, or
discussions — those only exist via the GitHub API and still need a live
call every time; a repo mirror is content, not project metadata. A GitHub
wiki is just a repo named `owner/repo.wiki` — it mirrors identically to
any other entry, no special handling needed.
