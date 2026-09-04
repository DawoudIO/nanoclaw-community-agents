---
schedule: "17 5 * * *"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, find. No network, no credentials, no LLM wake ever — pure
  # filesystem housekeeping.
  #
  # WHY THIS EXISTS. NanoClaw's own agent-runner writes a full re-serialization
  # of the entire conversation to a NEW file in this directory every time its
  # PreCompact hook fires — not incremental, not appended, and nothing in the
  # platform ever cleans this directory up (confirmed via source,
  # container/agent-runner/src/providers/claude.ts's archiveTranscriptFile).
  # A real install saw 264 such files in one day on one container (188MB),
  # each one bigger than the last, and it is a strong candidate cause of a
  # real OOM crash loop that day. Filed upstream: nanocoai/nanoclaw#3716.
  # Until that's fixed at the source, this keeps disk usage bounded instead of
  # growing unboundedly for as long as the container lives.
  #
  # Deliberately wakeAgent:false, always — there is nothing here that needs
  # judgment, and waking the model to review "N old files deleted" would cost
  # real tokens for zero value.
  DIR="${NANOCLAW_CONVERSATIONS_DIR:-/workspace/agent/conversations}"
  KEEP_DAYS="${CONVERSATION_ARCHIVE_KEEP_DAYS:-3}"
  case "$KEEP_DAYS" in
    ''|*[!0-9]*) KEEP_DAYS=3;;
  esac

  if [ ! -d "$DIR" ]; then
    echo '{"wakeAgent": false, "data": {"status": "no-directory"}}'
    exit 0
  fi

  REMOVED=$(find "$DIR" -maxdepth 1 -type f -mtime "+$KEEP_DAYS" -print -delete 2>/dev/null | wc -l | tr -d ' ')
  printf '{"wakeAgent": false, "data": {"status": "ok", "removed": %s, "keep_days": %s}}\n' "${REMOVED:-0}" "$KEEP_DAYS"
---
Purely mechanical housekeeping — you are never woken for this
(`wakeAgent` is always `false`). Nothing here needs your judgment or a
report to anyone.

**Why this task exists**: NanoClaw's own agent-runner writes a full
re-serialization of the entire conversation to a new file in
`/workspace/agent/conversations/` every time its `PreCompact` hook fires —
not incremental, not appended — and nothing in the platform cleans that
directory up on its own. A real install saw 188MB in one day on one
container from this, and it's a strong candidate cause of a real OOM
crash loop. Filed upstream: [nanocoai/nanoclaw#3716](https://github.com/nanocoai/nanoclaw/issues/3716).
This task is the stopgap until that's fixed at the source — it keeps disk
usage bounded to a `CONVERSATION_ARCHIVE_KEEP_DAYS`-sized window
(default 3 days) instead of growing forever for as long as this
container lives.

If `status` is anything other than `ok` or `no-directory`, that's the one
case worth a human eventually noticing — but still nothing to act on
through this task itself.
