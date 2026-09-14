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

SEEN="$DATA/first-response-seen.txt"
touch "$SEEN"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
i=0
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
  i=$((i+1))
done
wait

if ! ls "$TMP"/*.json >/dev/null 2>&1; then
  echo '{"wakeAgent": true, "data": {"status": "fetch-failed", "hint": "no repo produced a result — check the token and the sandbox network policy"}}'
  exit 0
fi
ALL=$(cat "$TMP"/*.json | jq -c -s '.' 2>/dev/null || echo '[]')
DEGRADED=$(printf '%s' "$ALL" | jq -c '[.[] | select(.ok == false) | {repo, reason}]')
HAS_DEGRADED=$(printf '%s' "$DEGRADED" | jq 'length > 0')

# Past the grace period, and not already handed to the agent once.
SEEN_JSON=$(jq -R -s -c 'split("\n") | map(select(length > 0))' < "$SEEN" 2>/dev/null || echo '[]')
NEW=$(jq -c -n --argjson a "$ALL" --argjson seen "$SEEN_JSON" --argjson g "$GRACE_MIN" '
  [ $a[] | .repo as $r | .items[]
    | select(.age_min >= $g)
    | select((($r + "#" + (.number|tostring)) | IN($seen[])) | not)
    | . + {repo: $r} ]' 2>/dev/null || echo '[]')
COUNT=$(printf '%s' "$NEW" | jq 'length')

WAKE=false
if [ "$COUNT" -gt 0 ] || [ "$HAS_DEGRADED" = "true" ]; then WAKE=true; fi

# Ack BEFORE handing over, deliberately: this task runs every 10 minutes, so a
# lost wake costs one missed first response, while a failure to ack would mean
# re-waking the agent for the same issue 144 times a day. That is the opposite
# trade-off from the slower gates, and it is the right one at this cadence.
if [ "$COUNT" -gt 0 ]; then
  printf '%s' "$NEW" | jq -r '.[] | "\(.repo)#\(.number)"' >> "$SEEN" 2>/dev/null || true
  # keep the ledger bounded — three days of items is plenty of memory
  tail -n 500 "$SEEN" > "$SEEN.t" 2>/dev/null && mv "$SEEN.t" "$SEEN"
fi

printf '{"wakeAgent": %s, "data": {"status": "%s", "count": %s, "grace_minutes": %s, "items": %s, "degraded_repos": %s}}\n' \
  "$WAKE" \
  "$([ "$HAS_DEGRADED" = "true" ] && echo partial-fetch-failure || { [ "$COUNT" -gt 0 ] && echo needs-first-response || echo all-answered; })" \
  "$COUNT" "$GRACE_MIN" "$NEW" "$DEGRADED"
