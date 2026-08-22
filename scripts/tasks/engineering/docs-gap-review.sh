#!/bin/bash
set -euo pipefail
# Deps: bash, jq. No network — this gate only reads the local question ledger.
# The lead appends one line per resolved support conversation (see
# report-formats.md): {"date": "<ISO8601 datetime>", "topic": "<kebab-slug>",
# "channel": "<where>"}. This weekly gate clusters the last 60 days and wakes
# the agent only when a topic has repeated enough (3+) to deserve a docs page
# and hasn't already been proposed — every repeat question is permanent,
# measurable load on the maintainer, and unlike most community problems it
# has a fully mechanical fix.
DATA="/workspace/agent/plugin-data/community-coding"
mkdir -p "$DATA"
LEDGER="$DATA/question-ledger.jsonl"
if [ ! -f "$LEDGER" ]; then
  echo '{"wakeAgent": false, "data": {"status": "no-ledger-yet", "hint": "the lead appends one topic line per resolved support conversation; nothing recorded yet"}}'
  exit 0
fi
PROPOSED="$DATA/docs-proposals-sent.txt"
touch "$PROPOSED"
CUTOFF=$(( $(date +%s) - 5184000 ))
HOT=$(jq -c -s --argjson c "$CUTOFF" '
  [ .[] | select(((.date // empty) | fromdateiso8601? // 0) >= $c) | .topic ]
  | group_by(.) | map({topic: .[0], count: length}) | map(select(.count >= 3))' \
  "$LEDGER" 2>/dev/null || echo '[]')
# Skip topics already proposed — the agent acks a proposal by appending the
# topic slug to docs-proposals-sent.txt AFTER handing the draft over, so a
# lost wake re-surfaces the topic next week. Duplicates beat losses.
# jq gotcha that made this gate dead code: in `A | index(B)`, B is evaluated
# against A — so `index(.topic)` looked for `.topic` on the ARRAY, which is a
# hard error, and with stderr swallowed it silently yielded [] every run.
# Pipe .topic into IN() instead, so it resolves against the element.
NEW=$(printf '%s' "$HOT" | jq -c --rawfile p "$PROPOSED" \
  '($p | split("\n") | map(select(length > 0))) as $sent
   | [ .[] | select(.topic | IN($sent[]) | not) ]' 2>/dev/null || echo '[]')
if [ "$(printf '%s' "$NEW" | jq 'length')" -eq 0 ]; then
  echo '{"wakeAgent": false, "data": {"status": "quiet"}}'
else
  printf '{"wakeAgent": true, "data": {"status": "hot-topics", "topics": %s}}\n' "$NEW"
fi
