#!/bin/bash
set -euo pipefail
# Deps: bash, jq, ncl. NO network and NO credentials — this gate only reads
# local state, which is why it keeps working when everything cloud-facing
# doesn't.
#
# Purpose: the lead is the public voice, but when its usage window runs out it
# stops replying and the community hears silence. Response delay is the
# strongest predictor of whether someone comes back, so silence is the worst
# failure this system has. This gate notices unanswered support messages and
# wakes the LOCAL agent (which has no window to run out of) to post a holding
# acknowledgment.
#
# It deliberately does NOT call any API to check the lead's health: "did a
# human's message go unanswered" is the signal that matters, and it's true
# whether the cause is rate limits, a crashed session, or a wiring fault.
DATA="/workspace/agent/plugin-data/community-secretary"
mkdir -p "$DATA"
if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
# Minutes a support-tier message may go unanswered before we acknowledge it.
# MUST be a bare integer. It is used inside $(( )), where bash resolves a bare
# name recursively as an arithmetic variable — so a human-friendly value like
# "20 minutes" makes bash look up `minutes`, which under `set -u` is a FATAL
# error that produces no output at all. This gate runs every 10 minutes and is
# the one thing standing between a rate-limited lead and total silence, so it
# must never die on a config typo: fall back to the default instead.
GRACE="${ACK_GRACE_MINUTES:-20}"
case "$GRACE" in
  ''|*[!0-9]*) GRACE=20;;
esac
SEEN="$DATA/acknowledged.txt"
touch "$SEEN"

if ! command -v ncl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo '{"wakeAgent": false, "data": {"status": "degraded", "hint": "ncl or jq unavailable to this gate - cannot see inbound messages"}}'
  exit 0
fi

# Inbound support-tier messages, newest first. Shape varies by NanoClaw
# version, so treat an unexpected shape as "cannot tell" rather than "nothing
# to do" — a false quiet here means a community member gets silence.
RAW=$(ncl messages list --json 2>/dev/null || echo '')
if [ -z "$RAW" ] || ! printf '%s' "$RAW" | jq -e 'type=="array"' >/dev/null 2>&1; then
  echo '{"wakeAgent": false, "data": {"status": "cannot-read-messages", "hint": "ncl messages list gave an unexpected shape - verify the command on this NanoClaw version before trusting this task"}}'
  exit 0
fi

CUTOFF=$(( $(date +%s) - GRACE * 60 ))
PENDING=$(printf '%s' "$RAW" | jq -c --argjson c "$CUTOFF" --rawfile seen "$SEEN" '
  ($seen | split("\n") | map(select(length > 0))) as $done
  | [ .[]
      | select((.direction // "inbound") == "inbound")
      | select((.answered // false) == false)
      | select(((.created_at // empty) | fromdateiso8601? // 0) < $c)
      | select((.id // .message_id // "" | tostring) as $i | ($i | IN($done[]) | not))
      | {id: ((.id // .message_id) | tostring),
         channel: (.channel // .messaging_group // "unknown"),
         sender: (.sender // .author // "unknown"),
         excerpt: ((.text // .body // "") | tostring | .[0:160])} ]' 2>/dev/null || echo '[]')

if [ "$(printf '%s' "$PENDING" | jq 'length')" -eq 0 ]; then
  echo '{"wakeAgent": false, "data": {"status": "all-answered"}}'
else
  printf '{"wakeAgent": true, "data": {"status": "unanswered", "grace_minutes": %s, "messages": %s}}\n' "$GRACE" "$PENDING"
fi
