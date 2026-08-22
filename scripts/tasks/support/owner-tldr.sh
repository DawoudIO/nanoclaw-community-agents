#!/bin/bash
set -uo pipefail
# Deps: bash, jq. No network, no credentials.
#
# THE DIGEST GATE. Work cadence and delivery cadence are different things, and
# conflating them is what turned this system into a notification stream.
#
# Sub-agents report whenever their gates fire — 21 tasks across four agents, on
# their own schedules, for good reasons (a mirror sync every 15 minutes, an
# advisory sweep every 4 hours). But the OWNER should not hear from us 21 times.
# So the lead no longer relays each report as it arrives: it appends a one-line
# entry to a queue, and this task turns the queue into ONE digest.
#
# The rule the owner actually asked for: batch everything, interrupt only for
# what's urgent. Urgency bypasses this queue entirely — the lead sends those
# immediately and does NOT enqueue them (see references/report-formats.md).
# This gate exists for the other 95%.
#
# Crash safety follows the same principle as every other ledger here:
# duplicates beat losses. The queue is ROTATED into a .processing file when we
# wake, and a leftover .processing from a previous run is folded back in — so a
# session that died mid-digest costs one repeated line, never a lost finding.
DATA="/workspace/agent/plugin-data/community-support"
mkdir -p "$DATA"
QUEUE="$DATA/digest-queue.jsonl"
PROC="$DATA/digest-queue.processing.jsonl"

# WHY THIS SURVIVES A RATE LIMIT.
# Gate scripts are bash and cost no tokens, so this runs on schedule whether or
# not the agent has budget left. If the lead is rate-limited the gate still
# rotates and still reports `digest-ready` — the agent simply never wakes, and
# .processing sits untouched. The next run folds the new queue into it, so the
# batch grows rather than disappearing, and the first run after the window
# reopens delivers everything. A usage limit delays the digest; it must never
# lose it.
DEFER_F="$DATA/digest-deferred-count"
DEFERRED=0
if [ -f "$PROC" ] && [ -s "$PROC" ]; then
  # A .processing file that still exists means the previous digest never got
  # sent — the agent deletes it only after the owner has it.
  DEFERRED=$(cat "$DEFER_F" 2>/dev/null || echo 0)
  case "$DEFERRED" in ''|*[!0-9]*) DEFERRED=0;; esac
  DEFERRED=$((DEFERRED+1))
  printf '%s' "$DEFERRED" > "$DEFER_F"
  if [ -f "$QUEUE" ]; then
    cat "$PROC" "$QUEUE" > "$PROC.merged" 2>/dev/null && mv "$PROC.merged" "$PROC"
    : > "$QUEUE"
  fi
elif [ -f "$QUEUE" ]; then
  mv "$QUEUE" "$PROC" 2>/dev/null || cp "$QUEUE" "$PROC"
  : > "$QUEUE"
  : > "$DEFER_F"
fi

if [ ! -s "${PROC:-/nonexistent}" ]; then
  # Nothing queued. This is the common case and it must cost nothing —
  # a day where no sub-agent had anything to say is a good day, not a gap.
  rm -f "$PROC"; : > "$DEFER_F"
  echo '{"wakeAgent": false, "data": {"status": "nothing-queued"}}'
  exit 0
fi

# Parse leniently: the queue is written by an agent, so a malformed line is a
# real possibility and must not lose the rest of the batch.
ITEMS=$(jq -c -s '.' "$PROC" 2>/dev/null || echo "")
if [ -z "$ITEMS" ]; then
  BAD=$(wc -l < "$PROC" | tr -d ' ')
  RAW=$(head -c 2000 "$PROC" | jq -Rs '.' 2>/dev/null || echo '""')
  printf '{"wakeAgent": true, "data": {"status": "queue-unparseable", "lines": %s, "raw_head": %s, "hint": "the digest queue has at least one malformed line - summarize from raw_head, then the queue is cleared on the next run"}}\n' \
    "$BAD" "$RAW"
  exit 0
fi

TOTAL=$(printf '%s' "$ITEMS" | jq 'length')
# Group by source agent so the digest can be organised without the model
# having to sort anything itself.
BY_SOURCE=$(printf '%s' "$ITEMS" | jq -c '
  group_by(.source // "unknown")
  | map({source: (.[0].source // "unknown"), count: length,
         entries: [.[] | {at: (.at // null), severity: (.severity // "info"), line: (.line // (.|tostring))}]})')
# Anything that slipped into the queue marked urgent is a process failure
# worth naming: urgent findings are supposed to bypass the queue.
MISFILED=$(printf '%s' "$ITEMS" | jq -c '[.[] | select((.severity // "info") == "urgent")]')
HAS_MISFILED=$(printf '%s' "$MISFILED" | jq 'length > 0')
OLDEST=$(printf '%s' "$ITEMS" | jq -r '[.[].at // empty] | sort | .[0] // ""')
# How overdue is this digest? Computed here so the agent never has to reason
# about dates, and so a backlog caused by a spent usage window is stated as a
# fact rather than inferred from a big batch.
AGE_H=null
if [ -n "$OLDEST" ]; then
  OE=$(date -u -d "$OLDEST" +%s 2>/dev/null || date -u -j -f %Y-%m-%dT%H:%M:%SZ "$OLDEST" +%s 2>/dev/null || echo "")
  case "$OE" in ''|*[!0-9]*) :;; *) AGE_H=$(( ( $(date +%s) - OE ) / 3600 ));; esac
fi

printf '{"wakeAgent": true, "data": {"status": "digest-ready", "total": %s, "oldest_entry": "%s", "oldest_age_hours": %s, "deferred_runs": %s, "by_source": %s, "misfiled_urgent": %s, "misfiled_present": %s}}\n' \
  "$TOTAL" "$OLDEST" "$AGE_H" "$DEFERRED" "$BY_SOURCE" "$MISFILED" "$HAS_MISFILED"
