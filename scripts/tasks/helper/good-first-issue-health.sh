#!/bin/bash
set -euo pipefail
# Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
# A 2026 longitudinal study found newcomer-PR merge rates on good-first-issue
# (GFI) labeled issues falling industry-wide even as newcomer interest held
# steady — the bottleneck is supply and review, not demand. This tracks the
# supply side: how many GFI issues are open, and how many are sitting
# unassigned and stale (the starved-onboarding-pipeline signal).
DATA="/workspace/agent/plugin-data/community-helper"
mkdir -p "$DATA"
if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
REPOS="${COMMUNITY_REPOS:-}"
if [ -z "$REPOS" ]; then
  echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-helper/config.env"}}'
  exit 0
fi
LABEL="${GFI_LABEL:-good first issue}"
STALE_CUTOFF=$(( $(date +%s) - 1209600 ))
TMP=$(mktemp -d)
i=0
for REPO in $REPOS; do
  (
    # sort=updated&order=asc: the least-recently-touched issues come first,
    # so when a repo has more than the 100-item page, the page holds exactly
    # the stalest ones — the set this task exists to find. `truncated` tells
    # the agent the stale list may be a floor, not the complete set.
    RESP=$(curl -fsS --max-time 10 -H "Accept: application/vnd.github+json" \
      --get "https://api.github.com/search/issues" \
      --data-urlencode "q=repo:$REPO is:issue is:open label:\"$LABEL\"" \
      --data-urlencode "sort=updated" --data-urlencode "order=asc" \
      --data-urlencode "per_page=100" 2>/dev/null) || RESP=""
    if [ -z "$RESP" ] || ! printf '%s' "$RESP" | jq -e '.total_count' >/dev/null 2>&1; then
      printf '{"repo": "%s", "status": "fetch-failed"}\n' "$REPO" > "$TMP/$i.json"
      exit 0
    fi
    # A jq failure on an unexpected item shape must surface as fetch-failed
    # for that repo — never as a silently missing repo in an "ok" report.
    printf '%s' "$RESP" | jq -c --arg r "$REPO" --argjson cutoff "$STALE_CUTOFF" '{
      repo: $r,
      status: "ok",
      open_count: .total_count,
      truncated: (.total_count > (.items | length)),
      unassigned_stale: [.items[]? | select(.assignee == null and ((.updated_at // empty) | fromdateiso8601? // now) < $cutoff)
        | {number, title: (.title[0:120]), url: .html_url, updated_at}]
    }' > "$TMP/$i.json" 2>/dev/null \
      || printf '{"repo": "%s", "status": "fetch-failed"}\n' "$REPO" > "$TMP/$i.json"
  ) &
  i=$((i+1))
done
wait
ALL=$(cat "$TMP"/*.json | jq -c -s '.')
rm -rf "$TMP"
FAILED=$(printf '%s' "$ALL" | jq -c '[.[] | select(.status=="fetch-failed") | .repo]')
if [ "$(printf '%s' "$FAILED" | jq 'length')" -gt 0 ]; then
  printf '{"wakeAgent": true, "data": {"status": "fetch-failed", "failed_repos": %s, "label": "%s", "results": %s}}\n' "$FAILED" "$LABEL" "$ALL"
else
  printf '{"wakeAgent": true, "data": {"status": "ok", "label": "%s", "results": %s}}\n' "$LABEL" "$ALL"
fi
