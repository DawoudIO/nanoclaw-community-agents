---
schedule: "0 12 * * *"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy for
  # api.github.com — no token here, no `gh` CLI.
  DATA="/workspace/agent/plugin-data/community-coding"
  mkdir -p "$DATA"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  REPOS="${COMMUNITY_REPOS:-}"
  if [ -z "$REPOS" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-coding/config.env"}}'
    exit 0
  fi
  HIST="$DATA/metrics-history.json"
  if [ ! -f "$HIST" ]; then echo '[]' > "$HIST"; fi
  TODAY="{}"
  for REPO in $REPOS; do
    OPEN_ISSUES=$(curl -sS --max-time 15 -H "Accept: application/vnd.github+json" \
      "https://api.github.com/search/issues?q=repo:$REPO+is:issue+is:open&per_page=1" \
      | jq '.total_count // 0' 2>/dev/null || echo 0)
    OPEN_PRS=$(curl -sS --max-time 15 -H "Accept: application/vnd.github+json" \
      "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:open&per_page=1" \
      | jq '.total_count // 0' 2>/dev/null || echo 0)
    TODAY=$(printf '%s' "$TODAY" | jq -c --arg r "$REPO" --argjson i "$OPEN_ISSUES" --argjson p "$OPEN_PRS" \
      '. + {($r): {open_issues: $i, open_prs: $p}}')
  done
  PREV=$(jq -c '.[-1].metrics // {}' "$HIST")
  jq -c --argjson m "$TODAY" --arg d "$(date -u +%Y-%m-%d)" \
    '. + [{date: $d, metrics: $m}] | .[-30:]' "$HIST" > "$HIST.tmp" && mv "$HIST.tmp" "$HIST"
  printf '{"wakeAgent": true, "data": {"today": %s, "previous": %s}}\n' "$TODAY" "$PREV"
---
Write the daily dev metrics section for your lead agent's dev-facing report,
using `scriptOutput.today` and `scriptOutput.previous` (the prior run's numbers,
already fetched — don't re-query).

Every number carries its delta versus the previous run. A count with no
comparison point isn't useful. Call out anything that moved sharply and say what
you think is behind it only if you actually checked; otherwise report the move
and say the cause is unverified.

Hand it to your lead — you don't post it to a channel yourself.
