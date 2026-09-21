#!/bin/bash
set -uo pipefail
# Deps: bash, curl, jq, awk, git. GitHub + GA4 auth injected by the OneCLI proxy.
#
# PROJECT HEALTH — one task, daily, for every number this project tracks.
#
# This replaced six tasks (dev-metrics-report, contributor-health-review,
# social-metrics-snapshot, weekly-analytics-report, ledger-publish,
# contributor-nudge) that each fetched their own numbers on their own
# schedule, wrote their own CSV, and woke the model separately. Same data,
# same CSVs, same schemas — one fan-out, one run, one decision about whether
# the model has anything to say.
#
# TWO MODES, decided here, not by the model:
#   collect  every day. The bash below gathers every API-readable number and
#            appends today's rows to the CSVs. The model wakes only to read
#            the social follower counts (no API for those — pages the model
#            has to fetch) and append that one row. Small prompt, cheap wake.
#   post     once a week (POST_DOW, default Monday). Everything in collect,
#            plus the model composes and posts the status: dev numbers to the
#            developer tier, social + traffic to the team-lead tier, with
#            WoW/MoM computed from the daily rows this task has been writing.
#
# The daily rows are the point: they are what make week-over-week and
# month-over-month real instead of two points and a guess, and they are what
# the agent reads (tail/grep, never the whole file) when someone asks how the
# project is doing on a Wednesday.
#
# LEDGER. Every run commits the CSVs to LEDGER_BRANCH on LEDGER_REPO and
# then READS THE ROW BACK from GitHub to confirm it landed — a push that
# reports success and a row that is actually on the branch are different
# claims, and this system once had to verify the second by hand.
DATA="/workspace/agent/plugin-data/community-helper"
mkdir -p "$DATA"

# --- local telemetry (best-effort; never blocks the gate) -------------------
mkdir -p "$DATA/telemetry" 2>/dev/null || true
exec > >(tee >(sed -u "s/^{/{\"_ts\":\"$(date -u +%FT%TZ)\",/" >> "$DATA/telemetry/project-health.jsonl" 2>/dev/null) 2>/dev/null)
if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
REPOS="${COMMUNITY_REPOS:-}"
if [ -z "$REPOS" ]; then
  echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-helper/config.env"}}'
  exit 0
fi

NOW_EPOCH=$(date +%s)
TODAY_D=$(date -u +%Y-%m-%d)
# Post day: 0=Sun..6=Sat, default Monday. `date +%u` is 1..7 (Mon=1) on
# both GNU and BSD; %w is 0..6 — use %w so 0 means Sunday on both.
POST_DOW="${HEALTH_POST_DOW:-1}"
case "$POST_DOW" in ''|*[!0-6]*) POST_DOW=1;; esac
IS_POST_DAY=false
[ "$(date -u +%w)" = "$POST_DOW" ] && IS_POST_DAY=true
# SOCIAL_DAILY=false turns the collect-day model wake off entirely, for a
# project that only wants the weekly post and is happy with weekly follower
# resolution. Default on: the owner asked for daily social data.
SOCIAL_DAILY="${SOCIAL_DAILY:-true}"

CUTOFF_EPOCH=$(( NOW_EPOCH - 604800 ))
SINCE_DATE=$(date -u -d "@$CUTOFF_EPOCH" +%Y-%m-%d 2>/dev/null || date -u -r "$CUTOFF_EPOCH" +%Y-%m-%d 2>/dev/null || echo "")
CUTOFF30=$(( NOW_EPOCH - 2592000 ))
SINCE30=$(date -u -d "@$CUTOFF30" +%Y-%m-%d 2>/dev/null || date -u -r "$CUTOFF30" +%Y-%m-%d 2>/dev/null || echo "")
CUTOFF90=$(( NOW_EPOCH - 7776000 ))
SINCE90=$(date -u -d "@$CUTOFF90" +%Y-%m-%d 2>/dev/null || date -u -r "$CUTOFF90" +%Y-%m-%d 2>/dev/null || echo "")

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# ============================================================================
# 1. GitHub counts — every day. One fan-out per repo; inside it, every call
#    for that repo fires concurrently. A failed fetch records null, never 0:
#    a 0 would corrupt the delta series with a fake swing.
# ============================================================================
i=0
PIDS=()   # wait only on the fetches we started, never on a bare `wait` — the
          # exec > >(tee ...) above also lives in this shell's job table.
for REPO in $REPOS; do
  (
    curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
      "https://api.github.com/search/issues?q=repo:$REPO+is:issue+is:open&per_page=1" > "$TMP/$i.oi" 2>/dev/null &
    curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
      "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:open&per_page=1" > "$TMP/$i.op" 2>/dev/null &
    curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$REPO/releases?per_page=5" > "$TMP/$i.rel" 2>/dev/null &
    curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$REPO" > "$TMP/$i.meta" 2>/dev/null &
    # Zero-comment backlog, oldest first: total_count is the backlog size, the
    # one item fetched is the longest-waiting. A worst-case-visibility signal,
    # not an average response time.
    curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
      "https://api.github.com/search/issues?q=repo:$REPO+is:issue+is:open+comments:0&sort=created&order=asc&per_page=1" > "$TMP/$i.zci" 2>/dev/null &
    SAFEREPO=$(printf '%s' "$REPO" | tr '/' '_')
    KNOWN="$DATA/known-contributors-$SAFEREPO.txt"
    if [ -f "$KNOWN" ] && [ -n "$SINCE_DATE" ]; then
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:merged+merged:%3E%3D$SINCE_DATE&per_page=100" > "$TMP/$i.prs" 2>/dev/null &
    elif [ ! -f "$KNOWN" ]; then
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$REPO/contributors?per_page=100&anon=false" > "$TMP/$i.contrib" 2>/dev/null &
    fi
    # Contributor-health inputs only on the post day: a 90-day window read
    # daily is noise with extra API calls.
    if [ "$IS_POST_DAY" = "true" ] && [ -n "$SINCE30" ] && [ -n "$SINCE90" ]; then
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:merged+merged:%3E%3D$SINCE30&per_page=1" > "$TMP/$i.merged30" 2>/dev/null &
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:closed+is:unmerged+closed:%3E%3D$SINCE30&per_page=1" > "$TMP/$i.unmerged30" 2>/dev/null &
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:merged+merged:%3E%3D$SINCE90&per_page=100" > "$TMP/$i.m90" 2>/dev/null &
    fi
    wait

    OI=$(jq '.total_count // "e"' < "$TMP/$i.oi" 2>/dev/null || echo e); case "$OI" in ''|*e*) OI=null;; esac
    OP=$(jq '.total_count // "e"' < "$TMP/$i.op" 2>/dev/null || echo e); case "$OP" in ''|*e*) OP=null;; esac
    STARS=$(jq '.stargazers_count // "e"' < "$TMP/$i.meta" 2>/dev/null || echo e); case "$STARS" in ''|*e*) STARS=null;; esac
    FORKS=$(jq '.forks_count // "e"' < "$TMP/$i.meta" 2>/dev/null || echo e); case "$FORKS" in ''|*e*) FORKS=null;; esac
    REL=$(jq -c 'if type=="array" then [.[] | {tag: .tag_name, downloads: ([.assets[]?.download_count] | add // 0)}] else null end' < "$TMP/$i.rel" 2>/dev/null || echo null)
    case "$REL" in ''|null) REL=null;; esac
    ZC_ISSUES=$(jq '.total_count // "e"' < "$TMP/$i.zci" 2>/dev/null || echo e); case "$ZC_ISSUES" in ''|*e*) ZC_ISSUES=null;; esac
    OLDEST_ZC=$(jq -r '.items[0].created_at // ""' < "$TMP/$i.zci" 2>/dev/null || echo "")

    # New contributors: bootstrap seeds the known list from /contributors and
    # reports nothing (seeding isn't "new"); later runs diff merged-PR authors
    # against it and append the new ones dated today. `seeded` in place of a
    # date keeps bootstrap-seeded names out of the return-nudge window below.
    NEWCONTRIB=null
    if [ -f "$KNOWN" ] && [ -f "$TMP/$i.prs" ]; then
      AUTHORS=$(jq -c 'if .items then ([.items[].user.login] | unique) else null end' < "$TMP/$i.prs" 2>/dev/null || echo null)
      if [ "$AUTHORS" != "null" ] && [ -n "$AUTHORS" ]; then
        KNOWN_JSON=$(cut -d',' -f1 "$KNOWN" 2>/dev/null | jq -R -s -c 'split("\n") | map(select(length > 0))' || echo '[]')
        NEWCONTRIB=$(jq -c -n --argjson a "$AUTHORS" --argjson k "$KNOWN_JSON" '$a - $k')
        printf '%s\n' "$NEWCONTRIB" | jq -r --arg d "$TODAY_D" '.[] | "\(.),\($d)"' >> "$KNOWN" 2>/dev/null || true
      else NEWCONTRIB='[]'; fi
    elif [ ! -f "$KNOWN" ] && [ -f "$TMP/$i.contrib" ]; then
      if jq -e 'type=="array"' < "$TMP/$i.contrib" >/dev/null 2>&1; then
        jq -r '.[].login | "\(.),seeded"' < "$TMP/$i.contrib" > "$KNOWN" 2>/dev/null || rm -f "$KNOWN"
        NEWCONTRIB='[]'
      fi
    fi

    # Contributor health (post day only). Ratio needs 5+ closed PRs to mean
    # anything; a percentage of two PRs is worse than no percentage.
    HEALTH=null
    if [ "$IS_POST_DAY" = "true" ] && [ -f "$TMP/$i.m90" ]; then
      M30=$(jq '.total_count // "e"' < "$TMP/$i.merged30" 2>/dev/null || echo e); case "$M30" in ''|*e*) M30=null;; esac
      U30=$(jq '.total_count // "e"' < "$TMP/$i.unmerged30" 2>/dev/null || echo e); case "$U30" in ''|*e*) U30=null;; esac
      RATIO=null
      if [ "$M30" != "null" ] && [ "$U30" != "null" ] && [ $(( M30 + U30 )) -ge 5 ]; then
        RATIO=$(awk -v u="$U30" -v t="$(( M30 + U30 ))" 'BEGIN { printf "%.2f", u/t }')
      fi
      CONC=$(jq -c 'if .items then
        ([.items[].user.login] | group_by(.) | map({login: .[0], merged_90d: length}) | sort_by(-.merged_90d)) as $a
        | {distinct_authors_90d: ($a | length), total_merged_90d: .total_count,
           top_author: ($a[0].login // null),
           top_author_share_pct: (if ([$a[].merged_90d] | add // 0) > 0 then (($a[0].merged_90d / ([$a[].merged_90d] | add)) * 100 | round) else null end),
           candidates: [$a[] | select(.merged_90d >= 5) | .login]}
        else null end' < "$TMP/$i.m90" 2>/dev/null || echo null)
      case "$CONC" in ''|null) CONC=null;; esac
      HEALTH=$(printf '{"merged_30d": %s, "unmerged_30d": %s, "unmerged_ratio": %s, "concentration": %s}' "$M30" "$U30" "$RATIO" "$CONC")
    fi

    printf '{"repo": "%s", "stars": %s, "forks": %s, "open_issues": %s, "open_prs": %s, "releases": %s, "new_contributors_7d": %s, "awaiting_issues": %s, "awaiting_oldest": "%s", "health": %s}\n' \
      "$REPO" "$STARS" "$FORKS" "$OI" "$OP" "$REL" "$NEWCONTRIB" "$ZC_ISSUES" "$OLDEST_ZC" "$HEALTH" > "$TMP/$i.json"
  ) &
  PIDS+=("$!")
  i=$((i+1))
done
wait "${PIDS[@]}"

if ! ls "$TMP"/*.json >/dev/null 2>&1; then
  echo '{"wakeAgent": true, "data": {"status": "fetch-failed", "hint": "no repo produced a result — check the token and the sandbox network policy"}}'
  exit 0
fi
REPOS_JSON=$(cat "$TMP"/*.json | jq -c -s '.' 2>/dev/null || echo '[]')
DEGRADED=$(printf '%s' "$REPOS_JSON" | jq -c '[.[] | select(.open_issues == null) | .repo]')

# metrics-history.csv — same schema as before, one row per repo per day.
# releases[] collapses to the latest tag + its downloads; nothing read the
# per-release history and current release data is fresh from the API anyway.
HIST="$DATA/metrics-history.csv"
[ -s "$HIST" ] || echo 'date,repo,stars,forks,open_issues,open_prs,new_contrib_7d,await_issues,await_oldest,rel_latest,dl_latest' > "$HIST"
printf '%s' "$REPOS_JSON" | jq -r --arg d "$TODAY_D" '.[]
  | [$d, .repo, (.stars // ""), (.forks // ""), (.open_issues // ""), (.open_prs // ""),
     (.new_contributors_7d | if . == null then "" else length end),
     (.awaiting_issues // ""), (.awaiting_oldest // ""),
     (.releases[0].tag // ""), (.releases[0].downloads // "")]
  | @csv' | tr -d '"' >> "$HIST" 2>/dev/null || true
{ head -n 1 "$HIST"; tail -n 400 "$HIST" | grep -v '^date,'; } > "$HIST.tmp" 2>/dev/null && mv "$HIST.tmp" "$HIST"

# contributor-health-history.csv — post day only, same schema as before.
if [ "$IS_POST_DAY" = "true" ]; then
  CH="$DATA/contributor-health-history.csv"
  [ -s "$CH" ] || echo 'date,repo,unmerged_ratio,top_author_share_pct' > "$CH"
  printf '%s' "$REPOS_JSON" | jq -r --arg d "$TODAY_D" '.[] | select(.health != null)
    | [$d, .repo, (.health.unmerged_ratio // ""), (.health.concentration.top_author_share_pct // "")] | @csv' \
    | tr -d '"' >> "$CH" 2>/dev/null || true
  { head -n 1 "$CH"; tail -n 520 "$CH" | grep -v '^date,'; } > "$CH.tmp" 2>/dev/null && mv "$CH.tmp" "$CH"
fi

# ============================================================================
# 2. Return-nudge window (post day only) — contributors whose first merged PR
#    was 20–30 days ago and who haven't come back. From the ledger the block
#    above maintains; capped so a big week can't turn into a search flood.
# ============================================================================
NUDGES='[]'
if [ "$IS_POST_DAY" = "true" ]; then
  MAX_CHECKS="${NUDGE_MAX_CHECKS:-4}"; case "$MAX_CHECKS" in ''|*[!0-9]*) MAX_CHECKS=4;; esac
  for REPO in $REPOS; do
    SAFEREPO=$(printf '%s' "$REPO" | tr '/' '_')
    KNOWN="$DATA/known-contributors-$SAFEREPO.txt"; [ -f "$KNOWN" ] || continue
    SEEN="$DATA/nudge-sent-$SAFEREPO.txt"; touch "$SEEN"
    CHECKS=0
    while IFS=, read -r UNAME UDATE; do
      [ -z "$UNAME" ] || [ -z "$UDATE" ] || [ "$UDATE" = "seeded" ] && continue
      grep -qxF "$UNAME" "$SEEN" 2>/dev/null && continue
      UEPOCH=$(date -u -d "$UDATE" +%s 2>/dev/null || date -u -j -f %Y-%m-%d "$UDATE" +%s 2>/dev/null || echo "")
      case "$UEPOCH" in ''|*[!0-9]*) continue;; esac
      AGE_D=$(( (NOW_EPOCH - UEPOCH) / 86400 ))
      [ "$AGE_D" -lt 20 ] || [ "$AGE_D" -gt 30 ] && continue
      [ "$CHECKS" -ge "$MAX_CHECKS" ] && continue
      CHECKS=$((CHECKS+1))
      CNT=$(curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:merged+author:$UNAME&per_page=1" 2>/dev/null \
        | jq '.total_count // "e"' 2>/dev/null || echo e)
      case "$CNT" in ''|*e*) continue;; esac   # fetch failed: don't ack, retry next week
      echo "$UNAME" >> "$SEEN"
      [ "$CNT" -le 1 ] && NUDGES=$(jq -c -n --argjson a "$NUDGES" --arg r "$REPO" --arg u "$UNAME" --arg d "$UDATE" --argjson ad "$AGE_D" \
        '$a + [{repo: $r, username: $u, first_contribution: $d, days_ago: $ad}]')
    done < "$KNOWN"
  done
fi

# ============================================================================
# 3. GA4 traffic (post day only). One request, three GA4-native date ranges,
#    so WoW and MoM come from GA4 itself over real calendar windows. Only the
#    current window is written to the CSV; the agent computes longer trends
#    from the daily rows. The old per-dimension breakdown (AI referrals,
#    countries, browsers, bot heuristics) is deliberately gone — deep
#    analytics narration, not project health, and the largest block of code
#    this system had.
# ============================================================================
TRAFFIC='[]'
PROPS="${GA4_PROPERTIES:-${GA4_PROPERTY_ID:-}}"
if [ "$IS_POST_DAY" = "true" ] && [ -n "$PROPS" ]; then
  IFS=',' read -ra PAIRS <<< "$PROPS"
  for PAIR in "${PAIRS[@]}"; do
    if [[ "$PAIR" == *:* ]]; then LABEL="${PAIR%%:*}"; PROPERTY_ID="${PAIR#*:}"; else PROPERTY_ID="$PAIR"; LABEL="property-${PROPERTY_ID}"; fi
    LABEL=$(printf '%s' "$LABEL" | tr -c 'A-Za-z0-9_-' '_')
    TH="$DATA/traffic-history-${LABEL}.csv"
    RESP=$(curl -sS --max-time 25 -X POST "https://analyticsdata.googleapis.com/v1beta/properties/$PROPERTY_ID:runReport" \
      -H 'Content-Type: application/json' \
      -d '{"dateRanges":[{"startDate":"7daysAgo","endDate":"yesterday","name":"current"},{"startDate":"14daysAgo","endDate":"8daysAgo","name":"previous_week"},{"startDate":"35daysAgo","endDate":"29daysAgo","name":"previous_month"}],"dimensions":[{"name":"dateRange"}],"metrics":[{"name":"activeUsers"},{"name":"sessions"},{"name":"screenPageViews"},{"name":"engagementRate"}]}' 2>/dev/null || echo '')
    row() { printf '%s' "$RESP" | jq -c --arg n "$1" '[.rows[]? | select(.dimensionValues[0].value==$n)][0] // empty
      | {activeUsers:(.metricValues[0].value|tonumber), sessions:(.metricValues[1].value|tonumber), pageViews:(.metricValues[2].value|tonumber), engagementRate:(.metricValues[3].value|tonumber)}' 2>/dev/null || echo ''; }
    CUR=$(row current); PW=$(row previous_week); PM=$(row previous_month)
    if [ -z "$CUR" ]; then
      TRAFFIC=$(jq -c --argjson t "$TRAFFIC" --arg l "$LABEL" --arg id "$PROPERTY_ID" -n '$t + [{label:$l, property_id:$id, status:"fetch-failed"}]')
      continue
    fi
    [ -s "$TH" ] || echo 'date,activeUsers,sessions,pageViews,engagementRate' > "$TH"
    printf '%s' "$CUR" | jq -r --arg d "$TODAY_D" '[$d, .activeUsers, .sessions, .pageViews, .engagementRate] | @csv' | tr -d '"' >> "$TH" 2>/dev/null || true
    { head -n 1 "$TH"; tail -n 370 "$TH" | grep -v '^date,'; } > "$TH.tmp" 2>/dev/null && mv "$TH.tmp" "$TH"
    TRAFFIC=$(jq -c --argjson t "$TRAFFIC" --arg l "$LABEL" --arg id "$PROPERTY_ID" \
      --argjson c "$CUR" --argjson pw "${PW:-null}" --argjson pm "${PM:-null}" -n \
      '$t + [{label:$l, property_id:$id, status:"ok", current:$c, previous_week:$pw, previous_month:$pm}]')
  done
fi

# ============================================================================
# 4. Ledger: commit every history CSV to LEDGER_BRANCH on LEDGER_REPO, then
#    read today's metrics row back from GitHub. Unset LEDGER_REPO is reported,
#    not fatal — but it means these series die with the container.
#    Always includes social-metrics-history.jsonl: the frozen pre-CSV
#    follower archive, real readings that can never be re-fetched.
# ============================================================================
LEDGER='{"status":"not-configured"}'
REPO_L="${LEDGER_REPO:-}"; BRANCH="${LEDGER_BRANCH:-agent-metrics}"; SUBDIR="${LEDGER_PATH:-agent-metrics}"
if [ -n "$REPO_L" ]; then
  ok=true
  case "$REPO_L" in [A-Za-z0-9_.-]*/[A-Za-z0-9_.-]*) ;; *) ok=false;; esac
  case "$BRANCH" in -*) ok=false;; esac
  case "$SUBDIR" in /*|*..*|-*) ok=false;; esac
  if [ "$ok" != "true" ]; then
    LEDGER='{"status":"bad-config","hint":"LEDGER_REPO must be owner/repo; LEDGER_BRANCH must not start with -; LEDGER_PATH must be a plain relative name"}'
  else
    PRESENT=()
    for f in metrics-history.csv contributor-health-history.csv social-metrics-history.csv social-metrics-history.jsonl; do
      [ -f "$DATA/$f" ] && PRESENT+=("$f")
    done
    for f in "$DATA"/traffic-history-*.csv; do [ -f "$f" ] && PRESENT+=("$(basename "$f")"); done
    WORK="$DATA/.ledger-repo"
    lfail() { LEDGER=$(jq -nc --arg s "$1" --arg h "$2" '{status:$s, hint:$h}'); }
    if [ ! -d "$WORK/.git" ]; then
      rm -rf "$WORK"
      git clone --quiet --depth 1 "https://github.com/$REPO_L.git" "$WORK" >/dev/null 2>&1 || { rm -rf "$WORK"; lfail clone-failed "cannot clone the ledger repo — check the name, that github.com (git) is allowlisted, and that a github.com git credential with write access is in the vault"; }
    fi
    if [ -d "$WORK/.git" ]; then
      if git -C "$WORK" ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
        # Full-depth fetch of the ledger branch: a shallow-rooted branch cannot be pushed to a remote missing its base.
        git -C "$WORK" fetch --quiet --depth 1000000 origin "$BRANCH" >/dev/null 2>&1 && git -C "$WORK" checkout --quiet -B "$BRANCH" FETCH_HEAD >/dev/null 2>&1 || lfail fetch-failed "ledger branch exists upstream but could not be checked out"
      elif git -C "$WORK" show-ref --quiet --verify "refs/heads/$BRANCH"; then
        git -C "$WORK" checkout --quiet "$BRANCH" >/dev/null 2>&1 || lfail checkout-failed "local ledger branch could not be checked out"
      else
        git -C "$WORK" checkout --quiet --orphan "$BRANCH" >/dev/null 2>&1 || lfail branch-create-failed "could not create the ledger branch"
        git -C "$WORK" rm -rq --cached . >/dev/null 2>&1 || true
        find "$WORK" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} + 2>/dev/null || true
      fi
      if [ "$(printf '%s' "$LEDGER" | jq -r .status)" = "not-configured" ]; then
        mkdir -p "$WORK/$SUBDIR"
        for f in "${PRESENT[@]}"; do cp "$DATA/$f" "$WORK/$SUBDIR/$f"; done
        if [ -n "$(git -C "$WORK" status --porcelain 2>/dev/null)" ]; then
          git -C "$WORK" config user.email >/dev/null 2>&1 || { git -C "$WORK" config user.email "noreply@localhost"; git -C "$WORK" config user.name "Community Agent"; }
          git -C "$WORK" add -A >/dev/null 2>&1
          git -C "$WORK" commit --quiet -m "chore(metrics): history for $TODAY_D" >/dev/null 2>&1 || lfail commit-failed "tree changed but the commit was refused"
        fi
        REMOTE_SHA=$(git -C "$WORK" ls-remote origin "refs/heads/$BRANCH" 2>/dev/null | awk '{print $1}')
        LOCAL_SHA=$(git -C "$WORK" rev-parse HEAD 2>/dev/null || echo "")
        if [ -n "$LOCAL_SHA" ] && [ "$REMOTE_SHA" != "$LOCAL_SHA" ]; then
          # Never --force: a moved upstream branch must fail loudly, not be overwritten.
          git -C "$WORK" push --quiet origin "refs/heads/$BRANCH:refs/heads/$BRANCH" >/dev/null 2>&1 || lfail push-failed "committed locally but could not push — the vault github.com (git) credential may lack write access, or the branch moved upstream. Kept, retried next run"
        fi
        if [ "$(printf '%s' "$LEDGER" | jq -r .status)" = "not-configured" ]; then
          # Read-back: is today's metrics row actually on the branch? A push
          # that returned 0 and a row a human can see on GitHub are different
          # claims — this system once verified the second by hand.
          LOCAL_LAST=$(tail -n 1 "$HIST" 2>/dev/null)
          REMOTE_LAST=$(curl -fsS --max-time 10 "https://raw.githubusercontent.com/$REPO_L/$BRANCH/$SUBDIR/metrics-history.csv" 2>/dev/null | tail -n 1)
          if [ -n "$REMOTE_LAST" ] && [ "$REMOTE_LAST" = "$LOCAL_LAST" ]; then
            LEDGER=$(jq -nc --arg b "$BRANCH" --arg f "$(IFS=,; echo "${PRESENT[*]}")" '{status:"published-and-verified", branch:$b, files:$f}')
          else
            LEDGER=$(jq -nc --arg b "$BRANCH" --arg r "${REMOTE_LAST:-}" '{status:"published-unverified", branch:$b, hint:"push succeeded but the row read back from GitHub does not match today'"'"'s local row — raw content may lag by a minute; if this persists, the branch is not what we think it is", remote_last_row:$r}')
          fi
        fi
      fi
    fi
  fi
fi

# ============================================================================
# 5. Decide. Post day: the model composes and posts. Collect day: the model
#    only reads social counts and appends that row — unless SOCIAL_DAILY is
#    off, in which case nothing has anything to say and the run is 0-token.
# ============================================================================
MODE=collect; [ "$IS_POST_DAY" = "true" ] && MODE=post
WAKE=true
[ "$MODE" = "collect" ] && [ "$SOCIAL_DAILY" != "true" ] && WAKE=false
[ "$(printf '%s' "$DEGRADED" | jq 'length')" -gt 0 ] && WAKE=true   # a broken fetch must never read as a quiet day

printf '{"wakeAgent": %s, "data": {"mode": "%s", "date": "%s", "repos": %s, "degraded_repos": %s, "nudges": %s, "traffic": %s, "ledger": %s}}\n' \
  "$WAKE" "$MODE" "$TODAY_D" "$REPOS_JSON" "$DEGRADED" "$NUDGES" "$TRAFFIC" "$LEDGER"
