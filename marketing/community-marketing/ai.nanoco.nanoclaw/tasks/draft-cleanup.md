---
schedule: "30 17 * * *"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy for
  # api.github.com — no token here, no `gh` CLI.
  DATA="/workspace/agent/plugin-data/community-marketing"
  mkdir -p "$DATA"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  REPO="${CONTENT_REPO:-}"
  if [ -z "$REPO" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set CONTENT_REPO in plugin-data/community-marketing/config.env"}}'
    exit 0
  fi
  PRS=$(curl -sS --max-time 15 -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/pulls?state=open&per_page=100" || echo '[]')
  CUTOFF=$(( $(date +%s) - 604800 ))
  STALE=$(printf '%s' "$PRS" | jq -c --argjson c "$CUTOFF" \
    '[.[] | select((.updated_at | fromdateiso8601) < $c) | {number, title, updated_at}]' 2>/dev/null || echo '[]')
  if [ "$(printf '%s' "$STALE" | jq 'length')" -eq 0 ]; then
    echo '{"wakeAgent": false, "data": {"status": "no-stale-drafts"}}'
  else
    printf '{"wakeAgent": true, "data": {"status": "stale", "drafts": %s}}\n' "$STALE"
  fi
---
Only invoked when there are content PRs sitting untouched for a week or more —
`scriptOutput.drafts` lists them.

Report them to your lead: number, title, how long stale. Recommend close or
revive for each, with a one-line reason. **Report only** — never close, merge, or
delete a draft PR yourself, even one you opened. Someone may be waiting on it.
