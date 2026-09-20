#!/bin/bash
set -uo pipefail
# Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
#
# FIRST RESPONSE ON GITHUB. Narrow on purpose: brand-new issues and PRs that
# nobody has replied to yet. Not triage, not a digest, not a backlog sweep —
# just "someone showed up and nobody has said anything."
#
# WHY THIS IS SEPARATE FROM github-ops-triage.
# Triage runs every 6 hours and produces a digest; that cadence is right for
# deciding duplicates and staleness, and wrong for first response. Time-to-
# first-response is the strongest predictor of whether a contributor comes
# back, so a 6-hour floor on it is the single biggest gap in the north star.
# But making the triage DIGEST 10-minutely would mean up to 144 digests a day,
# which is the notification stream we deliberately removed. So: fast and
# narrow here, slow and thorough there.
#
# Discord needs no equivalent — the manager answers Discord live through its
# channel wiring, event-driven, and unanswered-watch is the safety net for when
# it can't. GitHub has no live wiring in this design, so this poll is the path.
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
exec > >(tee >(sed -u "s/^{/{\"_ts\":\"$(date -u +%FT%TZ)\",/" >> "$DATA/telemetry/github-first-response.jsonl" 2>/dev/null) 2>/dev/null)
if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
REPOS="${COMMUNITY_REPOS:-}"
if [ -z "$REPOS" ]; then
  echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-manager/config.env"}}'
  exit 0
fi
# Grace period before we consider something unanswered. Exists so we do not
# beat a human maintainer who is already typing — replying 40 seconds after
# someone opens an issue reads as a bot, not as attention.
GRACE_MIN="${FIRST_RESPONSE_GRACE_MINUTES:-15}"
case "$GRACE_MIN" in ''|*[!0-9]*) GRACE_MIN=15;; esac

# Bounded retry: how long to wait, and how many times to retry, before
# re-surfacing an item that was already handed to the agent once. Exists
# because "seen" is marked BEFORE the agent replies (see below) — if the
# agent invocation dies between those two steps (a real incident: #9836 was
# marked seen right as an org-wide spend-limit outage killed the reply, and
# sat unanswered for 2 days since nothing ever re-checked it), the item was
# gone for good. The retry window is bounded specifically so this can't
# regress into the 144x/day re-wake cost "seen" exists to avoid: a genuinely
# answered item drops out of GitHub's own comments:0 search and never
# retries regardless of this window, so only a truly-still-unanswered item
# can ever resurface.
RETRY_MIN="${FIRST_RESPONSE_RETRY_MINUTES:-45}"
case "$RETRY_MIN" in ''|*[!0-9]*) RETRY_MIN=45;; esac
MAX_RETRIES="${FIRST_RESPONSE_MAX_RETRIES:-3}"
case "$MAX_RETRIES" in ''|*[!0-9]*) MAX_RETRIES=3;; esac
RETRY_SEC=$((RETRY_MIN * 60))

NOW_EPOCH=$(date +%s)
# Only look at the last 3 days. Anything older that is still unanswered is a
# backlog problem, and backlog belongs to triage — this task must not
# re-litigate old items every 10 minutes.
SINCE=$(date -u -d "@$((NOW_EPOCH - 259200))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
     || date -u -r "$((NOW_EPOCH - 259200))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
if [ -z "$SINCE" ]; then
  echo '{"wakeAgent": true, "data": {"status": "date-unavailable", "hint": "neither GNU nor BSD date worked in this image"}}'
  exit 0
fi

SEEN="$DATA/first-response-seen.csv"
touch "$SEEN"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
i=0
PIDS=()   # deadlock fix: exec > >(tee ...) puts a background subshell in this shell's
# own job table, so a BARE 'wait' below would also wait on it -- and it
# cannot exit until this script's stdout closes, which cannot happen until
# the script exits, which is blocked on that same wait. Track only the
# per-repo PIDs and wait on those explicitly.
for REPO in $REPOS; do
  (
    # comments:0 is the whole trick — GitHub's search does the "nobody has
    # replied" filter for us, so this stays one cheap call per repo.
    #
    # `-f` alone turns every HTTP error into the same silent empty body —
    # a genuine break, a transient 5xx, a 429 rate limit, and a 401 auth
    # problem all look identical: a bare "degraded" with no reason. That
    # produced a run of false-alarm-feeling escalations that were actually
    # transient blips with no way to tell which. Capture the real status
    # code and curl's own exit code instead, and carry both into the
    # degraded-repo report so a genuine break is distinguishable from noise.
    RAW=$(curl -sS --max-time 8 -w '\n%{http_code}' -H "Accept: application/vnd.github+json" \
      "https://api.github.com/search/issues?q=repo:$REPO+is:open+comments:0+created:%3E%3D$SINCE&sort=created&order=asc&per_page=20" \
      2>/dev/null) || RAW=""
    HTTP_CODE=$(printf '%s' "$RAW" | tail -n1)
    RESP=$(printf '%s' "$RAW" | sed '$d')
    if [ -z "$RAW" ]; then
      OUT=$(jq -c -n --arg r "$REPO" '{repo: $r, ok: false, items: [], reason: "curl request failed (network/timeout)"}')
    elif [ "${HTTP_CODE#2}" = "$HTTP_CODE" ]; then
      # Not a 2xx — surface the status code plainly (403 = rate limit or
      # scope, 404 = repo/token mismatch, 5xx = GitHub-side). Distinguishing
      # this from a generic "degraded" is the whole fix: they used to look
      # identical, which produced a run of alarming-looking escalations that
      # were actually transient blips with no way to tell which from a bug.
      OUT=$(jq -c -n --arg r "$REPO" --arg reason "HTTP $HTTP_CODE" '{repo: $r, ok: false, items: [], reason: $reason}')
    else
      OUT=$(jq -c --arg r "$REPO" --argjson now "$NOW_EPOCH" 'if .items then
          {repo: $r, ok: true,
           items: [.items[] | {
             number, title: (.title[0:140]), author: .user.login, url: .html_url,
             type: (if .pull_request then "pr" else "issue" end),
             created_at,
             age_min: ((($now - ((.created_at | fromdateiso8601?) // $now)) / 60) | floor)}]}
        else {repo: $r, ok: false, items: [], reason: "unexpected response shape"} end' <<< "$RESP" 2>/dev/null || echo "")
      [ -z "$OUT" ] && OUT=$(jq -c -n --arg r "$REPO" '{repo: $r, ok: false, items: [], reason: "unparseable response"}')
    fi
    printf '%s\n' "$OUT" > "$TMP/$i.json"
  ) &
  PIDS+=("$!")
  i=$((i+1))
done
wait "${PIDS[@]}"

if ! ls "$TMP"/*.json >/dev/null 2>&1; then
  echo '{"wakeAgent": true, "data": {"status": "fetch-failed", "hint": "no repo produced a result — check the token and the sandbox network policy"}}'
  exit 0
fi
ALL=$(cat "$TMP"/*.json | jq -c -s '.' 2>/dev/null || echo '[]')
DEGRADED=$(printf '%s' "$ALL" | jq -c '[.[] | select(.ok == false) | {repo, reason}]')
HAS_DEGRADED=$(printf '%s' "$DEGRADED" | jq 'length > 0')

# Past the grace period, and either never seen or eligible for a bounded
# retry. $SEEN is CSV — `key,seen_at,retries`, one row per ack — read with
# awk rather than a JSON parser. Keys are `owner/repo#123`, which cannot
# contain a comma, so no quoting is needed and position is the whole contract.
#
# Last row wins for a repeated key: acks append, so the newest entry for a key
# is the furthest down the file. awk overwrites as it goes, which gives that
# for free in one pass.
SEEN_JSON=$(awk -F, 'NF>=3 && $1!="key" { seen[$1]=$2 "," $3 }
  END { printf "["; first=1
        for (k in seen) { split(seen[k], v, ",")
          if (!first) printf ","; first=0
          printf "{\"key\":\"%s\",\"seen_at\":%s,\"retries\":%s}", k, v[1], v[2] }
        printf "]" }' "$SEEN" 2>/dev/null || echo '[]')
[ -z "$SEEN_JSON" ] && SEEN_JSON='[]'
# jq still does the JOIN against the GitHub payload below, because $ALL is an
# API response — but the state it joins against is now a flat table.
NEW=$(jq -c -n --argjson a "$ALL" --argjson seen "$SEEN_JSON" --argjson g "$GRACE_MIN" \
  --argjson now "$NOW_EPOCH" --argjson retry_sec "$RETRY_SEC" --argjson max_retries "$MAX_RETRIES" '
  ($seen | map({(.key): .}) | add // {}) as $bykey
  | [ $a[] | .repo as $r | .items[]
      | select(.age_min >= $g)
      | ($r + "#" + (.number|tostring)) as $k
      | ($bykey[$k]) as $s
      | if $s == null then
          . + {repo: $r, retry: false, retries: 0, _key: $k}
        elif (($now - $s.seen_at) >= $retry_sec) and ($s.retries < $max_retries) then
          . + {repo: $r, retry: true, retries: ($s.retries + 1), _key: $k}
        else
          empty
        end
    ]' 2>/dev/null || echo '[]')
COUNT=$(printf '%s' "$NEW" | jq 'length')

WAKE=false
if [ "$COUNT" -gt 0 ] || [ "$HAS_DEGRADED" = "true" ]; then WAKE=true; fi

# Ack BEFORE handing over, deliberately: this task runs every 10 minutes, so a
# lost wake costs one missed first response, while a failure to ack would mean
# re-waking the agent for the same issue 144 times a day. That is the opposite
# trade-off from the slower gates, and it is the right one at this cadence.
#
# BUT an ack this early has no way to tell "the agent replied" from "the
# agent's invocation died before replying" — and the latter used to mean the
# item was gone forever (see #9836 above). So $SEEN now also records WHEN an
# item was acked and how many times, and an item past RETRY_SEC with retries
# left resurfaces exactly once per window — bounded, not infinite, and only
# for items GitHub's own comments:0 filter still calls unanswered.
if [ "$COUNT" -gt 0 ]; then
  [ -s "$SEEN" ] || echo 'key,seen_at,retries' > "$SEEN"
  printf '%s' "$NEW" | jq -r --argjson now "$NOW_EPOCH" '.[] | [._key, $now, .retries] | @csv' \
    | tr -d '"' >> "$SEEN" 2>/dev/null || true
  # keep the ledger bounded — three days of items, a few retries each, is
  # still plenty of memory at 500 rows. Keep the header on top while trimming.
  { head -n 1 "$SEEN"; tail -n 500 "$SEEN" | grep -v '^key,'; } > "$SEEN.t" 2>/dev/null \
    && mv "$SEEN.t" "$SEEN"
fi

PUBLIC_NEW=$(printf '%s' "$NEW" | jq -c 'map(del(._key))')
printf '{"wakeAgent": %s, "data": {"status": "%s", "count": %s, "grace_minutes": %s, "retry_minutes": %s, "max_retries": %s, "items": %s, "degraded_repos": %s}}\n' \
  "$WAKE" \
  "$([ "$HAS_DEGRADED" = "true" ] && echo partial-fetch-failure || { [ "$COUNT" -gt 0 ] && echo needs-first-response || echo all-answered; })" \
  "$COUNT" "$GRACE_MIN" "$RETRY_MIN" "$MAX_RETRIES" "$PUBLIC_NEW" "$DEGRADED"
