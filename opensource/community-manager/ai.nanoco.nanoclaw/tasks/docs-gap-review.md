---
schedule: "3 2 * * *"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, jq. No network — this gate only reads the local question ledger.
  # The manager appends one line per resolved support conversation (see
  # report-formats.md): {"date": "<ISO8601 datetime>", "topic": "<kebab-slug>",
  # "channel": "<where>"}. This weekly gate clusters the last 60 days and wakes
  # the agent when a question was answered that the person could not have found
  # in the docs, and no page has been opened for it yet — every repeat question is permanent,
  # measurable load on the maintainer, and unlike most community problems it
  # has a fully mechanical fix.
  DATA="/workspace/agent/plugin-data/community-manager"
  mkdir -p "$DATA"

  # --- local telemetry (best-effort; never blocks the gate) -------------------
  # Mirrors this gate's one-line JSON output to a local per-task log so the
  # owner can review wake/error patterns weekly and adjust gates or budgets.
  # Not published anywhere and not a source
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

  # Ledger is CSV: `date,topic,channel,in_docs`. `in_docs` is the agent's call
  # at answer time: `yes` if the person could have found the answer on the
  # docs site, `no` if the agent answered from code, a thread, or its own
  # knowledge. One `no` is a gap worth a page — not a repeat count. Rows with
  # no fourth column (older writers) are treated as `yes`, so they never open
  # a PR on their own. The whole pass — window filter, cluster, gap test, and
  # the already-proposed exclusion — is one awk run over two files.
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
    NF >= 2 && $1 >= cutoff { count[$2]++; if (NF >= 4 && $4 == "no") gap[$2]++ }
    END {
      printf "["; first = 1
      for (t in gap) {
        if (t in sent) continue
        if (!first) printf ","; first = 0
        printf "{\"topic\":\"%s\",\"count\":%d,\"not_in_docs\":%d}", t, count[t], gap[t]
      }
      printf "]"
    }' "$LEDGER" 2>/dev/null || echo '[]')
  [ -z "$NEW" ] && NEW='[]'
  if [ "$(printf '%s' "$NEW" | jq 'length')" -eq 0 ]; then
    echo '{"wakeAgent": false, "data": {"status": "quiet"}}'
  else
    printf '{"wakeAgent": true, "data": {"status": "docs-gaps", "topics": %s}}\n' "$NEW"
  fi
---

Only invoked when, in the last 60 days, you answered a question the person
could not have found on the docs site (`in_docs: no` in the question ledger
you append after every resolved support conversation — see
`report-formats.md`) and no page has been opened for it yet. One such
question is enough; it does not have to repeat. This runs nightly so a gap
becomes a PR within a day. `count` is how often the topic came up, `not_in_docs`
how many of those had no findable answer — context for the PR body, not a
threshold.

For each topic in `scriptOutput.topics`:

1. **Verify the gap is real**: search the project's docs site for the topic.
   If a page already answers it, the gap is discoverability — the PR edits
   that page's title, intro or keywords instead of adding a new one, and the
   PR body says so.
2. **Write the page** from the answer you actually gave — this is
   consolidation of a real answer, not invention. If you only answered once,
   re-read that thread and write exactly what resolved it. Follow `docs_style` from your config (a user manual: current
   behaviour, no version-history language) and the docs repo's own
   structure: look at two neighbouring pages first and match their
   front-matter, headings and tone. One page, or one edit to one page.
3. **Open the PR yourself** in the docs repo from your repo map (the `docs`
   entry and its path). Through the GitHub API, in this order:
   - new branch `docs/<topic-slug>` from the default branch (`GET
     git/ref/heads/<default>` → `POST git/refs`);
   - `PUT repos/{docs}/contents/{path}` with the file, `content` base64-encoded
     from the exact bytes (`base64 -w0`, or `-b 0` on BSD), on that branch;
   - **read it back before opening the PR**: `GET` the same path on the
     branch, decode, and `diff` against your draft. A real install once
     shipped corrupted files through this API; a mismatch means stop, delete
     the branch, and tell the owner — never open the PR;
   - `POST repos/{docs}/pulls`: title `docs: <page title>`, body = the
     recurring question (anonymised, quoted), how many times it was asked
     and where, links to the threads, and the line "Drafted by the community
     agent from support answers — please review before merging." Add the
     `documentation` label if the repo has it.
   - **Never merge, never approve, never push to the default branch.** A
     maintainer reviews it like any other PR.
4. **Then ack**: append the topic slug (one per line, exactly as it appears
   in `scriptOutput.topics[].topic`) to
   `plugin-data/community-manager/docs-proposals-sent.txt`, and enqueue one
   digest line (`source: docs-gap-review`, `info`): `"opened docs PR #N for
   <topic> (asked 4×, 3 with no findable answer)"`. Your write after the PR is the
   acknowledgment, so a lost wake re-surfaces the topic tomorrow instead of
   it vanishing. Duplicates beat losses — but check the docs repo for an open
   `docs/<topic-slug>` branch first, so a lost ack does not open a second PR.

If the docs repo is not in your repo map, or the token cannot write to it
(a `403` on the branch or file call), do not fall back to anything: enqueue
an `attention` line saying exactly that, and leave the topic unacked so it
returns tomorrow.
