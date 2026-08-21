#!/bin/bash
set -euo pipefail
# Deps: bash, curl, jq. The GA4 OAuth bearer is injected by the OneCLI proxy
# for analyticsdata.googleapis.com — no credential belongs in this file.
DATA="/workspace/agent/plugin-data/community-marketing"
mkdir -p "$DATA"
if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
PROPERTY_ID="${GA4_PROPERTY_ID:-}"
if [ -z "$PROPERTY_ID" ]; then
  echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set GA4_PROPERTY_ID in plugin-data/community-marketing/config.env"}}'
  exit 0
fi
HIST="$DATA/traffic-history.json"
if [ ! -f "$HIST" ]; then echo '[]' > "$HIST"; fi
RESP=$(curl -sS --max-time 25 -X POST \
  "https://analyticsdata.googleapis.com/v1beta/properties/$PROPERTY_ID:runReport" \
  -H 'Content-Type: application/json' \
  -d '{"dateRanges":[{"startDate":"7daysAgo","endDate":"yesterday"}],"metrics":[{"name":"activeUsers"},{"name":"sessions"},{"name":"screenPageViews"}]}' \
  2>/dev/null || echo '')
if [ -z "$RESP" ] || ! printf '%s' "$RESP" | jq -e '.rows' >/dev/null 2>&1; then
  echo '{"wakeAgent": true, "data": {"status": "fetch-failed"}}'
  exit 0
fi
WEEK=$(printf '%s' "$RESP" | jq -c '{activeUsers: (.rows[0].metricValues[0].value|tonumber), sessions: (.rows[0].metricValues[1].value|tonumber), pageViews: (.rows[0].metricValues[2].value|tonumber)}')
PREV=$(jq -c '.[-1].metrics // {}' "$HIST")
jq -c --argjson m "$WEEK" --arg d "$(date -u +%Y-%m-%d)" \
  '. + [{date: $d, metrics: $m}] | .[-26:]' "$HIST" > "$HIST.tmp" && mv "$HIST.tmp" "$HIST"
printf '{"wakeAgent": true, "data": {"status": "ok", "week": %s, "previous": %s}}\n' "$WEEK" "$PREV"
