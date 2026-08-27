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
# Discord needs no equivalent — the lead answers Discord live through its
# channel wiring, event-driven, and unanswered-watch is the safety net for when
# it can't. GitHub has no live wiring in this design, so this poll is the path.
DATA="/workspace/agent/plugin-data/community-manager"
mkdir -p "$DATA"
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
    curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
      "https://api.github.com/search/issues?q=repo:$REPO+is:open+comments:0+created:%3E%3D$SINCE&sort=created&order=asc&per_page=20" \
      > "$TMP/$i.raw" 2>/dev/null
    OUT=$(jq -c --arg r "$REPO" --argjson now "$NOW_EPOCH" 'if .items then
        {repo: $r, ok: true,
         items: [.items[] | {
           number, title: (.title[0:140]), author: .user.login, url: .html_url,
           type: (if .pull_request then "pr" else "issue" end),
           created_at,
           age_min: ((($now - ((.created_at | fromdateiso8601?) // $now)) / 60) | floor)}]}
      else {repo: $r, ok: false, items: []} end' < "$TMP/$i.raw" 2>/dev/null || echo "")
    [ -z "$OUT" ] && OUT=$(jq -c -n --arg r "$REPO" '{repo: $r, ok: false, items: []}')
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
DEGRADED=$(printf '%s' "$ALL" | jq -c '[.[] | select(.ok == false) | .repo]')
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
