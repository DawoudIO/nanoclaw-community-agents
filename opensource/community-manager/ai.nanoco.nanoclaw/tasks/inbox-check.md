---
schedule: "55 6,16 * * *"
script: |
  #!/bin/bash
  set -uo pipefail
  # Deps: bash, curl, jq. The Gmail OAuth bearer is injected by the OneCLI proxy
  # for gmail.googleapis.com — no credential belongs in this file.
  #
  # WHY THIS GATE EXISTS. inbox-check used to have no gate at all: it woke the
  # MANAGER — the Sonnet-tier agent — twice every day whether the inbox held
  # anything or not. That made it the most expensive guaranteed wake in the
  # system, and the cost was invisible because an empty inbox produces exactly
  # the same silent "nothing to report" turn as a broken one.
  #
  # The gate was assumed impossible on the theory that a mailbox is only
  # reachable through the agent's email MCP. That was wrong:
  # weekly-analytics-report already proves a bash gate can call a Google API
  # through the same proxy that injects the agent's own bearer, so Gmail's REST
  # API is reachable here on the identical path.
  #
  # WHAT IT DELIBERATELY DOES NOT DO: it never fetches subjects, senders, or
  # bodies — only message IDs, via `q=` metadata matching. Two reasons, both
  # load-bearing. A shared project inbox is exactly where a vulnerability
  # disclosure arrives (see this task's prompt), and the gate's JSON is mirrored
  # verbatim into a local telemetry log, so a subject line here would persist
  # private mail content to disk outside the agent's own context. The agent
  # reads the actual mail through its email MCP, where the escalation rules in
  # references/escalation-paths.md apply.
  DATA="/workspace/agent/plugin-data/community-manager"
  mkdir -p "$DATA"

  # --- local telemetry (best-effort; never blocks the gate) -------------------
  # Mirrors this gate's one-line JSON output to a local per-task log so the
  # owner can review wake/error patterns weekly and adjust gates or budgets.
  # Not published anywhere (unlike ledger-publish's series) and not a source
  # of truth -- a background pipe means a very fast exit can occasionally drop
  # the last line, an accepted trade for never risking the gate's real output
  # or exit code. IDs only, never mail content — see the header.
  mkdir -p "$DATA/telemetry" 2>/dev/null || true
  exec > >(tee >(sed -u "s/^{/{\"_ts\":\"$(date -u +%FT%TZ)\",/" >> "$DATA/telemetry/inbox-check.jsonl" 2>/dev/null) 2>/dev/null)
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi

  # Opt-in, because most projects have no shared inbox and this task must stay
  # silent forever rather than reporting a permanent 401 at them. The credential
  # lives in the OneCLI vault; a bash gate cannot see the vault, so enabling is
  # an explicit config key rather than something detectable.
  if [ "${INBOX_ENABLED:-}" != "true" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set INBOX_ENABLED=\"true\" in plugin-data/community-manager/config.env once the Gmail read-only credential is wired"}}'
    exit 0
  fi

  # Default query is deliberately bounded on BOTH axes: unread only (mail the
  # owner has already read is theirs, not a triage backlog) and recent only, so
  # a long-abandoned inbox doesn't hand over hundreds of ids on first run.
  QUERY="${INBOX_QUERY:-is:unread newer_than:7d}"
  MAX_RESULTS="${INBOX_MAX_RESULTS:-25}"
  case "$MAX_RESULTS" in ''|*[!0-9]*) MAX_RESULTS=25;; esac

  # Bounded retry, same shape and for the same reason as github-first-response:
  # ids are acked BEFORE the agent triages them, so an invocation that dies in
  # between (a spend-limit outage killed a real one) would otherwise drop the
  # mail forever. The token is read-only — this agent CANNOT mark anything read
  # — so without a cap a single deliberately-unread message would re-wake the
  # manager twice a day indefinitely. Hence retries, not permanent re-surfacing.
  RETRY_HOURS="${INBOX_RETRY_HOURS:-24}"
  case "$RETRY_HOURS" in ''|*[!0-9]*) RETRY_HOURS=24;; esac
  MAX_RETRIES="${INBOX_MAX_RETRIES:-2}"
  case "$MAX_RETRIES" in ''|*[!0-9]*) MAX_RETRIES=2;; esac
  RETRY_SEC=$((RETRY_HOURS * 3600))
  NOW_EPOCH=$(date +%s)

  RAW=$(curl -sS --max-time 10 -w '\n%{http_code}' -H "Accept: application/json" \
    --get "https://gmail.googleapis.com/gmail/v1/users/me/messages" \
    --data-urlencode "q=$QUERY" \
    --data-urlencode "maxResults=$MAX_RESULTS" 2>/dev/null) || RAW=""
  HTTP_CODE=$(printf '%s' "$RAW" | tail -n1)
  RESP=$(printf '%s' "$RAW" | sed '$d')

  # A broken fetch must never read as an empty inbox — that is the one failure
  # mode that would silently swallow a security disclosure. Surface the real
  # status code so 401 (credential not wired / scope wrong) is distinguishable
  # from 5xx (Google-side) and from a network timeout.
  if [ -z "$RAW" ]; then
    echo '{"wakeAgent": true, "data": {"status": "fetch-failed", "reason": "curl request failed (network/timeout)"}}'
    exit 0
  fi
  if [ "${HTTP_CODE#2}" = "$HTTP_CODE" ]; then
    printf '{"wakeAgent": true, "data": {"status": "fetch-failed", "reason": "HTTP %s", "hint": "401/403 usually means the gmail.googleapis.com credential is not wired, or lacks gmail.readonly"}}\n' "$HTTP_CODE"
    exit 0
  fi

  # Gmail omits `messages` entirely on a zero-match query rather than returning
  # an empty array, so `// []` is load-bearing, not defensive noise.
  IDS=$(printf '%s' "$RESP" | jq -c '[(.messages // [])[] | {id, threadId}]' 2>/dev/null || echo "")
  if [ -z "$IDS" ]; then
    echo '{"wakeAgent": true, "data": {"status": "fetch-failed", "reason": "unparseable response shape"}}'
    exit 0
  fi
  TOTAL=$(printf '%s' "$IDS" | jq 'length')

  if [ "$TOTAL" -eq 0 ]; then
    echo '{"wakeAgent": false, "data": {"status": "empty", "unread": 0}}'
    exit 0
  fi

  SEEN="$DATA/inbox-seen.jsonl"
  touch "$SEEN"
  SEEN_JSON=$(jq -R -s -c '
    split("\n") | map(select(length > 0)) | map(try fromjson catch empty)
    ' < "$SEEN" 2>/dev/null || echo '[]')

  NEW=$(jq -c -n --argjson ids "$IDS" --argjson seen "$SEEN_JSON" \
    --argjson now "$NOW_EPOCH" --argjson retry_sec "$RETRY_SEC" --argjson max_retries "$MAX_RETRIES" '
    ($seen | map({(.id): .}) | add // {}) as $bykey
    | [ $ids[]
        | . as $m
        | ($bykey[$m.id]) as $s
        | if $s == null then
            $m + {retry: false, retries: 0}
          elif (($now - $s.seen_at) >= $retry_sec) and ($s.retries < $max_retries) then
            $m + {retry: true, retries: ($s.retries + 1)}
          else
            empty
          end
      ]' 2>/dev/null || echo '[]')
  COUNT=$(printf '%s' "$NEW" | jq 'length')

  if [ "$COUNT" -eq 0 ]; then
    printf '{"wakeAgent": false, "data": {"status": "all-handed-over", "unread": %s, "hint": "every unread message has already been handed over, and none is due a retry"}}\n' "$TOTAL"
    exit 0
  fi

  # Ack before handing over, bounded by the retry policy above.
  printf '%s' "$NEW" | jq -c --argjson now "$NOW_EPOCH" '.[] | {id, seen_at: $now, retries}' \
    >> "$SEEN" 2>/dev/null || true
  tail -n 500 "$SEEN" > "$SEEN.t" 2>/dev/null && mv "$SEEN.t" "$SEEN"

  printf '{"wakeAgent": true, "data": {"status": "needs-triage", "count": %s, "unread": %s, "query": "%s", "retry_hours": %s, "messages": %s}}\n' \
    "$COUNT" "$TOTAL" "$QUERY" "$RETRY_HOURS" "$NEW"
---
Check the project's shared inbox and triage what's there. This is your work,
not a sub-agent's: an inbox is a support channel with a different transport,
and the same escalation rules apply to it as to Discord.

**Security or vulnerability disclosure — check for this FIRST, before
anything else.** A shared project inbox is a normal place for someone to
send a vulnerability report, especially if it's the address in
`SECURITY.md` or your docs. If anything looks like a security disclosure:
route it per `references/escalation-paths.md` (private, owner + the named
backstop, never a public channel and never a public issue), and do not
summarize its detail into any digest that lands somewhere public. Treat an
ambiguous case as security until you're sure it isn't.

**Abuse, harassment, or anything with a legal edge** — same as any other
channel: don't adjudicate, route it per `escalation-paths.md`, don't quote
the content onward.

Then the ordinary triage:

**Needs a human** — anything with a decision, a commitment, or a relationship
implication. Summarize and hand up; don't draft a reply that reads like a
decision has been made.
**You can draft a reply** — routine questions with a known answer, per
`references/inbox-triage.md`. Draft it, hand it to the owner, don't send.
Log the topic to `question-ledger.jsonl` exactly as you would for a
Discord support conversation — email questions repeat too, and
`docs-gap-review` is blind to anything you don't log.
**Spam or automated noise** — count it, don't summarize each one.

Never send, reply, forward, or delete anything. This task reads and drafts
only — the send is always a human's. If the inbox is quiet, one line saying
so is the whole report.
