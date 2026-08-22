---
schedule: "15 15 * * 2"
script: |
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
  DATA="/workspace/agent/plugin-data/community-support"
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
---
Only invoked when a support topic has been asked 3+ times in the last 60 days
and no docs page has yet been proposed for it — the ledger the gate reads is
the one you append to after every resolved support conversation (see
`report-formats.md`, "Support conversation summary").

For each topic in `scriptOutput.topics`:

1. **Verify the gap is real**: search the project's docs site for the topic.
   If a page already answers it, the gap is discoverability, not absence —
   propose improving that page's title/keywords instead of a new page, and
   say which page.
2. **Draft the docs proposal**: what page, what question it answers (quote
   the actual recurring question, anonymized), and a first-draft outline
   built from the answers you've actually been giving — you've written this
   content 3+ times already; this is consolidation, not invention.
3. **Route it**: hand the draft to your owner as a docs issue proposal (or,
   the coding agent can draft the page's content for you, but it cannot open
   a PR — its token is read-only, so anything that lands is yours or a
   human's to create). Follow the project's docs style rules from your config.
4. **Then ack**: append the topic slug (one per line, exactly as it appears
   in `scriptOutput.topics[].topic`) to
   `plugin-data/community-support/docs-proposals-sent.txt` — your write after
   handing off is the acknowledgment, so a lost wake re-surfaces the topic
   next week instead of it vanishing. Duplicates beat losses.

Never publish a docs page directly from this task — you draft and propose;
a human (or the reviewed PR pipeline) publishes.
