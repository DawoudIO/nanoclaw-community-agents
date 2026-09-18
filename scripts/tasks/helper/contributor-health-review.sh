#!/bin/bash
set -uo pipefail
# Deps: bash, curl, jq, awk. GitHub auth injected by the OneCLI proxy.
#
# Maintainer-load and PR-throughput signals: how dependent is each repo on a
# single author, is the close-without-merge rate drifting, and who has enough
# sustained merged work to be worth a bigger role.
#
# WHY THIS IS ITS OWN TASK, NOT PART OF dev-metrics-report.
# The numbers below are arithmetic and the script computes them — but every one
# of them needs a judgment call that a daily list of counts is the wrong place
# for:
#   * a rising unmerged ratio means EITHER more low-quality submissions OR a
#     maintainer backlog. Opposite problems, opposite responses, same number.
#   * high top-author share means "one person deep" only in context — a
#     solo-maintainer project at 95% is normal; a ten-person project at 95%
#     is a bus-factor emergency.
#   * naming someone a delegation candidate is a judgment about a PERSON, and
#     deserves a deliberate read rather than a line in a digest.
# So the fetching stays scripted and the interpreting gets its own slot.
# Weekly, because these are slow-moving signals — a daily read of a 90-day
# window is just noise with extra API calls.
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
exec > >(tee >(sed -u "s/^{/{\"_ts\":\"$(date -u +%FT%TZ)\",/" >> "$DATA/telemetry/contributor-health-review.jsonl" 2>/dev/null) 2>/dev/null)
if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
REPOS="${COMMUNITY_REPOS:-}"
if [ -z "$REPOS" ]; then
  echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-helper/config.env"}}'
  exit 0
fi

NOW_EPOCH=$(date +%s)
CUTOFF30=$(( NOW_EPOCH - 2592000 ))
SINCE30=$(date -u -d "@$CUTOFF30" +%Y-%m-%d 2>/dev/null || date -u -r "$CUTOFF30" +%Y-%m-%d 2>/dev/null || echo "")
CUTOFF90=$(( NOW_EPOCH - 7776000 ))
SINCE90=$(date -u -d "@$CUTOFF90" +%Y-%m-%d 2>/dev/null || date -u -r "$CUTOFF90" +%Y-%m-%d 2>/dev/null || echo "")
if [ -z "$SINCE30" ] || [ -z "$SINCE90" ]; then
  echo '{"wakeAgent": true, "data": {"status": "date-unavailable", "hint": "neither GNU nor BSD date worked in this image - cannot build the search windows"}}'
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
i=0
for REPO in $REPOS; do
  (
    curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
      "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:merged+merged:%3E%3D$SINCE30&per_page=1" \
      > "$TMP/$i.merged30" 2>/dev/null &
    curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
      "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:closed+is:unmerged+closed:%3E%3D$SINCE30&per_page=1" \
      > "$TMP/$i.unmerged30" 2>/dev/null &
    curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
      "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:merged+merged:%3E%3D$SINCE90&per_page=100" \
      > "$TMP/$i.m90" 2>/dev/null &
    wait

    MERGED30=$(jq '.total_count // "e"' < "$TMP/$i.merged30" 2>/dev/null || echo e)
    case "$MERGED30" in ''|*e*) MERGED30=null;; esac
    UNMERGED30=$(jq '.total_count // "e"' < "$TMP/$i.unmerged30" 2>/dev/null || echo e)
    case "$UNMERGED30" in ''|*e*) UNMERGED30=null;; esac
    # The ratio is arithmetic, not judgment — computed here so the agent
    # never does mental math. null below a 5-sample floor: a percentage
    # derived from one or two PRs is worse than no percentage at all.
    RATIO=null
    if [ "$MERGED30" != "null" ] && [ "$UNMERGED30" != "null" ]; then
      TOTAL30=$(( MERGED30 + UNMERGED30 ))
      if [ "$TOTAL30" -ge 5 ]; then
        RATIO=$(awk -v u="$UNMERGED30" -v t="$TOTAL30" 'BEGIN { printf "%.2f", u/t }')
      fi
    fi
    # sampled=true when >100 PRs merged in 90d — the histogram then covers
    # the most recent 100, which still answers the concentration question.
    CONC=$(jq -c 'if .items then
      ([.items[].user.login] | group_by(.) | map({login: .[0], merged_90d: length}) | sort_by(-.merged_90d)) as $a
      | {distinct_authors_90d: ($a | length),
         total_merged_90d: .total_count,
         sampled: (.total_count > (.items | length)),
         top_author: ($a[0].login // null),
         top_author_share_pct: (if ([$a[].merged_90d] | add // 0) > 0 then (($a[0].merged_90d / ([$a[].merged_90d] | add)) * 100 | round) else null end),
         candidates: [$a[] | select(.merged_90d >= 5)]}
      else null end' < "$TMP/$i.m90" 2>/dev/null || echo null)
    case "$CONC" in ''|null) CONC=null;; esac

    printf '{"repo": "%s", "closed_prs_30d": {"merged": %s, "unmerged": %s, "unmerged_ratio": %s}, "concentration": %s}\n' \
      "$REPO" "$MERGED30" "$UNMERGED30" "$RATIO" "$CONC" > "$TMP/$i.json"
  ) &
  i=$((i+1))
done
wait

if ! ls "$TMP"/*.json >/dev/null 2>&1; then
  echo '{"wakeAgent": true, "data": {"status": "fetch-failed", "hint": "no repo produced a result — check the token and the sandbox network policy"}}'
  exit 0
fi
ALL=$(cat "$TMP"/*.json | jq -c -s '.' 2>/dev/null || echo '[]')
DEGRADED=$(printf '%s' "$ALL" | jq -c '[.[] | select(.concentration == null or .closed_prs_30d.merged == null) | .repo]')
HAS_DEGRADED=$(printf '%s' "$DEGRADED" | jq 'length > 0')

# Trend memory: this task exists to catch DRIFT, so it needs last week's
# values to compare against. Append-only history, capped at ~1 year of
# weekly points.
# CSV: date,repo,unmerged_ratio,top_author_share_pct — one row per repo per
# run. Only those two numbers are ever compared against, so the history holds
# exactly them rather than a nested copy of the whole assessment.
HIST="$DATA/contributor-health-history.csv"
[ -s "$HIST" ] || echo 'date,repo,unmerged_ratio,top_author_share_pct' > "$HIST"

# Last run's rows = every row carrying the most recent date, which on an
# append-ordered file is the date on the final line. awk builds the small JSON
# array the comparison joins against. An empty field becomes a real null,
# never 0 — "not measured" and "measured as zero" must never merge, or a
# degraded fetch reads as a 100-point swing.
LAST_DATE=$(tail -n 1 "$HIST" | cut -d, -f1)
PREV='[]'
case "$LAST_DATE" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
    PREV=$(awk -F, -v d="$LAST_DATE" '
      NR == 1 && $1 == "date" { next }
      $1 == d && NF >= 4 {
        r = ($3 == "" ? "null" : $3); s = ($4 == "" ? "null" : $4)
        out = out (out == "" ? "" : ",") sprintf("{\"repo\":\"%s\",\"ratio\":%s,\"share\":%s}", $2, r, s)
      }
      END { printf "[%s]", out }' "$HIST" 2>/dev/null || echo '[]')
    ;;
esac
[ -z "$PREV" ] && PREV='[]'

printf '%s' "$ALL" | jq -r --arg d "$(date -u +%Y-%m-%d)" \
  '.[] | [$d, .repo, (.closed_prs_30d.unmerged_ratio // ""), (.concentration.top_author_share_pct // "")] | @csv' \
  | tr -d '"' >> "$HIST" 2>/dev/null || true
# ~52 weekly points across a handful of repos; header kept on top.
{ head -n 1 "$HIST"; tail -n 520 "$HIST" | grep -v '^date,'; } > "$HIST.tmp" 2>/dev/null \
  && mv "$HIST.tmp" "$HIST" || rm -f "$HIST.tmp"

# Wake only on a real move. Thresholds are deliberate and stated here rather
# than left to the model: a 10-point ratio swing or a 10-point concentration
# swing is a signal; 1-2 points is sampling noise on repos this size.
MOVED=$(jq -c -n --argjson t "$ALL" --argjson p "$PREV" '
  [ $t[] as $cur
    | ($p[] | select(.repo == $cur.repo)) as $old
    | select(
        (($cur.closed_prs_30d.unmerged_ratio != null) and ($old.ratio != null)
          and (((($cur.closed_prs_30d.unmerged_ratio | tonumber) - ($old.ratio | tonumber)) | fabs) >= 0.10))
        or (($cur.concentration.top_author_share_pct != null) and ($old.share != null)
          and ((($cur.concentration.top_author_share_pct - $old.share) | fabs) >= 10))
      )
    | {repo: $cur.repo,
       ratio_now: $cur.closed_prs_30d.unmerged_ratio, ratio_before: $old.ratio,
       share_now: $cur.concentration.top_author_share_pct, share_before: $old.share} ]' \
  2>/dev/null || echo '[]')
HAS_MOVED=$(printf '%s' "$MOVED" | jq 'length > 0' 2>/dev/null || echo false)
FIRST_RUN=$(printf '%s' "$PREV" | jq 'length == 0')

# Quarterly heartbeat: bus-factor risk is worth one look a quarter even when
# nothing moved. Longer than the weekly cadence, so it can't fire every run.
HB_F="$DATA/contributor-health-last-wake"
DAYS_SINCE=999
if [ -f "$HB_F" ]; then
  HB=$(cat "$HB_F" 2>/dev/null || echo "")
  case "$HB" in ''|*[!0-9]*) HB=0;; esac
  [ "$HB" -gt 0 ] && DAYS_SINCE=$(( (NOW_EPOCH - HB) / 86400 ))
fi

WAKE=false
[ "$HAS_MOVED" = "true" ] && WAKE=true
[ "$HAS_DEGRADED" = "true" ] && WAKE=true
[ "$FIRST_RUN" = "true" ] && WAKE=true
[ "$DAYS_SINCE" -ge 90 ] && WAKE=true
[ "$WAKE" = "true" ] && printf '%s' "$NOW_EPOCH" > "$HB_F"

printf '{"wakeAgent": %s, "data": {"status": "%s", "repos": %s, "moved": %s, "degraded_repos": %s, "first_run": %s, "quiet_heartbeat": %s}}\n' \
  "$WAKE" \
  "$([ "$HAS_DEGRADED" = "true" ] && echo partial-fetch-failure || echo ok)" \
  "$ALL" "$MOVED" "$DEGRADED" "$FIRST_RUN" \
  "$([ "$HAS_MOVED" = "false" ] && [ "$HAS_DEGRADED" = "false" ] && [ "$FIRST_RUN" = "false" ] && echo true || echo false)"
