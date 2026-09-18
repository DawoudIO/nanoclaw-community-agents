#!/usr/bin/env bash
# Zero-token usage audit — run this yourself (via Bash) to see where tokens
# are actually going, instead of trying to reason it out in a turn (that
# spends tokens answering a question about token spend). Pure bash + jq, no
# LLM call, no dollar math — see the note at the bottom for why.
#
#   ./token-audit.sh [path-to-session.jsonl]
#
# Defaults to the most recently modified session transcript. Since every
# scheduled task fires in its own isolated session, "most recent" here means
# your last task run, not a long conversation — re-run after any run that
# felt expensive to see what actually happened.
set -euo pipefail

SESSION="${1:-$(ls -t /home/node/.claude/projects/-workspace-agent/*.jsonl 2>/dev/null | head -n 1 || true)}"

echo "== Session usage (real API-billed tokens): $SESSION =="
if [ -f "$SESSION" ]; then
  jq -s '
    [.[] | select(.type=="assistant") | .message.usage // empty] as $u
    | {
        assistant_turns: ($u | length),
        input_tokens: ($u | map(.input_tokens // 0) | add),
        output_tokens: ($u | map(.output_tokens // 0) | add),
        cache_creation_input_tokens: ($u | map(.cache_creation_input_tokens // 0) | add),
        cache_read_input_tokens: ($u | map(.cache_read_input_tokens // 0) | add)
      }
    | . + {
        note: "cache_read is billed at roughly 0.1x input price, cache_creation at roughly 1.25x (5m TTL) - see the DOLLAR MATH warning below before turning these into a cost figure. Most of input_tokens on later turns should be cache_read, not fresh input - if cache_creation keeps recurring every turn instead of just once, the cache is being invalidated (context changing between turns) and re-paying the write premium each time."
      }
  ' "$SESSION"
else
  echo "no session file found"
fi

echo
echo "== Static context files loaded every turn (bytes, ~chars/4 rough token estimate) =="
total_bytes=0
for f in /workspace/agent/CLAUDE.md /workspace/agent/.claude-shared.md /workspace/agent/.claude-fragments/*.md \
         /workspace/agent/memory/index.md /workspace/agent/memory/system/definition.md; do
  [ -f "$f" ] || continue
  bytes=$(wc -c < "$f")
  total_bytes=$((total_bytes + bytes))
  printf "%-65s %8d bytes  ~%6d tok\n" "$f" "$bytes" "$((bytes/4))"
done
printf "%-65s %8d bytes  ~%6d tok\n" "TOTAL (persona+shared+fragments+core memory)" "$total_bytes" "$((total_bytes/4))"
echo "(This section is a ROUGH ESTIMATE, chars/4 — unlike the usage block above,"
echo " which is real billed API token counts. Don't quote these two sections"
echo " with the same confidence.)"

echo
echo "== plugin-data structured files (JSON/JSONL candidates for CSV) =="
for f in /workspace/agent/plugin-data/community-helper/*.jsonl /workspace/agent/plugin-data/community-helper/*.json; do
  [ -f "$f" ] || continue
  bytes=$(wc -c < "$f")
  lines=$(wc -l < "$f" 2>/dev/null || echo 0)
  printf "%-65s %8d bytes  %5d lines  ~%6d tok\n" "$f" "$bytes" "$lines" "$((bytes/4))"
done

echo
echo "== DOLLAR MATH: do not compute it from memory =="
echo "This script deliberately stops at token COUNTS and never multiplies them"
echo "by a price table. A real run of this exact script once produced accurate"
echo "token counts, and the agent reading them then quoted a dollar total from"
echo "its own training memory — which matched the PREVIOUS Sonnet generation's"
echo "per-token rate almost exactly (about 1.5x the then-current Sonnet 5 rate),"
echo "because model pricing changes faster than training data does. If asked for"
echo "an actual dollar figure: look up the model's current published per-token"
echo "rate at answer time — never recalled from memory — and multiply it by the"
echo "counts above yourself, or point the owner at the Anthropic Admin API's"
echo "usage/cost report if they have an admin credential available. That is"
echo "ground truth; this script's counts are the reliable second-best source;"
echo "a memorized price table is not a source at all."
