---
schedule: "0 15 * * 1"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, curl, jq. The PostHog personal API key is injected by the
  # OneCLI proxy for the PostHog host — no key belongs in this file.
  DATA="/workspace/agent/plugin-data/community-coding"
  mkdir -p "$DATA"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  PROJECT_ID="${POSTHOG_PROJECT_ID:-}"
  HOST="${POSTHOG_HOST:-https://us.posthog.com}"
  if [ -z "$PROJECT_ID" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set POSTHOG_PROJECT_ID in plugin-data/community-coding/config.env"}}'
    exit 0
  fi
  RESP=$(curl -sS --max-time 20 "$HOST/api/projects/$PROJECT_ID/insights/?limit=25" 2>/dev/null || echo '')
  if [ -z "$RESP" ] || ! printf '%s' "$RESP" | jq -e '.results' >/dev/null 2>&1; then
    echo '{"wakeAgent": true, "data": {"status": "fetch-failed"}}'
    exit 0
  fi
  printf '{"wakeAgent": true, "data": {"status": "ok", "insights": %s}}\n' \
    "$(printf '%s' "$RESP" | jq -c '[.results[]? | {name, id, last_refresh}]')"
---
Weekly telemetry review. `scriptOutput` carries the fetched insight list (or
`status: "fetch-failed"` — if so, report that plainly to your lead and stop;
don't guess at numbers).

Turn the data into a short narrative for your lead's dev report: what moved
week-over-week, what looks anomalous, and what you'd want a human to look at.
Numbers always carry their window. Anything you couldn't verify stays marked
unverified.

Hand it to your lead — you don't post it anywhere yourself.
