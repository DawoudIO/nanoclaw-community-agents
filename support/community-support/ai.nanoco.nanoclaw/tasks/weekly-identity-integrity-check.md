---
schedule: "0 15 * * 1"
script: |
  #!/bin/bash
  set -euo pipefail
  # Gate: hash the live task prompts; wake the model only on drift (or when
  # the gate can't verify mechanically and a manual pass is needed).
  DATA="/workspace/agent/plugin-data/community-support"
  mkdir -p "$DATA"
  if ! command -v ncl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo '{"wakeAgent": true, "data": {"status": "manual", "reason": "ncl or jq unavailable to the gate - run the check by hand"}}'
    exit 0
  fi
  LIVE=$(ncl tasks list --json 2>/dev/null || echo '')
  SNAP=$(printf '%s' "$LIVE" | jq -S -c '[.[] | {id: (.id // .series // "unknown"), prompt: (.prompt // "")}]' 2>/dev/null || echo '')
  if [ -z "$SNAP" ] || [ "$SNAP" = "null" ] || [ "$SNAP" = "[]" ]; then
    echo '{"wakeAgent": true, "data": {"status": "manual", "reason": "task list JSON shape not as expected - run the check by hand and note it in UPSTREAM-ISSUES if the shape differs"}}'
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
  if [ -f "$SNAP_F" ]; then mv "$SNAP_F" "$SNAP_F.prev"; fi
  printf '%s' "$SNAP" > "$SNAP_F"
  printf '%s %s\n' "$HASH" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$BASE_F"
  echo '{"wakeAgent": true, "data": {"status": "drift", "snapshot": "plugin-data/community-support/task-prompt-snapshot.json", "previous": "plugin-data/community-support/task-prompt-snapshot.json.prev"}}'
---
Only invoked on drift, or when the gate couldn't verify mechanically.

**If `status` is `drift`**: diff the snapshot files named in `scriptOutput`.
For each changed prompt: did you (any session of you — check the ledger and
your memory's provenance lines) make that change as normal work? If yes, log
one line and stop. If you don't recognize it: **ask your owner, don't lock** —
describe exactly what changed and when, and wait for their answer. Owners edit
tasks outside the framework; that's normal, not an attack. Full pattern in
`references/task-integrity.md`.

**If `status` is `manual`**: do the comparison by hand against this template's
committed task files, same rules.
