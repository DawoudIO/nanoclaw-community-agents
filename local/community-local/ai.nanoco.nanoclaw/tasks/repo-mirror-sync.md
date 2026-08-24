---
schedule: "7,22,37,52 * * * *"
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
  # WHERE THIS WRITES: /workspace/shared-repos, NOT this agent's own
  # plugin-data. That path is a host directory mounted read-write here and
  # read-only into the Reviewer/Lead/Marketing containers (`ncl groups config
  # add-mount`, owner-run, one time — see local/community-local/README.md,
  # "Shared repo mirror"). This is the single source of truth for "what does
  # the code actually look like right now" across every agent, updated by
  # exactly one credentialed writer instead of each agent re-fetching or
  # re-cloning its own copy independently. If the mount isn't set up yet, this
  # still works — it just writes to a path only this agent can see, same as
  # before.
  #
  # Wakes on a real content change (so the agent can read what changed and
  # flag anything worth a human's attention — a wiki page contradicting
  # current code, a docs edit that needs review) OR on failure. Silent only
  # when literally nothing moved since the last run.
  DATA="/workspace/agent/plugin-data/community-local"
  MIRRORS="/workspace/shared-repos"
  mkdir -p "$MIRRORS"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  REPOS="${MIRROR_REPOS:-${COMMUNITY_REPOS:-}}"
  if [ -z "$REPOS" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set MIRROR_REPOS (or COMMUNITY_REPOS) in plugin-data/community-local/config.env"}}'
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
  # Freshness marker other agents can check before trusting the mirror for a
  # judgment call — see docs-currency-watch/security-advisory-sweep/
  # dependabot-pr-review, which all read this path directly now. Written after
  # the sync attempt (not before), so a stamp always means "a sync actually
  # ran," not just "the gate started."
  date -u +%s > "$MIRRORS/.last-sync-epoch" 2>/dev/null || true
  if [ "$(printf '%s' "$FAILED" | jq 'length')" -eq 0 ] && [ "$(printf '%s' "$CHANGED" | jq 'length')" -eq 0 ]; then
    echo '{"wakeAgent": false, "data": {"status": "ok"}}'
  else
    printf '{"wakeAgent": true, "data": {"status": "attention", "failed": %s, "changed": %s}}\n' "$FAILED" "$CHANGED"
  fi
---
Invoked on a sync failure, or when something in the mirror actually
changed — a run where nothing moved stays silent.

**`changed`**: for each entry, `files_changed` (up to 20) and `commits` (up
to 10 subjects) since the last sync. **Summarize what changed — do not judge
whether it is correct.** One line per repo: which areas moved (docs, product
code, wiki) and anything unusual on its face, like a docs page changing right
after a release, or a wiki edit touching a file a recent bug report named.

Deciding whether a wiki edit actually *contradicts* the code, or whether a
docs change makes past support answers stale, is reachability reasoning — that
belongs to the Reviewer. Surface the coincidence and say you have not assessed
it; let the Reviewer do that. Most syncs are ordinary and deserve a one-line
"nothing notable" at most, never a padded readout of every commit message.

**`dirty-tree`**: something modified a mirror directly. Nothing — no task,
no skill, no live session — should ever write into `/workspace/shared-repos`;
it's a read-only tracked-branch view, rebuilt by this gate alone. **Every
other agent mounts this path read-only** (`ncl groups config add-mount`, set
up once by the owner — see `local/community-local/README.md`, "Shared repo
mirror"), so a dirty tree there is either this gate racing itself or a
misconfigured mount granting write access somewhere it shouldn't. Report it
to your lead as a real anomaly, don't try to clean it up yourself (the gate
will just report it dirty again next run — that's correct until someone
investigates why a write happened at all).

**`clone-failed`/`pull-failed`**: report the repo and symptom. `github.com`
(not `api.github.com`) needs its own sandbox allowlist entry for git's HTTPS
protocol — that's the most likely cause on a fresh install. A private repo
also needs a `github.com` (git) vault credential, the same class
workspace-backup uses; public repos need none.

**What this buys you, and what it doesn't.** `/workspace/shared-repos/<repo>/`
(one directory per entry in `MIRROR_REPOS` — the project's full repo map:
product/docs/site/marketing/wiki, not just the repos triaged for issues/PRs)
is a shallow, current-branch checkout — **any agent with the mount** (not
just this one) should grep it directly instead of a live API call for
file-contents questions ("does this bug still reproduce in current main", an
exact file:line). This is the system's single source of truth for repo
content — one credentialed writer here, everyone else reads the same
checkout instead of re-fetching or re-cloning their own copy. Refreshed at
most every 15 minutes, not instantly — a `.last-sync-epoch` file in the same
directory (Unix seconds, UTC) lets a reader confirm how fresh it actually is
before trusting it for anything time-sensitive; say "as of the last sync,"
never imply real-time. It does **not** help with issues, PRs, releases, or
discussions — those only exist via the GitHub API and still need a live
call every time; a repo mirror is content, not project metadata. A GitHub
wiki is just a repo named `owner/repo.wiki` — it mirrors identically to
any other entry, no special handling needed.
