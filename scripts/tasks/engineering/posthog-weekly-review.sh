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
# Fetch each insight's actual computed result inline (PostHog's list
# endpoint returns it directly) so the agent has real week-over-week
# values without a single extra API call — and keep a rolling history so
# "previous" is a real fetched number, never a guess or last week's memory.
HIST="$DATA/posthog-insights-history.json"
if [ ! -f "$HIST" ]; then echo '[]' > "$HIST"; fi
TODAY_MAP=$(printf '%s' "$RESP" | jq -c '[.results[]? | {id: (.id|tostring), name, last_refresh, result}] | map({(.id): .}) | add // {}')
PREV_MAP=$(jq -c '.[-1].insights // {}' "$HIST")
jq -c --argjson m "$TODAY_MAP" --arg d "$(date -u +%Y-%m-%d)" \
  '. + [{date: $d, insights: $m}] | .[-12:]' "$HIST" > "$HIST.tmp" && mv "$HIST.tmp" "$HIST"
COMBINED=$(jq -nc --argjson t "$TODAY_MAP" --argjson p "$PREV_MAP" \
  '$t | to_entries | map(.value + {previous_result: ($p[.key].result // null)})')

# Wake gate: only spend agent tokens when an insight's RESULT actually
# changed since last week — compare result values only, never last_refresh
# (PostHog bumps that on every cache refresh regardless of the numbers,
# which would flip this gate to "changed" every single week and defeat it).
# A 7-day heartbeat forces a wake on a fully static week so the channel
# doesn't go quiet long enough to look dead.
CHANGED=$(jq -n --argjson t "$TODAY_MAP" --argjson p "$PREV_MAP" \
  '($t | with_entries(.value |= .result)) != ($p | with_entries(.value |= .result))')
LASTWAKE_F="$DATA/posthog-review-last-wake"
DAYS_SINCE_WAKE=999
if [ -f "$LASTWAKE_F" ]; then
  NOW_EPOCH=$(date +%s)
  LW_EPOCH=$(date -u -d "$(cat "$LASTWAKE_F")" +%s 2>/dev/null || date -u -j -f %Y-%m-%d "$(cat "$LASTWAKE_F")" +%s 2>/dev/null || echo 0)
  DAYS_SINCE_WAKE=$(( (NOW_EPOCH - LW_EPOCH) / 86400 ))
fi
WAKE=false
if [ "$CHANGED" = "true" ] || [ "$DAYS_SINCE_WAKE" -ge 7 ]; then
  WAKE=true
  date -u +%Y-%m-%d > "$LASTWAKE_F"
fi
printf '{"wakeAgent": %s, "data": {"status": "ok", "insights": %s, "quiet_heartbeat": %s}}\n' \
  "$WAKE" "$COMBINED" "$([ "$CHANGED" = "false" ] && echo true || echo false)"
