---
schedule: "13 13 * * 1-5"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
  # Gate: fetch the delta since last run; wake the model only if there is one.
  # The cursor advances ONLY on a fully successful fetch — a failed or
  # unauthorized fetch must never silently swallow a window of updates.
  DATA="/workspace/agent/plugin-data/community-support"
  mkdir -p "$DATA"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  REPOS="${COMMUNITY_REPOS:-}"
  if [ -z "$REPOS" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-support/config.env"}}'
    exit 0
  fi
  SINCE_F="$DATA/triage-last-run"
  SINCE=$(cat "$SINCE_F" 2>/dev/null || echo "")
  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  ITEMS="[]"; FAILED=""; TRUNC=""
  for REPO in $REPOS; do
    URL="https://api.github.com/repos/$REPO/issues?state=open&sort=updated&direction=desc&per_page=50"
    if [ -n "$SINCE" ]; then URL="$URL&since=$SINCE"; fi
    RESP=$(curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" "$URL") || { FAILED="$FAILED $REPO"; continue; }
    BATCH=$(printf '%s' "$RESP" | jq -c 'if type=="array" then [.[] | {number, title: (.title[0:120]), is_pr: (has("pull_request")), updated_at, labels: [.labels[].name]}] else null end' 2>/dev/null || echo null)
    if [ "$BATCH" = "null" ]; then FAILED="$FAILED $REPO"; continue; fi
    BATCH=$(printf '%s' "$BATCH" | jq -c --arg r "$REPO" 'map(. + {repo: $r})')
    if [ "$(printf '%s' "$BATCH" | jq 'length')" -eq 50 ]; then TRUNC="$TRUNC $REPO"; fi
    ITEMS=$(jq -c -n --argjson a "$ITEMS" --argjson b "$BATCH" '$a + $b')
  done
  if [ -n "$FAILED" ]; then
    printf '{"wakeAgent": true, "data": {"status": "fetch-failed", "failed_repos": "%s", "items": %s}}\n' "${FAILED# }" "$ITEMS"
    exit 0
  fi
  echo "$NOW" > "$SINCE_F"
  if [ "$(printf '%s' "$ITEMS" | jq 'length')" -eq 0 ]; then
    echo '{"wakeAgent": false, "data": {"status": "quiet"}}'
  else
    printf '{"wakeAgent": true, "data": {"since": "%s", "truncated_repos": "%s", "items": %s}}\n' "${SINCE:-first-run}" "${TRUNC# }" "$ITEMS"
  fi
---
Standalone-mode triage (leave this task paused if the coding sub-agent is
stamped — its own triage covers this at higher cadence).

**If `status` is `fetch-failed`**: don't triage — report it to the owner.
`401/403` symptoms mean the token isn't wired (vault entry or selective-mode
assignment); the cursor was deliberately not advanced, so nothing is lost.

Otherwise, work `scriptOutput.items` — issues and PRs created or updated since
`scriptOutput.since`. If `truncated_repos` is non-empty, say so in the digest:
more than 50 items updated there and the oldest weren't fetched. Flag likely
duplicates, security-shaped reports (route per `references/escalation-paths.md`,
never publicly), stale PRs, and open maintainer questions. Produce one digest
per `references/report-formats.md` for your owner's review. Do not post,
comment, or label from this task directly — this task drafts; publishing
happens in your reviewed, live actions.
