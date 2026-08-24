#!/bin/bash
# Diagnose (and optionally checkpoint) NanoClaw's SQLite databases.
#
#   bash scripts/db-health-check.sh <nanoclaw-root>               # diagnose only (safe, read-only)
#   bash scripts/db-health-check.sh <nanoclaw-root> --checkpoint  # + safe WAL checkpoint on healthy DBs
#
# WHY THIS EXISTS: a real install hit intermittent, "unrepairable" task-DB
# corruption repeatedly over one weekend, with no way to tell "corrupted"
# apart from "locked" from the ncl CLI's error text alone -- so it looked
# unrepairable when part of it might just have been contention. NanoClaw's
# own codebase already learned a version of this lesson once, for its
# per-session DBs (inbound.db/outbound.db -- see session-manager.ts's
# documented cross-mount invariants: journal_mode=DELETE, disabled mmap,
# busy_timeout=5000), but the CENTRAL db (where task/schedule state lives)
# never got the same protections -- still plain WAL mode, no busy_timeout.
# This script doesn't fix that platform gap (see UPSTREAM-ISSUES.md #18) --
# it gives you a fast, safe way to tell what's actually wrong before you
# touch anything, next time this happens.
#
# SAFE BY DESIGN: PRAGMA integrity_check and PRAGMA wal_checkpoint are both
# operations SQLite itself defines as always non-destructive, including
# against a database another process still has open. This script NEVER runs
# `.recover`, never deletes a file, and never touches a DB that fails its
# integrity check -- it prints the exact recovery command for a human to run
# themselves, because that step can silently lose rows and deserves a human
# decision, not a script's.
set -uo pipefail
ROOT="${1:-}"
CHECKPOINT=false
[ "${2:-}" = "--checkpoint" ] && CHECKPOINT=true

if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
  echo "usage: bash scripts/db-health-check.sh <nanoclaw-root> [--checkpoint]" >&2
  echo "  <nanoclaw-root> is the dir containing data/ (and groups/) -- wherever you run ncl/sbx from." >&2
  exit 1
fi

command -v sqlite3 >/dev/null 2>&1 || { echo "sqlite3 required -- not found on this host"; exit 1; }

DBS=$(find "$ROOT" -iname "*.db" 2>/dev/null | sort)
if [ -z "$DBS" ]; then
  echo "No .db files found under $ROOT -- is this the right directory?"
  exit 1
fi

BAD=0
TOTAL=0
while IFS= read -r db; do
  [ -z "$db" ] && continue
  TOTAL=$((TOTAL+1))
  echo "=== $db ==="

  # A large -wal file sitting next to a small/stale main db is the signature
  # of a checkpoint that never completed -- often from an unclean shutdown
  # (terminal closed, laptop slept, process killed) mid-write, which is the
  # single most common real-world cause of "SQLite corrupted, then cleared
  # itself, then corrupted again later."
  wal="${db}-wal"
  shm="${db}-shm"
  if [ -f "$wal" ]; then
    walsize=$(wc -c < "$wal" 2>/dev/null | tr -d ' ')
    dbsize=$(wc -c < "$db" 2>/dev/null | tr -d ' ')
    echo "  -wal present: ${walsize:-0} bytes (main db: ${dbsize:-0} bytes)"
    if [ "${walsize:-0}" -gt "${dbsize:-0}" ] && [ "${walsize:-0}" -gt 1048576 ]; then
      echo "  note: WAL is larger than the main DB and over 1MB -- checkpoint overdue"
    fi
  fi
  [ -f "$shm" ] && echo "  -shm present"

  RESULT=$(sqlite3 "$db" "PRAGMA integrity_check;" 2>&1)
  if [ "$RESULT" = "ok" ]; then
    echo "  integrity_check: OK"
  else
    BAD=$((BAD+1))
    echo "  integrity_check: FAILED"
    echo "$RESULT" | sed 's/^/    /'
    echo "  -> do NOT auto-repair. Back up first, then try the least-destructive path:"
    echo "       cp -r \"$ROOT/data\" \"$ROOT/data.backup.\$(date +%s)\""
    echo "       sqlite3 \"$db\" \".recover\" > \"${db}.recovered.sql\""
    echo "     Inspect the .sql output before rebuilding a fresh DB from it --"
    echo "     .recover can silently drop rows it can't parse, so \"ran without"
    echo "     error\" is not the same as \"nothing was lost.\""
  fi

  # Checkpointing a DB that just passed integrity_check is always safe --
  # it's SQLite's own recommended maintenance for a WAL-mode database, and
  # the one thing this script actually DOES rather than just reports. It's
  # also safe to run against a database another process still has open.
  if $CHECKPOINT && [ "$RESULT" = "ok" ]; then
    CKPT=$(sqlite3 "$db" "PRAGMA wal_checkpoint(TRUNCATE);" 2>&1)
    echo "  checkpoint: $CKPT"
  fi
  echo
done <<< "$DBS"

echo "----"
if [ "$BAD" -eq 0 ]; then
  echo "All $TOTAL database(s) pass integrity_check."
else
  echo "$BAD of $TOTAL database(s) failed integrity_check -- see above."
  echo "Do not ignore this: a task reading from one of these will keep failing"
  echo "until it's actually repaired, not just retried."
fi
