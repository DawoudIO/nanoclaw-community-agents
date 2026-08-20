---
schedule: "0 */3 * * *"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash + coreutils only. jq/ncl are checked for, not required — a
  # degraded image is itself a finding this gate must be able to report.
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

  # Environment self-check: report a missing dependency ONCE, not every 3h.
  if ! command -v jq >/dev/null 2>&1; then
    if [ ! -f "$DATA/warned-no-jq" ]; then
      note "jq missing from the agent image - several script gates depend on it"
      touch "$DATA/warned-no-jq"
    fi
  fi
  if ! command -v ncl >/dev/null 2>&1; then
    if [ ! -f "$DATA/warned-no-ncl" ]; then
      note "ncl unavailable inside task scripts - paused-task and integrity checks degraded"
      touch "$DATA/warned-no-ncl"
    fi
  fi

  # Paused-task drift. Fresh installs ship every task paused by design, so a
  # bare "paused > 0" check would false-alarm every 3h. Alert only when the
  # paused count RISES above the recorded baseline (one alert per rise).
  if command -v ncl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    PAUSED=$(ncl tasks list --status paused --json 2>/dev/null | jq 'length' 2>/dev/null || echo "")
    if [ -n "$PAUSED" ]; then
      BASE_F="$DATA/paused-baseline"
      BASE=$(cat "$BASE_F" 2>/dev/null || echo "$PAUSED")
      if [ "$PAUSED" -gt "$BASE" ]; then
        note "paused task count rose from $BASE to $PAUSED - was a task paused unexpectedly?"
      fi
      echo "$PAUSED" > "$BASE_F"
    fi
  fi

  if [ -z "$ISSUES" ]; then
    echo '{"wakeAgent": false, "data": {"status": "ok"}}'
  else
    # JSON built without jq, so a degraded image can still report itself.
    JLIST=$(printf '%s' "$ISSUES" | tr '|' '\n' | sed 's/["\\]//g; s/.*/"&"/' | paste -sd, -)
    printf '{"wakeAgent": true, "data": {"status": "attention", "issues": [%s]}}\n' "$JLIST"
  fi
---
Only invoked when the health-check script found something. Summarize
`scriptOutput.issues` for the owner in one short message — what's stale,
newly paused, or missing from the environment, and since when. A missing
`jq`/`ncl` warning is an image/platform defect worth an upstream issue, not
something you can fix. Don't speculate about cause; report the fact and ask if
it's expected. Never pause or resume a task on your own from this task.
