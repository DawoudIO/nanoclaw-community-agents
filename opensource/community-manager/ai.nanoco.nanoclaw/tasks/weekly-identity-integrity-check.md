---
schedule: "45 15 * * 1"
script: |
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
  # Not published anywhere (unlike project-health's series) and not a source
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
  # jq here, deliberately: this is `ncl`'s JSON output, not a file we wrote.
  # Hand-parsing an API/CLI JSON payload with grep is the fragile-parser trap —
  # grep belongs on OUR OWN csv state, below, where the shape is fixed.
  LIVE_TSV=$(printf '%s' "$LIVE" | jq -r '.[] | [(.id // .series // "unknown"), ((.prompt // "") | @base64)] | @tsv' 2>/dev/null || echo '')
  if [ -z "$LIVE_TSV" ]; then
    echo '{"wakeAgent": true, "data": {"status": "manual", "reason": "task list JSON shape not as expected - run the check by hand and note the shape in UPSTREAM-ISSUES"}}'
    exit 0
  fi

  # One sha256 per task rather than one global hash over everything. The old
  # single-hash design could only ever report "something drifted"; per-task
  # hashes name WHICH prompt changed, which is the actionable half of a tamper
  # alert. Hashing the base64 is equivalent to hashing the prompt (1:1 mapping)
  # and saves decoding it back.
  #
  # Storing hashes, not prompt text, also means this file stops carrying a
  # second copy of every prompt. The trade is deliberate: on drift you learn
  # which task changed but not the old text — and the right thing to diff
  # against was never this local copy anyway, it's the task file in the
  # template repo, which is the actual source of truth for what a prompt
  # should say.
  HASH_F="$DATA/task-prompt-hashes.csv"
  NEW_CSV="task_id,prompt_sha256"
  while IFS=$'\t' read -r id b64; do
    [ -z "$id" ] && continue
    h=$(printf '%s' "$b64" | sha256sum | cut -d' ' -f1)
    NEW_CSV="$NEW_CSV
  $id,$h"
  done <<EOF
  $LIVE_TSV
  EOF

  if [ ! -s "$HASH_F" ]; then
    printf '%s\n' "$NEW_CSV" > "$HASH_F"
    echo '{"wakeAgent": false, "data": {"status": "baseline-initialized"}}'
    exit 0
  fi

  # Compare with awk in ONE pass over both files — no jq, no per-task grep
  # subprocess. Drifted = id present in both with a different hash; added and
  # removed are reported separately because an unexpectedly REMOVED task is as
  # much a tamper signal as a changed one.
  DRIFT=$(printf '%s\n' "$NEW_CSV" | awk -F, -v basefile="$HASH_F" '
    BEGIN {
      while ((getline line < basefile) > 0) {
        split(line, f, ",")
        if (f[1] == "task_id") continue
        base[f[1]] = f[2]
      }
      close(basefile)
    }
    NR == 1 { next }
    {
      seen[$1] = 1
      if (!($1 in base)) { added = added " " $1 }
      else if (base[$1] != $2) { drifted = drifted " " $1 }
    }
    END {
      for (k in base) if (!(k in seen)) removed = removed " " k
      sub(/^ /, "", drifted); sub(/^ /, "", added); sub(/^ /, "", removed)
      print drifted "|" added "|" removed
    }')
  DRIFTED_IDS=$(printf '%s' "$DRIFT" | cut -d'|' -f1)
  ADDED_IDS=$(printf '%s' "$DRIFT" | cut -d'|' -f2)
  REMOVED_IDS=$(printf '%s' "$DRIFT" | cut -d'|' -f3)

  if [ -z "$DRIFTED_IDS$ADDED_IDS$REMOVED_IDS" ]; then
    echo '{"wakeAgent": false, "data": {"status": "no-drift"}}'
    exit 0
  fi

  # NOT self-healed: the new hashes go to a .new file and the acked baseline is
  # left alone, so a lost wake re-alerts next week instead of silently
  # baselining tampered prompts as good.
  printf '%s\n' "$NEW_CSV" > "$HASH_F.new"
  printf '{"wakeAgent": true, "data": {"status": "drift", "drifted": "%s", "added": "%s", "removed": "%s", "current": "plugin-data/community-manager/task-prompt-hashes.csv.new", "last_acked": "plugin-data/community-manager/task-prompt-hashes.csv"}}\n' \
    "$DRIFTED_IDS" "$ADDED_IDS" "$REMOVED_IDS"
---
Only invoked on drift, or when the gate couldn't verify mechanically.

**If `status` is `drift`**: diff the file named in `scriptOutput.current`
against `scriptOutput.last_acked`. For each changed prompt: did you (any
session of you — check the ledger and your memory's provenance lines) make
that change as normal work? If yes, log one line. If you don't recognize it:
**ask your owner, don't lock** — describe exactly what changed and when, and
wait for their answer. Owners edit tasks outside the framework; that's normal,
not an attack. Full pattern in `references/task-integrity.md`.

**Ack only after the review is resolved** (self-authored, or owner confirmed):
write `scriptOutput.new_hash` + a timestamp as the single line of
`plugin-data/community-manager/task-prompt-baseline`, and move the `.new`
snapshot over the acked one. Until you ack, this re-alerts weekly — by design:
an unreviewed drift must never become the silent new normal.

**If `status` is `manual`**: do the comparison by hand against this template's
committed task files, same rules.
