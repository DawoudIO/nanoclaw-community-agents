---
name: owner-tldr
schedule: "41 */2 * * *"
status: paused
script: |
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
  # THREE TIERS, because "how often" has three different right answers:
  #
  #   urgent    -> bypasses this queue entirely; the lead sends it the moment it
  #                happens (security, an outage, a decision that blocks work).
  #   attention -> escalated: digest within ~4h. This tier exists for findings
  #                that mean WE ARE BLIND — a degraded fetch, a failing
  #                credential, a gate that can't read a repo. health-check runs
  #                every 3h, and letting its finding sit in a queue until
  #                evening would waste the entire point of checking often.
  #   info      -> the daily TLDR at the owner's chosen hour. Routine.
  #
  # Why not simply digest every 2-4 hours: the digest is not in any
  # responsiveness path. Community responsiveness is unanswered-watch (every 10
  # minutes) plus the lead's live replies; nobody outside is waiting on this. A
  # fixed 4-hourly digest would therefore buy the OWNER six messages a day in
  # place of one, without making the system any faster for anyone else — which
  # is the notification stream this task was created to remove. The escalation
  # tier gets the responsiveness where it's actually needed and nowhere else.
  #
  # Crash safety follows the same principle as every other ledger here:
  # duplicates beat losses. The queue is ROTATED into a .processing file when we
  # wake, and a leftover .processing from a previous run is folded back in — so a
  # session that died mid-digest costs one repeated line, never a lost finding.
  DATA="/workspace/agent/plugin-data/community-support"
  mkdir -p "$DATA"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  # Hour (UTC, 0-23) for the routine daily digest. The gate runs every 2h but
  # only lets the ROUTINE tier through at this hour, so the owner gets a
  # predictable slot instead of one that drifts.
  TLDR_HOUR="${TLDR_HOUR:-18}"
  case "$TLDR_HOUR" in ''|*[!0-9]*) TLDR_HOUR=18;; esac
  [ "$TLDR_HOUR" -gt 23 ] && TLDR_HOUR=18
  ESCALATE_GAP_H=4          # min hours between escalated digests
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

  # --- which tier is pending, and may it go out now? ---------------------
  ATTENTION=$(printf '%s' "$ITEMS" | jq '[.[] | select((.severity // "info") == "attention")] | length')
  # digest-last-sent is written ONLY on a real delivery, so its ABSENCE means
  # "never sent" — not "sent long ago" and not "just anchored". Conflating those
  # is how the routine slot got ignored on a fresh install in one direction, and
  # how an attention item got held for 4 hours in the other.
  LAST_F="$DATA/digest-last-sent"
  NEVER_SENT=true
  HOURS_SINCE=0
  if [ -f "$LAST_F" ]; then
    LS=$(cat "$LAST_F" 2>/dev/null || echo 0)
    case "$LS" in ''|*[!0-9]*) LS=0;; esac
    if [ "$LS" -gt 0 ]; then
      NEVER_SENT=false
      HOURS_SINCE=$(( ( $(date +%s) - LS ) / 3600 ))
    fi
  fi
  HOUR_NOW=$(date -u +%-H 2>/dev/null || date -u +%H | sed 's/^0//')
  case "$HOUR_NOW" in ''|*[!0-9]*) HOUR_NOW=0;; esac

  WAKE=false; REASON=held
  # Escalated: something says we may be blind. Never wait for the evening slot,
  # and never wait on a clock that has never been set.
  if [ "$ATTENTION" -gt 0 ] && { [ "$NEVER_SENT" = "true" ] || [ "$HOURS_SINCE" -ge "$ESCALATE_GAP_H" ]; }; then
    WAKE=true; REASON=escalated
  # Routine: the owner's chosen hour, at most once for it.
  elif [ "$HOUR_NOW" -eq "$TLDR_HOUR" ] && { [ "$NEVER_SENT" = "true" ] || [ "$HOURS_SINCE" -ge 20 ]; }; then
    WAKE=true; REASON=routine
  # Safety net: the routine slot was missed entirely (a spent window, a restart).
  # Only meaningful once a real digest has been sent — otherwise "never sent"
  # would masquerade as "30 hours overdue" on a fresh install.
  elif [ "$NEVER_SENT" = "false" ] && [ "$HOURS_SINCE" -ge 30 ]; then
    WAKE=true; REASON=overdue
  fi

  # The queue is only rotated when we are actually going to deliver. Rotating on
  # a held run would hand the batch to a session that never starts, and the
  # fold-back would then have to undo it every 2 hours.
  if [ "$WAKE" = "false" ]; then
    # put it back so the next run sees one queue, not a split batch
    if [ -s "$PROC" ]; then
      if [ -s "$QUEUE" ]; then cat "$PROC" "$QUEUE" > "$QUEUE.m" && mv "$QUEUE.m" "$QUEUE"
      else cp "$PROC" "$QUEUE"; fi
      rm -f "$PROC"
    fi
    printf '{"wakeAgent": false, "data": {"status": "held", "pending": %s, "attention_pending": %s, "next_routine_hour_utc": %s}}\n' \
      "$TOTAL" "$ATTENTION" "$TLDR_HOUR"
    exit 0
  fi
  printf '%s' "$(date +%s)" > "$LAST_F"

  printf '{"wakeAgent": true, "data": {"status": "digest-ready", "trigger": "%s", "total": %s, "attention_pending": %s, "oldest_entry": "%s", "oldest_age_hours": %s, "deferred_runs": %s, "by_source": %s, "misfiled_urgent": %s, "misfiled_present": %s}}\n' \
    "$REASON" "$TOTAL" "$ATTENTION" "$OLDEST" "$AGE_H" "$DEFERRED" "$BY_SOURCE" "$MISFILED" "$HAS_MISFILED"
---

**One message a day. This is the only routine report the owner gets.**

Everything the sub-agents produced since the last digest is in
`scriptOutput.by_source`, already grouped by agent and counted. Your job is to
turn it into a single TLDR the owner can read in under a minute — not a
concatenation of what each agent said.

**If `status` is `nothing-queued`** you were not woken. Nothing to do.

**If `status` is `queue-unparseable`**: summarize what you can from
`raw_head`, say plainly that some entries could not be read, and note the
queue clears on the next run so nothing accumulates. Don't try to repair the
file.

## The shape

Follow `references/report-formats.md`, with the whole digest under ~200 words:

1. **Verdict line.** `ALL CLEAR` / `WATCHING` / `NEEDS YOU`, plus the single
   most important fact across everything.
2. **At most three items that matter**, each one line, each naming what
   changed and what to do. Not three per agent — three total.
3. **One rollup line** for the rest: *"plus 9 routine items across mirrors,
   metrics and hygiene — nothing needed."*

Never organise the digest by agent. The owner does not care which agent
noticed something; they care what needs them. `by_source` is grouped for your
convenience in reading it, not as an output template.

## Judgment, not aggregation

This is the one task where you are explicitly asked to **drop things**. A
sub-agent reporting "mirror synced, nothing notable" 14 times is 14 queue
entries and zero digest lines. If nothing in the whole batch needs the owner,
the correct output is one line: `ALL CLEAR — 12 routine items, nothing needs
you.` A digest that lists everything has failed at its only job.

Rank by *what happens if the owner never sees it*. An approved PR sitting 30
days outranks a follower count. A degraded fetch outranks both, because it
means we are blind rather than fine.

## When the digest is late — `deferred_runs` and `oldest_age_hours`

`deferred_runs > 0` means one or more previous digests never reached the
owner, and this batch is the accumulation. The usual cause is the usage window
running out: the gate is bash and costs nothing, so it kept running and kept
folding new entries in, but there was no budget left to wake you. **Nothing
was lost — it was delayed.**

Say so in one clause, up front: *"covering 3 days (digest was delayed by
usage limits)."* The owner needs to know the gap was a delay and not a quiet
period, because those two look identical from the outside and only one of them
is fine.

**A backlog is not permission to write more.** A three-day batch gets the same
≤3 items and the same ~200 words as a one-day batch — arguably fewer, since
older routine entries have aged into irrelevance. Prefer "the two things that
still matter from the last 3 days" over a chronological catch-up. If something
in the backlog needed the owner two days ago and still does, that is the
verdict line.

`oldest_age_hours` above roughly 26 with `deferred_runs` at 0 means the queue
is filling but this task isn't delivering — flag that as a wiring problem, not
a busy week.

## `misfiled_present`

True means something was queued with severity `urgent`. Urgent findings are
supposed to bypass this queue and go straight to the owner when they happen —
so this is a real process failure, not just a routing detail. Lead the digest
with the item itself, then say in one clause that it should have arrived
immediately, so the owner knows the fast path may be broken.

## After you post

Delete `plugin-data/community-support/digest-queue.processing.jsonl`. The gate
deliberately does not clear it for you: if this session dies before posting,
that file is the only copy of the batch, and the next run folds it back in.
Deleting it is your confirmation that the digest actually reached the owner —
so delete it **after** sending, never before.
