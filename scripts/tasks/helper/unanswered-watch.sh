#!/bin/bash
set -euo pipefail
# Deps: bash, jq, ncl. NO network and NO credentials — this gate only reads
# local state, which is why it keeps working when everything cloud-facing
# doesn't.
#
# Purpose: the manager is the public voice, but when its usage window runs out it
# stops replying and the community hears silence. Response delay is the
# strongest predictor of whether someone comes back, so silence is the worst
# failure this system has. This gate notices unanswered support messages and
# wakes the HELPER to post a holding acknowledgment — a different agent
# group with its own session, so a manager that is rate-limited, crashed, or
# mis-wired does not take the acknowledgment down with it.
#
# It deliberately does NOT call any API to check the manager's health: "did a
# human's message go unanswered" is the signal that matters, and it's true
# whether the cause is rate limits, a crashed session, or a wiring fault.
#
# WHY `ncl sessions list` + `ncl sessions history`, AND NOT A "messages"
# COMMAND. There is no cross-agent-group message listing on this platform, by
# design (agent-group scoping) — do not go looking for one. What DOES exist,
# and is what makes this gate possible: the router writes every inbound
# message into every
# WIRED agent-group's own session regardless of whether that agent's engage
# mode ever triggers a reply (only the wake decision differs). So as long as
# this agent is silently wired to every support-tier channel (see
# welcome/SKILL.md §5c — `--engage-mode mention` on channels nobody ever
# @-mentions the Helper in), it has its own real, passive session per
# support channel, readable via `ncl sessions history` — scoped to its own
# agent group, which it's always allowed to see.
DATA="/workspace/agent/plugin-data/community-helper"
mkdir -p "$DATA"

# --- local telemetry (best-effort; never blocks the gate) -------------------
# Mirrors this gate's one-line JSON output to a local per-task log so the
# owner can review wake/error patterns weekly and adjust gates or budgets.
# Not published anywhere (unlike project-health's series) and not a source
# of truth -- a background pipe means a very fast exit can occasionally drop
# the last line, an accepted trade for never risking the gate's real output
# or exit code.
mkdir -p "$DATA/telemetry" 2>/dev/null || true
exec > >(tee >(sed -u "s/^{/{\"_ts\":\"$(date -u +%FT%TZ)\",/" >> "$DATA/telemetry/unanswered-watch.jsonl" 2>/dev/null) 2>/dev/null)
# config.env is parsed, never sourced: the model writes into this same
# directory, so a line planted here must stay a string, never become code.
if [ -f "$DATA/config.env" ]; then
  while IFS='=' read -r k v; do
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    export "$k=$v"
  done < <(grep -E '^[A-Z][A-Z0-9_]*=' "$DATA/config.env")
fi
# Minutes a support-tier message may go unanswered before we acknowledge it.
# MUST be a bare integer. It is used inside $(( )), where bash resolves a bare
# name recursively as an arithmetic variable — so a human-friendly value like
# "20 minutes" makes bash look up `minutes`, which under `set -u` is a FATAL
# error that produces no output at all. This gate runs every 10 minutes and is
# the one thing standing between a rate-limited manager and total silence, so it
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

# Only channel-backed, active sessions — this agent's own agent-shared or
# agent-to-agent sessions (messaging_group_id null) are never support
# channels and would only ever produce false positives here.
# Accept both a bare array and the `{ok, data: [...]}` wrapper: `ncl tasks
# list` turned out to be wrapped, and assuming a bare array there broke a
# live gate. The same unwrap is applied to `sessions history` below.
UNWRAP='(if type == "array" then . else (.data // null) end)'
SESSIONS=$(ncl sessions list --json 2>/dev/null | jq -c "$UNWRAP"' | [.[] | select(.status == "active") | select(.messaging_group_id != null)]' 2>/dev/null || echo '')
# A safety net that watches nothing fails silently, so both "can't read the
# sessions" and "no channel sessions at all" wake the agent ONCE when the
# state has lasted a day, then go quiet, and reset once sessions read fine.
# Both used to be wakeAgent:false every run while the prompt said to report
# them — an instruction that could never run. A live install did 851 of
# these quiet runs in a week: its Helper was never wired to the support
# channels. 144 runs a day means the wake has to be once, not every run.
say_once() {  # $1 status, $2 hint
  local since_f="$DATA/$1-since" ack_f="$DATA/$1-reported" since
  [ -s "$since_f" ] || date +%s > "$since_f"
  since=$(cat "$since_f" 2>/dev/null || echo 0); case "$since" in ''|*[!0-9]*) since=$(date +%s);; esac
  if [ ! -f "$ack_f" ] && [ $(( $(date +%s) - since )) -ge 86400 ]; then
    : > "$ack_f"
    printf '{"wakeAgent": true, "data": {"status": "%s", "persisting_hours": %s, "hint": "%s"}}\n' "$1" $(( ($(date +%s) - since) / 3600 )) "$2"
  else
    printf '{"wakeAgent": false, "data": {"status": "%s", "hint": "%s"}}\n' "$1" "$2"
  fi
  exit 0
}
if [ -z "$SESSIONS" ] || ! printf '%s' "$SESSIONS" | jq -e 'type=="array"' >/dev/null 2>&1; then
  say_once cannot-read-sessions "ncl sessions list gave an unexpected shape - verify the command on this NanoClaw version before trusting this task"
fi
rm -f "$DATA/cannot-read-sessions-since" "$DATA/cannot-read-sessions-reported"

if [ "$(printf '%s' "$SESSIONS" | jq 'length')" -eq 0 ]; then
  say_once no-channel-sessions "no active channel-backed sessions - this agent is not wired to any support channel, so the holding-ack safety net covers nothing (welcome/SKILL.md 5c)"
fi
rm -f "$DATA/no-channel-sessions-since" "$DATA/no-channel-sessions-reported"

CUTOFF=$(( $(date +%s) - GRACE * 60 ))
PENDING='[]'
DEGRADED='[]'
while IFS= read -r SESSION; do
  SID=$(printf '%s' "$SESSION" | jq -r '.id')
  MGID=$(printf '%s' "$SESSION" | jq -r '.messaging_group_id')
  # Small limit: only the newest message matters for "has the last thing
  # said here been answered", not a full transcript.
  HIST=$(ncl sessions history --id "$SID" --limit 3 --json 2>/dev/null | jq -c "$UNWRAP" 2>/dev/null || echo '')
  if [ -z "$HIST" ] || ! printf '%s' "$HIST" | jq -e 'type=="array"' >/dev/null 2>&1; then
    DEGRADED=$(jq -c --arg mgid "$MGID" '. + [$mgid]' <<< "$DEGRADED")
    continue
  fi
  # Newest row is last in the chronological array `sessions history` returns.
  LAST=$(printf '%s' "$HIST" | jq -c 'if length > 0 then .[-1] else null end')
  [ "$LAST" = "null" ] && continue

  IS_UNANSWERED=$(jq -r --argjson c "$CUTOFF" '
    (.direction == "in") and (((.timestamp | fromdateiso8601?) // $c) < $c)' <<< "$LAST" 2>/dev/null || echo false)
  [ "$IS_UNANSWERED" != "true" ] && continue

  # Dedup key: session + the exact timestamp of the unanswered message, so
  # the same still-unanswered message isn't re-acknowledged every 10 minutes,
  # but a NEW unanswered message in the same channel later still surfaces.
  KEY="${SID}:$(jq -r '.timestamp' <<< "$LAST")"
  if grep -qxF "$KEY" "$SEEN" 2>/dev/null; then continue; fi

  ENTRY=$(jq -c --arg key "$KEY" --arg mgid "$MGID" \
    '{key: $key, messaging_group_id: $mgid, sender: (.sender // "unknown"), excerpt: ((.text // "") | .[0:160])}' <<< "$LAST")
  PENDING=$(jq -c --argjson e "$ENTRY" '. + [$e]' <<< "$PENDING")
done < <(printf '%s' "$SESSIONS" | jq -c '.[]')

if [ "$(printf '%s' "$PENDING" | jq 'length')" -eq 0 ]; then
  if [ "$(printf '%s' "$DEGRADED" | jq 'length')" -gt 0 ]; then
    printf '{"wakeAgent": false, "data": {"status": "partial-fetch-failure", "degraded_messaging_groups": %s}}\n' "$DEGRADED"
  else
    echo '{"wakeAgent": false, "data": {"status": "all-answered"}}'
  fi
else
  printf '{"wakeAgent": true, "data": {"status": "unanswered", "grace_minutes": %s, "messages": %s, "degraded_messaging_groups": %s}}\n' "$GRACE" "$PENDING" "$DEGRADED"
fi
