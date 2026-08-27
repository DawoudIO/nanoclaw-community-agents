---
schedule: "35 */6 * * *"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
  # Gate: fetch the delta since last run; wake the model only if there is one.
  # The cursor advances ONLY on a fully successful fetch — a failed or
  # unauthorized fetch must never silently swallow a window of updates.
  DATA="/workspace/agent/plugin-data/community-coding"
  mkdir -p "$DATA"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  REPOS="${COMMUNITY_REPOS:-}"
  if [ -z "$REPOS" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-coding/config.env"}}'
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
**If `status` is `fetch-failed`**: don't triage — report to your lead. A
`401/403` symptom means your token isn't wired (vault entry or selective-mode
assignment); the cursor wasn't advanced, so the window will be re-fetched.

Otherwise: triage pass over `scriptOutput.items` — issues and PRs created or
updated since `scriptOutput.since` (read anything you need in depth, but don't
re-list). If `truncated_repos` is non-empty, say so in the digest — more than
50 items updated there and the oldest weren't fetched.

For each item: duplicate of an existing open issue? Security-shaped (route per
your security-handling reference — never comment publicly on those)? Stale PR
needing a nudge decision? Waiting on a maintainer? Produce one digest, hand it
to your lead via your parent destination. Never post, comment, or label
anything on GitHub yourself — you draft, your lead publishes.
