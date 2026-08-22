---
name: posthog-weekly-review
schedule: "9 15 * * 1"
status: paused
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
  #
  # The heartbeat MUST be longer than this task's own cron interval or it can
  # never suppress anything: on a weekly cron, a 7-day heartbeat is satisfied
  # at every single run. 28 days = a fully static month still produces one
  # proof-of-life wake, while an ordinary quiet week stays silent.
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
  if [ "$CHANGED" = "true" ] || [ "$DAYS_SINCE_WAKE" -ge 28 ]; then
    WAKE=true
    date -u +%Y-%m-%d > "$LASTWAKE_F"
  fi
  printf '{"wakeAgent": %s, "data": {"status": "ok", "insights": %s, "quiet_heartbeat": %s}}\n' \
    "$WAKE" "$COMBINED" "$([ "$CHANGED" = "false" ] && echo true || echo false)"
---
Weekly telemetry review. **The goal is finding issues before users report
them** — error spikes, silently failing flows, anomalies that correlate with a
recent release. `scriptOutput` carries the fetched insight list, each with
its `result` and `previous_result` already fetched — don't re-query PostHog
yourself, and don't guess at a comparison your own memory of last week isn't
reliable for (a different session likely ran that report). `status:
"fetch-failed"` means report that plainly to your lead and stop.

**You're only woken when an insight's result actually changed, or a month
has passed with no wake at all** — history is still recorded every week
either way. If `quiet_heartbeat` is `true`, nothing moved; say one line ("no change
in tracked insights this week") instead of writing the full review below.

For anything that looks like a real defect users haven't reported yet: draft a
GitHub issue (title, evidence, suspected release/commit window) and hand it to
your lead for review and filing — you don't post it yourself. For the rest,
a short narrative: what moved week-over-week (using `result` vs.
`previous_result`), what's anomalous, what a human should look at. `null` for
`previous_result` means this insight has no prior data point yet (first run,
or a new insight) — don't compute a delta from it. Numbers always carry their
window; anything unverified stays marked unverified.
