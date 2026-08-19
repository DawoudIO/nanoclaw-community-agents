---
schedule: "0 */3 * * *"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, jq. `ncl` is optional — the paused-task check skips without it.
  DATA="/workspace/agent/plugin-data/community-support"
  mkdir -p "$DATA"
  ISSUES=""
  note() { ISSUES="${ISSUES}${ISSUES:+|}$1"; }

  STATE="/workspace/agent/state.json"
  if [ -f "$STATE" ]; then
    AGE=$(( $(date +%s) - $(date -r "$STATE" +%s) ))
    if [ "$AGE" -gt 21600 ]; then
      note "state.json is $((AGE/3600))h stale (expected updates at least every 6h)"
    fi
  fi

  # Paused-task drift. Fresh installs ship every task paused by design, so a
  # bare "paused > 0" check would false-alarm every 3h. Alert only when the
  # paused count RISES above the recorded baseline; the baseline self-lowers
  # when tasks are resumed and self-raises after one alert (one alert per rise,
  # not a nag every cycle).
  if command -v ncl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    PAUSED=$(ncl tasks list --status paused --json 2>/dev/null | jq 'length' 2>/dev/null || echo "")
    if [ -n "$PAUSED" ]; then
      BASE_F="$DATA/paused-baseline"
      BASE=$(cat "$BASE_F" 2>/dev/null || echo "$PAUSED")
      if [ "$PAUSED" -gt "$BASE" ]; then
        note "paused task count rose from $BASE to $PAUSED — was a task paused unexpectedly?"
      fi
      echo "$PAUSED" > "$BASE_F"
    fi
  fi

  if [ -z "$ISSUES" ]; then
    echo '{"wakeAgent": false, "data": {"status": "ok"}}'
  else
    printf '%s' "$ISSUES" | tr '|' '\n' | jq -R . | jq -s -c '{wakeAgent: true, data: {status: "attention", issues: .}}'
  fi
---
Only invoked when the health-check script found something. Summarize
`scriptOutput.issues` for the owner in one short message — what's stale or
newly paused, and since when. Don't speculate about cause; just report the fact
and ask if it's expected. Never pause or resume a task on your own from this
task.
