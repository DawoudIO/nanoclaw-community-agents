---
schedule: "0 */6 * * *"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
  # Gate: fetch the delta since last run; wake the model only if there is one.
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
  ITEMS="[]"
  for REPO in $REPOS; do
    URL="https://api.github.com/repos/$REPO/issues?state=open&sort=updated&direction=desc&per_page=50"
    if [ -n "$SINCE" ]; then URL="$URL&since=$SINCE"; fi
    RESP=$(curl -sS --max-time 15 -H "Accept: application/vnd.github+json" "$URL" || echo '[]')
    BATCH=$(printf '%s' "$RESP" | jq -c --arg r "$REPO" \
      '[.[]? | {repo: $r, number, title: (.title[0:120]), is_pr: (has("pull_request")), updated_at, labels: [.labels[].name]}]' \
      2>/dev/null || echo '[]')
    ITEMS=$(jq -c -n --argjson a "$ITEMS" --argjson b "$BATCH" '$a + $b')
  done
  date -u +%Y-%m-%dT%H:%M:%SZ > "$SINCE_F"
  if [ "$(printf '%s' "$ITEMS" | jq 'length')" -eq 0 ]; then
    echo '{"wakeAgent": false, "data": {"status": "quiet"}}'
  else
    printf '{"wakeAgent": true, "data": {"since": "%s", "items": %s}}\n' "${SINCE:-first-run}" "$ITEMS"
  fi
---
Triage pass over `scriptOutput.items` — issues and PRs created or updated since
`scriptOutput.since` (already fetched; read anything you need in depth, but
don't re-list).

For each item: duplicate of an existing open issue? Security-shaped (route per
your security-handling reference — never comment publicly on those)? Stale PR
needing a nudge decision? Waiting on a maintainer? Produce one digest, hand it
to your lead via your parent destination. Never post, comment, or label
anything on GitHub yourself — you draft, your lead publishes.
