#!/bin/bash
set -euo pipefail
# Deps: bash, jq. No network — this gate only reads the local question ledger.
# The manager appends one line per resolved support conversation (see
# report-formats.md): {"date": "<ISO8601 datetime>", "topic": "<kebab-slug>",
# "channel": "<where>"}. This weekly gate clusters the last 60 days and wakes
# the agent only when a topic has repeated enough (3+) to deserve a docs page
# and hasn't already been proposed — every repeat question is permanent,
# measurable load on the maintainer, and unlike most community problems it
# has a fully mechanical fix.
DATA="/workspace/agent/plugin-data/community-manager"
mkdir -p "$DATA"

# --- local telemetry (best-effort; never blocks the gate) -------------------
# Mirrors this gate's one-line JSON output to a local per-task log so the
# owner can review wake/error patterns weekly and adjust gates or budgets.
# Not published anywhere (unlike ledger-publish's series) and not a source
# of truth -- a background pipe means a very fast exit can occasionally drop
# the last line, an accepted trade for never risking the gate's real output
# or exit code.
mkdir -p "$DATA/telemetry" 2>/dev/null || true
exec > >(tee >(sed -u "s/^{/{\"_ts\":\"$(date -u +%FT%TZ)\",/" >> "$DATA/telemetry/docs-gap-review.jsonl" 2>/dev/null) 2>/dev/null)
LEDGER="$DATA/question-ledger.csv"
if [ ! -s "$LEDGER" ]; then
  echo '{"wakeAgent": false, "data": {"status": "no-ledger-yet", "hint": "the manager appends one topic row per resolved support conversation; nothing recorded yet"}}'
  exit 0
fi
PROPOSED="$DATA/docs-proposals-sent.txt"
touch "$PROPOSED"
CUTOFF=$(( $(date +%s) - 5184000 ))

# Ledger is CSV: `date,topic,channel`. The whole pass — window filter,
# cluster, 3+ threshold, and the already-proposed exclusion — is one awk run
# over two files, replacing two jq passes and a --rawfile.
#
# Dates are compared as STRINGS, not parsed: rows carry a full ISO8601
# timestamp, awk has no date parser, and ISO8601 sorts lexicographically —
# which is exactly why the writer is required to use full timestamps. The
# cutoff is rendered to the same shape before comparing.
CUTOFF_ISO=$(date -u -d "@$CUTOFF" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
          || date -u -r "$CUTOFF" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
if [ -z "$CUTOFF_ISO" ]; then
  echo '{"wakeAgent": true, "data": {"status": "date-unavailable", "hint": "neither GNU nor BSD date worked in this image"}}'
  exit 0
fi

# Skip topics already proposed — the agent acks a proposal by appending the
# topic slug to docs-proposals-sent.txt AFTER handing the draft over, so a
# lost wake re-surfaces the topic next week. Duplicates beat losses.
#
# This exclusion was previously a jq gotcha that made the gate dead code: in
# `A | index(B)`, B is evaluated against A, so `index(.topic)` looked for
# `.topic` on the ARRAY — a hard error which, with stderr swallowed, silently
# yielded [] on every run. An awk set lookup has no equivalent trap.
NEW=$(awk -F, -v cutoff="$CUTOFF_ISO" -v proposed="$PROPOSED" '
  BEGIN {
    while ((getline line < proposed) > 0) if (line != "") sent[line] = 1
    close(proposed)
  }
  NR == 1 && $1 == "date" { next }
  NF >= 2 && $1 >= cutoff { count[$2]++ }
  END {
    printf "["; first = 1
    for (t in count) {
      if (count[t] < 3 || (t in sent)) continue
      if (!first) printf ","; first = 0
      printf "{\"topic\":\"%s\",\"count\":%d}", t, count[t]
    }
    printf "]"
  }' "$LEDGER" 2>/dev/null || echo '[]')
[ -z "$NEW" ] && NEW='[]'
if [ "$(printf '%s' "$NEW" | jq 'length')" -eq 0 ]; then
  echo '{"wakeAgent": false, "data": {"status": "quiet"}}'
else
  printf '{"wakeAgent": true, "data": {"status": "hot-topics", "topics": %s}}\n' "$NEW"
fi
