#!/bin/bash
# Emit the authoritative task-reference table, derived from the task files.
#
#   bash scripts/gen-task-table.sh            # markdown table to stdout
#   bash scripts/gen-task-table.sh --counts   # just the headline counts
#   bash scripts/gen-task-table.sh --check    # verify docs match reality
#
# WHY THIS EXISTS: every doc that hand-wrote "18 tasks (7 lead, 7 coding,
# 4 coding)" went stale the moment the topology changed, and nothing
# caught it because prose isn't testable. The repo already knows how many
# tasks exist and who owns them. Docs should quote this, not restate it.
#
# --check is wired into scripts/test/run.sh so drift fails the harness
# instead of shipping.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-table}"

# group dir -> (label, model tier). Keep in sync with scripts/sync-tasks.sh.
group_label() {
  case "$1" in
    manager)     echo "Lead|Claude Sonnet";;
    engineering) echo "Reviewer|Claude Haiku";;
    *)           echo "?|?";;
  esac
}
group_dir() {
  case "$1" in
    manager)     echo "opensource/community-manager";;
    engineering) echo "opensource/community-coding";;
  esac
}

# Translate a 5-field cron into the words a human uses. Nobody reads
# "55 10 1 */3 *" and thinks "quarterly", which is why the schedule tables
# were unreadable even when they were correct.
cadence() {
  local mi ho dom mon dow
  read -r mi ho dom mon dow <<< "$1"
  local nh nm
  nm=$(printf '%s' "$mi" | awk -F, '{print NF}')
  nh=$(printf '%s' "$ho" | awk -F, '{print NF}')
  case "$mi" in
    */*) echo "every ${mi#*/} min"; return;;
  esac
  if [ "$ho" = "*" ]; then
    [ "$nm" -gt 1 ] && echo "${nm}× hourly" || echo "hourly"
    return
  fi
  case "$ho" in
    */*) echo "every ${ho#*/}h"; return;;
  esac
  # a specific hour: cadence is set by the day fields
  case "$mon" in
    */*) echo "quarterly"; return;;
  esac
  if [ "$dom" != "*" ]; then echo "monthly"; return; fi
  case "$dow" in
    '*') [ "$nh" -gt 1 ] && echo "${nh}× daily" || echo "daily";;
    *-*) echo "weekdays";;
    *,*) echo "twice weekly";;
    *)   echo "weekly";;
  esac
}
dow_name() {
  case "$1" in
    0) echo Sun;; 1) echo Mon;; 2) echo Tue;; 3) echo Wed;;
    4) echo Thu;; 5) echo Fri;; 6) echo Sat;; *) echo "";;
  esac
}
# Human "when": the clock time plus the day, in UTC.
when() {
  local mi ho dom mon dow
  read -r mi ho dom mon dow <<< "$1"
  case "$mi" in */*) echo "on the ${mi#*/}-minute mark"; return;; esac
  if [ "$ho" = "*" ]; then echo ":$(printf '%s' "$mi" | tr ',' '/') each hour"; return; fi
  case "$ho" in */*) case "$mi" in ''|*[!0-9]*) :;; *) mi=$(printf '%02d' "$mi");; esac; echo "every ${ho#*/}h at :$mi"; return;; esac
  local t
  # pad a bare numeric minute so 15:9 reads as 15:09
  case "$mi" in ''|*[!0-9]*) :;; *) mi=$(printf '%02d' "$mi");; esac
  t=$(printf '%s' "$ho" | awk -F, -v m="$mi" '{s="";for(i=1;i<=NF;i++){s=s sprintf("%02d:%s",$i,m); if(i<NF) s=s ", "}; print s}')
  case "$mon" in */*) echo "$t, day $dom every ${mon#*/} months"; return;; esac
  [ "$dom" != "*" ] && { echo "$t on day $dom"; return; }
  case "$dow" in
    '*') echo "$t";;
    1-5) echo "$t, Mon–Fri";;
    *,*) echo "$t, $(dow_name "${dow%%,*}")+";;
    *)   echo "$t, $(dow_name "$dow")";;
  esac
}

TOTAL=0; GATED=0; UNGATED=""
ROWS=""
for group in manager engineering; do
  gdir=$(group_dir "$group")
  label=$(group_label "$group"); agent="${label%%|*}"
  for md in "$ROOT/$gdir"/ai.nanoco.nanoclaw/tasks/*.md; do
    [ -f "$md" ] || continue
    name=$(basename "$md" .md)
    sched=$(grep -m1 '^schedule:' "$md" | sed 's/^schedule: *//; s/"//g')
    if [ -f "$ROOT/scripts/tasks/$group/$name.sh" ]; then
      gate="yes"; GATED=$((GATED+1))
    else
      gate="no"; UNGATED="$UNGATED $name"
    fi
    TOTAL=$((TOTAL+1))
    ROWS="$ROWS| \`$name\` | $agent | **$(cadence "$sched")** | $(when "$sched") | $gate |
"
  done
done

counts() {
  printf '%s tasks across 2 agents; %s script-gated' "$TOTAL" "$GATED"
  [ -n "$UNGATED" ] && printf ' (ungated:%s)' "$UNGATED"
  printf '\n'
}

case "$MODE" in
  --counts) counts;;
  --state)
    # What each task PERSISTS, derived from its gate script. Answers the
    # question "what data does this build, and is it kept?" without anyone
    # having to read 17 shell scripts.
    #
    # Two classes, and the distinction is the one that matters operationally:
    #   CACHE  — a cursor, a heartbeat stamp, a last-seen snapshot. Losing it
    #            costs one duplicate report or one re-fetch. Rebuildable.
    #   LEDGER — append-only history that CANNOT be re-fetched retroactively
    #            (a follower count for last Tuesday is gone). Losing it is
    #            permanent data loss, so these are what backup exists for.
    echo "| Task | Agent | Writes | Class |"
    echo "|------|-------|--------|-------|"
    for group in manager engineering; do
      gdir=$(group_dir "$group")
      label=$(group_label "$group"); agent="${label%%|*}"
      for md in "$ROOT/$gdir"/ai.nanoco.nanoclaw/tasks/*.md; do
        [ -f "$md" ] || continue
        name=$(basename "$md" .md)
        sh="$ROOT/scripts/tasks/$group/$name.sh"
        if [ ! -f "$sh" ]; then
          echo "| \`$name\` | $agent | _(no gate script — agent-written state only)_ | — |"
          continue
        fi
        files=$(grep -ohE '"\$DATA/[a-zA-Z0-9._-]+"' "$sh" 2>/dev/null \
                | tr -d '"$' | sed 's|DATA/||' | grep -v '^config\.env$' | sort -u)
        if [ -z "$files" ]; then
          echo "| \`$name\` | $agent | _nothing — stateless_ | — |"
          continue
        fi
        out=""; class=""
        for f in $files; do
          case "$f" in
            *.jsonl|*history*) c="LEDGER";;
            *)                 c="cache";;
          esac
          out="$out\`$f\` ($c)<br>"
          case "$c" in LEDGER) class="LEDGER";; *) [ -z "$class" ] && class="cache";; esac
        done
        echo "| \`$name\` | $agent | ${out%<br>} | $class |"
      done
    done
    echo
    echo "_LEDGER entries are append-only and cannot be re-fetched retroactively — a follower count for last Tuesday is gone once lost. Nothing backs them up (this set is rebuilt from scratch at repave time by design), so treat a long-running series as worth exporting by hand if you actually want to keep it. Everything marked cache is safe to delete; the task rebuilds it on its next run, at the cost of one duplicate report._"
    echo "_Generated by \`scripts/gen-task-table.sh --state\` — do not hand-edit._";;
  --check)
    # The one number docs are allowed to state in prose is the total, and
    # only in the form this script prints. Anything else is drift.
    BAD=0
    for f in "$ROOT"/README.md "$ROOT"/docs/OPERATIONS.md "$ROOT"/docs/INSTALL.md; do
      [ -f "$f" ] || continue
      # Stale agent-count language. There are two agents; a doc claiming
      # three or four has drifted.
      if grep -niE '(^|[^a-z])(all )?(three|four) (agents|templates)' "$f" >/dev/null; then
        echo "DRIFT $f: says 'three/four agents/templates' but there are 2"; BAD=1
      fi
      # stale task-count language: any "N of M tasks" or "all M tasks" where M != TOTAL
      while IFS= read -r m; do
        [ -z "$m" ] && continue
        [ "$m" = "$TOTAL" ] || { echo "DRIFT $f: task count '$m' should be $TOTAL"; BAD=1; }
      done < <(grep -ohE '(of|all) ([0-9]+) task' "$f" | grep -oE '[0-9]+')
    done
    # The ready-gate size is stated in CHECKPOINTS.md's own heading and quoted
    # by README.md and INSTALL.md. Three copies of one number drift the moment
    # a gate item is added — CHECKPOINTS is the authority.
    CP="$ROOT/docs/CHECKPOINTS.md"
    if [ -f "$CP" ]; then
      GATE=$(grep -oE 'ready gate — [0-9]+ points' "$CP" | grep -oE '[0-9]+' | head -1)
      if [ -n "$GATE" ]; then
        for f in "$ROOT/README.md" "$ROOT/docs/INSTALL.md"; do
          [ -f "$f" ] || continue
          while IFS= read -r n; do
            [ "$n" = "$GATE" ] || { echo "DRIFT $f: ready-gate count '$n' should be $GATE (CHECKPOINTS.md is authoritative)"; BAD=1; }
          done < <(grep -ohE '[0-9]+-point ready gate' "$f" | grep -oE '^[0-9]+')
        done
      fi
    fi

    if [ "$BAD" -eq 0 ]; then echo "task-table check OK: $(counts)"; fi
    exit $BAD;;
  *)
    echo "| Task | Agent | Cadence | When (UTC) | Gated |"
    echo "|------|-------|---------|------------|-------|"
    printf '%s' "$ROWS"
    echo
    echo "_$(counts)_"
    echo "_Generated by \`scripts/gen-task-table.sh\` — do not hand-edit._";;
esac
