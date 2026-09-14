#!/bin/bash
set -euo pipefail
# Gate: hash the live task prompts; wake the model only on drift (or when
# the gate can't verify mechanically). The baseline is NOT self-healed on
# drift — the agent acks it after review, so a lost wake re-alerts next
# week instead of silently baselining tampered prompts as good.
DATA="/workspace/agent/plugin-data/community-manager"
mkdir -p "$DATA"

# --- local telemetry (best-effort; never blocks the gate) -------------------
# Mirrors this gate's one-line JSON output to a local per-task log so the
# owner can review wake/error patterns weekly and adjust gates or budgets.
# Not published anywhere (unlike ledger-publish's series) and not a source
# of truth -- a background pipe means a very fast exit can occasionally drop
# the last line, an accepted trade for never risking the gate's real output
# or exit code.
mkdir -p "$DATA/telemetry" 2>/dev/null || true
exec > >(tee >(sed -u "s/^{/{\"_ts\":\"$(date -u +%FT%TZ)\",/" >> "$DATA/telemetry/weekly-identity-integrity-check.jsonl" 2>/dev/null) 2>/dev/null)
if ! command -v ncl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo '{"wakeAgent": true, "data": {"status": "manual", "reason": "ncl or jq unavailable to the gate - run the check by hand"}}'
  exit 0
fi
LIVE=$(ncl tasks list --json 2>/dev/null || echo '')
SNAP=$(printf '%s' "$LIVE" | jq -S -c '[.[] | {id: (.id // .series // "unknown"), prompt: (.prompt // "")}]' 2>/dev/null || echo '')
if [ -z "$SNAP" ] || [ "$SNAP" = "null" ] || [ "$SNAP" = "[]" ]; then
  echo '{"wakeAgent": true, "data": {"status": "manual", "reason": "task list JSON shape not as expected - run the check by hand and note the shape in UPSTREAM-ISSUES"}}'
  exit 0
fi
HASH=$(printf '%s' "$SNAP" | sha256sum | cut -d' ' -f1)
BASE_F="$DATA/task-prompt-baseline"
SNAP_F="$DATA/task-prompt-snapshot.json"
OLD=$(cut -d' ' -f1 "$BASE_F" 2>/dev/null || echo "")
if [ -z "$OLD" ]; then
  printf '%s %s\n' "$HASH" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$BASE_F"
  printf '%s' "$SNAP" > "$SNAP_F"
  echo '{"wakeAgent": false, "data": {"status": "baseline-initialized"}}'
  exit 0
fi
if [ "$HASH" = "$OLD" ]; then
  echo '{"wakeAgent": false, "data": {"status": "no-drift"}}'
  exit 0
fi
printf '%s' "$SNAP" > "$SNAP_F.new"
printf '{"wakeAgent": true, "data": {"status": "drift", "new_hash": "%s", "current": "plugin-data/community-manager/task-prompt-snapshot.json.new", "last_acked": "plugin-data/community-manager/task-prompt-snapshot.json"}}\n' "$HASH"
