---
schedule: "23 16 * * 1"
script: |
  #!/bin/bash
  set -uo pipefail
  # Deps: bash, awk. No network, no credentials — pure local-file logic.
  #
  # THE DROPPED-THREAD WATCH the persona has always promised.
  #
  # `instructions.md` tells the agent "the health check watches the ledger for
  # instructions acked but never closed, so a dropped thread surfaces
  # mechanically instead of the owner having to wonder." Until this task
  # existed, nothing did — the 4-agent era had a health-check task, the 2-agent
  # consolidation dropped it, and the persona's promise was never updated. An
  # owner instruction that got an `Ack #N` and then quietly died was invisible.
  #
  # WHAT THIS CANNOT SEE, stated plainly because it matters: an instruction the
  # agent never ledgered AT ALL. There is no `received` row for it, so there is
  # nothing here to go stale. This watches threads that were opened and
  # abandoned; it cannot watch threads that were never opened. Closing that
  # second gap needs a count of inbound owner messages to reconcile against,
  # which lives in the session mailbox DB (SQLite, not in this image's deps) —
  # a separate problem, deliberately not solved here rather than half-solved.
  DATA="/workspace/agent/plugin-data/community-manager"
  mkdir -p "$DATA"

  # --- local telemetry (best-effort; never blocks the gate) -------------------
  mkdir -p "$DATA/telemetry" 2>/dev/null || true
  exec > >(tee >(sed -u "s/^{/{\"_ts\":\"$(date -u +%FT%TZ)\",/" >> "$DATA/telemetry/owner-instruction-watch.jsonl" 2>/dev/null) 2>/dev/null)

  LEDGER="$DATA/owner-instructions.jsonl"
  if [ ! -s "$LEDGER" ]; then
    echo '{"wakeAgent": false, "data": {"status": "no-ledger-yet", "hint": "the manager appends one event line per owner instruction; nothing recorded yet"}}'
    exit 0
  fi

  # Stale threshold. The persona's own wording is "over 24h", so that is the
  # default rather than a number invented here.
  STALE_HOURS="${OWNER_ACK_STALE_HOURS:-24}"
  case "$STALE_HOURS" in ''|*[!0-9]*) STALE_HOURS=24;; esac
  CUTOFF=$(( $(date +%s) - STALE_HOURS * 3600 ))
  CUTOFF_ISO=$(date -u -d "@$CUTOFF" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
            || date -u -r "$CUTOFF" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
  if [ -z "$CUTOFF_ISO" ]; then
    echo '{"wakeAgent": true, "data": {"status": "date-unavailable", "hint": "neither GNU nor BSD date worked in this image"}}'
    exit 0
  fi

  # The ledger stays JSONL rather than CSV (the standing convention in
  # scripts/tasks/CONVENTIONS.md): its `gist` field is free-form owner wording
  # and will contain commas, which is the same reason digest-queue stayed JSON.
  # This reads it WITHOUT jq — three field extractions by regex — so the gate
  # keeps working on an install where jq was never added.
  #
  # Timestamps compare as STRINGS, which is correct only because they are full
  # ISO8601 and sort lexicographically. A bare date would sort before every
  # timestamped row of its own day and read as stale when it isn't.
  RESULT=$(awk -v cutoff="$CUTOFF_ISO" '
    function field(line, key,   v) {
      if (!match(line, "\"" key "\"[ ]*:[ ]*\"?[^,\"}]+")) return ""
      v = substr(line, RSTART, RLENGTH)
      sub("\"" key "\"[ ]*:[ ]*\"?", "", v)
      return v
    }
    {
      id = field($0, "id"); ev = field($0, "event"); ts = field($0, "ts")
      if (id == "" || ev == "") next
      if (ev == "received") { if (!(id in recv)) recv[id] = ts; if (!(id in closed)) closed[id] = 0 }
      else if (ev == "done" || ev == "blocked" || ev == "dropped") closed[id] = 1
    }
    END {
      n = 0; ids = ""; oldest = ""
      for (i in recv) {
        if (closed[i] == 1) continue
        if (recv[i] == "" || recv[i] >= cutoff) continue
        n++
        ids = ids (ids == "" ? "" : ",") sprintf("{\"id\":\"%s\",\"received\":\"%s\"}", i, recv[i])
        if (oldest == "" || recv[i] < oldest) oldest = recv[i]
      }
      printf "{\"count\":%d,\"oldest\":\"%s\",\"open\":[%s]}", n, oldest, ids
    }' "$LEDGER" 2>/dev/null || echo '')
  [ -z "$RESULT" ] && RESULT='{"count":0,"oldest":"","open":[]}'

  COUNT=$(printf '%s' "$RESULT" | sed 's/.*"count":\([0-9]*\).*/\1/')
  case "$COUNT" in ''|*[!0-9]*) COUNT=0;; esac

  if [ "$COUNT" -eq 0 ]; then
    echo '{"wakeAgent": false, "data": {"status": "quiet"}}'
  else
    printf '{"wakeAgent": true, "data": {"status": "stale-threads", "stale_hours": %s, "detail": %s}}\n' \
      "$STALE_HOURS" "$RESULT"
  fi
---
Only invoked when `scriptOutput.status` is `stale-threads` — one or more
owner instructions were ledgered `received` and never closed within
`stale_hours`.

For each entry in `scriptOutput.detail.open`: this is the exact gap the
persona describes — an instruction you acked and then went quiet on. Look up
its context in `owner-instructions.jsonl` yourself (the `id` is the join
key), figure out what actually happened to it, and close the loop for real:
if it's done, say so and log `done`; if it's genuinely still waiting on
something external, log `blocked` and say what; if it no longer applies,
log `dropped` and say why. Don't just log a closing event to silence this
gate — that's the exact failure this task exists to catch, one level deeper.

Tell the owner plainly which threads this caught, even the embarrassing
ones. The point of a mechanical check is that it doesn't spare you the
finding just because you're the one who dropped it.

**What this gate cannot see, and don't imply otherwise**: an instruction you
never ledgered at all has no `received` row, so there's nothing here to go
stale. This only catches threads that were opened and abandoned, not ones
that were never opened. If the owner references something you have no
record of acking, that's a different failure — say so directly rather than
treating this gate's silence as clearance.
