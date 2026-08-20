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
Weekly telemetry review. **The goal is finding issues before users report
them** — error spikes, silently failing flows, anomalies that correlate with a
recent release. `scriptOutput` carries the fetched insight list (or `status:
"fetch-failed"` — if so, report that plainly to your lead and stop; don't
guess at numbers).

For anything that looks like a real defect users haven't reported yet: draft a
GitHub issue (title, evidence, suspected release/commit window) and hand it to
your lead for review and filing — you don't post it yourself. For the rest,
a short narrative: what moved week-over-week, what's anomalous, what a human
should look at. Numbers always carry their window; anything unverified stays
marked unverified.
