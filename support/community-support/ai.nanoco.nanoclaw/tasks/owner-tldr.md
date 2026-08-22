---
schedule: "41 */2 * * *"
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
  # WHEN the owner gets the digest, in THEIR LOCAL TIME — 07:00 by default,
  # because the point is that they are awake and can act on it. A digest that
  # lands at 3am is read at 7am anyway, having spent a wake to arrive early.
  #
  # The kit pins the container to TZ=UTC, so cron lines are UTC and cannot know
  # the owner's zone. This gate is the one place that can: it runs every 2h and
  # decides for itself whether it is 07:00 where the owner is. That means no
  # cron arithmetic at onboarding and no re-editing anything when DST shifts.
  OWNER_TZ="${OWNER_TZ:-UTC}"
  TLDR_LOCAL_HOUR="${TLDR_LOCAL_HOUR:-7}"
  case "$TLDR_LOCAL_HOUR" in ''|*[!0-9]*) TLDR_LOCAL_HOUR=7;; esac
  [ "$TLDR_LOCAL_HOUR" -gt 23 ] && TLDR_LOCAL_HOUR=7
  ESCALATE_GAP_H=4          # min hours between escalated digests

  # An unknown TZ makes `date` fall back to UTC SILENTLY — verified, and it is
  # the dangerous case: the owner would be told 07:00 local and quietly get
  # whatever 07:00 UTC happens to be for them. So check the zoneinfo entry
  # exists and say so when it doesn't, rather than being confidently wrong.
  TZ_OK=true
  if [ "$OWNER_TZ" != "UTC" ] && [ ! -f "/usr/share/zoneinfo/$OWNER_TZ" ]; then
    TZ_OK=false
    OWNER_TZ=UTC
  fi
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
  HOUR_NOW=$(TZ="$OWNER_TZ" date +%-H 2>/dev/null || TZ="$OWNER_TZ" date +%H | sed 's/^0//')
  case "$HOUR_NOW" in ''|*[!0-9]*) HOUR_NOW=0;; esac
  # Waking window, derived from the one answer we already have rather than asking
  # for two more: it opens when the digest lands and runs 15 hours. Escalations
  # are held outside it — see the wake rules below.
  WAKE_END=$(( (TLDR_LOCAL_HOUR + 15) % 24 ))
  AWAKE=false
  if [ "$WAKE_END" -gt "$TLDR_LOCAL_HOUR" ]; then
    [ "$HOUR_NOW" -ge "$TLDR_LOCAL_HOUR" ] && [ "$HOUR_NOW" -lt "$WAKE_END" ] && AWAKE=true
  else
    # window wraps past midnight
    { [ "$HOUR_NOW" -ge "$TLDR_LOCAL_HOUR" ] || [ "$HOUR_NOW" -lt "$WAKE_END" ]; } && AWAKE=true
  fi

  WAKE=false; REASON=held
  # Escalated: something says we may be blind. Jump the queue — but only while
  # the owner is actually awake. Escalating at 3am spends a wake to deliver
  # something that still is not read until morning, when the routine digest
  # would have carried it for free.
  if [ "$ATTENTION" -gt 0 ] && [ "$AWAKE" = "true" ] \
     && { [ "$NEVER_SENT" = "true" ] || [ "$HOURS_SINCE" -ge "$ESCALATE_GAP_H" ]; }; then
    WAKE=true; REASON=escalated
  # Routine: the owner's chosen hour, at most once for it.
  elif [ "$HOUR_NOW" -eq "$TLDR_LOCAL_HOUR" ] && { [ "$NEVER_SENT" = "true" ] || [ "$HOURS_SINCE" -ge 20 ]; }; then
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
    printf '{"wakeAgent": false, "data": {"status": "held", "pending": %s, "attention_pending": %s, "owner_local_hour": %s, "digest_local_hour": %s, "owner_awake": %s, "tz": "%s", "tz_resolved": %s}}\n' \
      "$TOTAL" "$ATTENTION" "$HOUR_NOW" "$TLDR_LOCAL_HOUR" "$AWAKE" "$OWNER_TZ" "$TZ_OK"
    exit 0
  fi
  printf '%s' "$(date +%s)" > "$LAST_F"

  printf '{"wakeAgent": true, "data": {"status": "digest-ready", "trigger": "%s", "total": %s, "attention_pending": %s, "owner_local_hour": %s, "tz": "%s", "tz_resolved": %s, "oldest_entry": "%s", "oldest_age_hours": %s, "deferred_runs": %s, "by_source": %s, "misfiled_urgent": %s, "misfiled_present": %s}}\n' \
    "$REASON" "$TOTAL" "$ATTENTION" "$HOUR_NOW" "$OWNER_TZ" "$TZ_OK" "$OLDEST" "$AGE_H" "$DEFERRED" "$BY_SOURCE" "$MISFILED" "$HAS_MISFILED"
---

**One message a day, at 07:00 the owner's local time — the only routine report
they get.** Everything the sub-agents produced since the last digest is in
`by_source`, grouped and counted.

**The shape, in full:** a verdict line (`ALL CLEAR` / `WATCHING` / `NEEDS YOU`)
plus the single most important fact → at most **three** items that matter, each
with its comparison and one action → **one** rolled-up line for everything
steady. Under ~200 words. Never organised by agent.

**Read `references/owner-digest.md` before writing.** It carries the craft: why
07:00 changes the wording, how to rank, and the rule that makes this work —
this is the one task explicitly asked to **drop** things. Fourteen "mirror
synced, nothing notable" entries are fourteen queue lines and zero digest lines.
A digest that lists everything has failed at its only job.

## The branches

**`nothing-queued`** — you were not woken. Nothing to do.

**`queue-unparseable`** — summarize what you can from `raw_head`, say plainly
that some entries could not be read, and note the queue clears next run so
nothing accumulates. Don't try to repair the file.

**`trigger`** tells you which tier woke you:
- `routine` — the 07:00 brief.
- `escalated` — something marked `attention` jumped the queue during the
  owner's waking hours. Lead with it and say why it couldn't wait.
- `overdue` — the morning slot was missed entirely.

**`deferred_runs > 0`** — previous digests never reached the owner (usually a
spent usage window) and this is the accumulation. Nothing was lost, it was
delayed: say so in one clause up front, because a delay and a quiet period look
identical from outside. See the reference for how to write a late one.

**`oldest_age_hours` > ~26 with `deferred_runs` at 0** — the queue is filling
but this task isn't delivering. That's a wiring problem, not a busy week.

**`misfiled_present: true`** — something was queued as `urgent`. Urgent is
supposed to bypass this queue and arrive immediately, so this is a process
failure, not a routing detail. Lead with the item, then note in one clause that
it should have arrived immediately — the fast path may be broken.

**`tz_resolved: false`** — `OWNER_TZ` could not be resolved, so this ran on UTC
and "07:00" is not their 07:00. One line: the fix is a valid IANA zone name
(`Europe/Berlin`, not `UTC+1`) in `config.env`.

## After you post

Delete `plugin-data/community-support/digest-queue.processing.jsonl`. The gate
deliberately does not clear it: if this session dies before posting, that file
is the only copy of the batch and the next run folds it back in. Deleting it is
your confirmation the digest reached the owner — so delete it **after** sending,
never before.
