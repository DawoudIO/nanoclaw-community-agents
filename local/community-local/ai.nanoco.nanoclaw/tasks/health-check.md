---
schedule: "25 */3 * * *"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash + coreutils only. jq/ncl are checked for, not required — a
  # degraded image is itself a finding this gate must be able to report.
  DATA="/workspace/agent/plugin-data/community-local"
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

  # Owner-instruction ledger: anything acked >24h ago and never closed is a
  # dropped thread the owner should not have to discover by wondering.
  LEDGER="$DATA/owner-instructions.jsonl"
  if [ -f "$LEDGER" ] && command -v jq >/dev/null 2>&1; then
    STUCK=$(jq -s --argjson now "$(date +%s)" '[group_by(.id)[] | select([.[] | .event] | (index("done") == null and index("blocked") == null and index("dropped") == null)) | select((.[0].ts | fromdateiso8601? // $now) < ($now - 86400))] | length' "$LEDGER" 2>/dev/null || echo 0)
    if [ "${STUCK:-0}" -gt 0 ] 2>/dev/null; then
      note "$STUCK owner instruction(s) acked over 24h ago but never closed - check the owner-instructions ledger"
    fi
  fi

  # Alive heartbeat: a system that only speaks on problems is indistinguishable
  # from a dead one — if the sandbox process dies, every gate stops firing and
  # the silence looks exactly like a healthy quiet week. Once every 7 days,
  # wake even when everything is fine, so the owner sees a proof-of-life line;
  # its ABSENCE past ~8 days is the outage signal ("if I haven't said 'all
  # healthy' in over a week, the system itself is down — restart the sandbox").
  HB_F="$DATA/health-heartbeat-last"
  HB_DUE=false
  NOW_S=$(date +%s)
  HB_LAST=$(cat "$HB_F" 2>/dev/null || echo 0)
  case "$HB_LAST" in ''|*[!0-9]*) HB_LAST=0;; esac
  if [ $(( NOW_S - HB_LAST )) -ge 604800 ]; then HB_DUE=true; fi

  if [ -z "$ISSUES" ]; then
    if [ "$HB_DUE" = "true" ]; then
      echo "$NOW_S" > "$HB_F"
      echo '{"wakeAgent": true, "data": {"status": "heartbeat", "note": "weekly proof-of-life - environment checks passed"}}'
    else
      echo '{"wakeAgent": false, "data": {"status": "ok"}}'
    fi
  else
    # Any real wake also counts as proof-of-life.
    echo "$NOW_S" > "$HB_F"
    # JSON built without jq, so a degraded image can still report itself.
    JLIST=$(printf '%s' "$ISSUES" | tr '|' '\n' | sed 's/["\\]//g; s/.*/"&"/' | paste -sd, -)
    printf '{"wakeAgent": true, "data": {"status": "attention", "issues": [%s]}}\n' "$JLIST"
  fi
---
Only invoked when the health-check script found something — or for the weekly
proof-of-life heartbeat.

**If `status` is `heartbeat`**: this gate's own environment checks passed
(jq/ncl present, state.json fresh, no unexpected paused-task drift, no stuck
owner-instruction threads) — send your lead exactly one line, scoped
honestly: "Weekly environment heartbeat: no issues found as of <date/time>."
**Never say "all checks passed" or anything implying system-wide health** —
this task only checks its own environment, not other tasks' run outcomes. A
real install had this heartbeat land the same minute as a real
`repo-mirror-sync` failure, reading as a contradiction; the fix is scoping
the words, not widening what this gate checks (that would just duplicate
every other task's own failure reporting). This line's *absence* is the
outage signal: the owner knows that if more than ~8 days pass without it,
the sandbox process itself has died (nothing inside a dead system can report
its own death) and needs restarting on the host. Don't pad it into a report.

**If `status` is `attention`**: summarize `scriptOutput.issues` for your lead
in one short message — what's stale, newly paused, or missing from the
environment, and since when. A missing `jq`/`ncl` warning is an
image/platform defect worth an upstream issue, not something you can fix.
Don't speculate about cause; report the fact and ask if it's expected. Never
pause or resume a task on your own from this task.
