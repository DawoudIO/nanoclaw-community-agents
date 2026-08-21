#!/bin/bash
set -euo pipefail
# Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
# Quarterly newcomer-path audit via GitHub's community-profile endpoint —
# ONE call per repo answers all of it: CONTRIBUTING, CODE_OF_CONDUCT, issue
# and PR templates, README, license, plus GitHub's own health percentage.
# Research context: failed OSS projects had contributing guidelines 16% of
# the time vs 72% for healthy ones — a well-tended good-first-issue list on
# a repo with no CONTRIBUTING.md optimizes step two of a path with no step
# one. Wakes only when something is missing or a fetch failed.
DATA="/workspace/agent/plugin-data/community-coding"
mkdir -p "$DATA"
if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
REPOS="${COMMUNITY_REPOS:-}"
if [ -z "$REPOS" ]; then
  echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-coding/config.env"}}'
  exit 0
fi
TMP=$(mktemp -d)
i=0
for REPO in $REPOS; do
  (
    RESP=$(curl -fsS --max-time 10 -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$REPO/community/profile" 2>/dev/null) || RESP=""
    if [ -z "$RESP" ] || ! printf '%s' "$RESP" | jq -e '.health_percentage' >/dev/null 2>&1; then
      printf '{"repo": "%s", "status": "fetch-failed"}\n' "$REPO" > "$TMP/$i.json"
      exit 0
    fi
    printf '%s' "$RESP" | jq -c --arg r "$REPO" '{
      repo: $r,
      status: "ok",
      health_percentage: .health_percentage,
      missing: ([.files | to_entries[] | select(.value == null) | .key])
    }' > "$TMP/$i.json" 2>/dev/null \
      || printf '{"repo": "%s", "status": "fetch-failed"}\n' "$REPO" > "$TMP/$i.json"
  ) &
  i=$((i+1))
done
wait
ALL=$(cat "$TMP"/*.json | jq -c -s '.')
rm -rf "$TMP"
FAILED=$(printf '%s' "$ALL" | jq -c '[.[] | select(.status=="fetch-failed") | .repo]')
GAPS=$(printf '%s' "$ALL" | jq '[.[] | select(.status=="ok" and (.missing | length) > 0)] | length')
if [ "$(printf '%s' "$FAILED" | jq 'length')" -gt 0 ] || [ "$GAPS" -gt 0 ]; then
  printf '{"wakeAgent": true, "data": {"status": "attention", "failed_repos": %s, "results": %s}}\n' "$FAILED" "$ALL"
else
  echo '{"wakeAgent": false, "data": {"status": "all-complete"}}'
fi
