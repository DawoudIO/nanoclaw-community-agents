---
schedule: "16 16 * * 1"
script: |
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

  # --- local telemetry (best-effort; never blocks the gate) -------------------
  # Mirrors this gate's one-line JSON output to a local per-task log so the
  # owner can review wake/error patterns weekly and adjust gates or budgets.
  # Not published anywhere (unlike ledger-publish's series) and not a source
  # of truth -- a background pipe means a very fast exit can occasionally drop
  # the last line, an accepted trade for never risking the gate's real output
  # or exit code.
  mkdir -p "$DATA/telemetry" 2>/dev/null || true
  exec > >(tee >(sed -u "s/^{/{\"_ts\":\"$(date -u +%FT%TZ)\",/" >> "$DATA/telemetry/good-first-issue-health.jsonl" 2>/dev/null) 2>/dev/null)
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
---
Weekly good-first-issue funnel check. `scriptOutput.label` is the exact label
text searched (`GFI_LABEL` in config.env, default `"good first issue"` —
GitHub's own suggested label; if your project uses different wording, e.g.
`"help wanted"` or a custom scheme, set `GFI_LABEL` instead of assuming the
default matches).

**If `status` is `fetch-failed`**: report the symptom for `failed_repos` to
your manager — `401/403` is token wiring, `502` is sandbox network policy — and
stop for those repos.

**If `open_count` is 0 for every run over several weeks**: say so plainly and
ask your manager whether the project actually uses this label under a different
name — a real zero (no beginner-friendly issues exist) and a label-name
mismatch look identical from this data, and only a human knows which one is
true. Don't guess; don't silently keep reporting 0 forever without raising it
once.

**`unassigned_stale`** is the signal that matters: open, GFI-labeled issues
with no assignee and no activity in 14+ days — the starved end of the
onboarding funnel research shows is quietly breaking industry-wide. List each
one (number/title/link); these are candidates for a maintainer to either
re-promote (comment, bump visibility) or unlabel if it turns out not to be
beginner-friendly after all. An empty list is good news — the funnel is
healthy; say so in one line. If a repo's `truncated` is `true`, more than 100
GFI issues exist and only the 100 least-recently-updated (i.e., the stalest)
were scanned — say the stale list is a floor, not the complete count. If a
repo you expected is missing from `results` entirely, treat that as a fetch
problem and say so — never assume an absent repo means a healthy repo.

Hand this to your manager as its own short update — don't fold it into the daily
dev-metrics report, and don't duplicate `dev-metrics-report`'s open-issue
count here.
