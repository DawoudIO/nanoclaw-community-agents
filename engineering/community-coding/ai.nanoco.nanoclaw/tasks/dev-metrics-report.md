---
schedule: "0 12 * * *"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
  # Repos are fetched IN PARALLEL to stay inside the platform's script
  # timeout, and a failed fetch records null (unknown) — never zero, which
  # would corrupt the delta series with fake swings.
  DATA="/workspace/agent/plugin-data/community-coding"
  mkdir -p "$DATA"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  REPOS="${COMMUNITY_REPOS:-}"
  if [ -z "$REPOS" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-coding/config.env"}}'
    exit 0
  fi
  HIST="$DATA/metrics-history.json"
  if [ ! -f "$HIST" ]; then echo '[]' > "$HIST"; fi
  NOW_EPOCH=$(date +%s)
  CUTOFF_EPOCH=$(( NOW_EPOCH - 604800 ))
  SINCE_DATE=$(date -u -d "@$CUTOFF_EPOCH" +%Y-%m-%d 2>/dev/null || date -u -r "$CUTOFF_EPOCH" +%Y-%m-%d 2>/dev/null || echo "")
  CUTOFF30_EPOCH=$(( NOW_EPOCH - 2592000 ))
  SINCE30_DATE=$(date -u -d "@$CUTOFF30_EPOCH" +%Y-%m-%d 2>/dev/null || date -u -r "$CUTOFF30_EPOCH" +%Y-%m-%d 2>/dev/null || echo "")
  CUTOFF90_EPOCH=$(( NOW_EPOCH - 7776000 ))
  SINCE90_DATE=$(date -u -d "@$CUTOFF90_EPOCH" +%Y-%m-%d 2>/dev/null || date -u -r "$CUTOFF90_EPOCH" +%Y-%m-%d 2>/dev/null || echo "")
  TMP=$(mktemp -d)
  i=0
  for REPO in $REPOS; do
    (
      # Calls fire concurrently (not sequentially) so one repo's total wall
      # time stays near one request's latency, not the sum of all of them.
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:issue+is:open&per_page=1" \
        > "$TMP/$i.oi" 2>/dev/null &
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:open&per_page=1" \
        > "$TMP/$i.op" 2>/dev/null &
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$REPO/releases?per_page=5" \
        > "$TMP/$i.rel" 2>/dev/null &
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$REPO" \
        > "$TMP/$i.meta" 2>/dev/null &
      # Zero-comment backlog: a cheap proxy for "awaiting first response" —
      # sorted oldest-first, so total_count is the backlog size and the one
      # item fetched is the longest-waiting case. This is NOT a true average
      # response time (that needs a per-item timeline fetch, too expensive to
      # run per-repo per-day) and a bot-authored first comment also removes an
      # item from this bucket — treat it as a worst-case-visibility signal,
      # never as a precise average.
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:issue+is:open+comments:0&sort=created&order=asc&per_page=1" \
        > "$TMP/$i.zci" 2>/dev/null &
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:open+comments:0&sort=created&order=asc&per_page=1" \
        > "$TMP/$i.zcp" 2>/dev/null &
      # PR closed-without-merge, last 30 days (not 7 — most repos here close
      # too few PRs a week for a 7-day ratio to mean anything). A rising
      # ratio flags spam or maintainer overload per GitHub's own OSPO
      # guidance.
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:merged+merged:%3E%3D$SINCE30_DATE&per_page=1" \
        > "$TMP/$i.merged30" 2>/dev/null &
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:closed+is:unmerged+closed:%3E%3D$SINCE30_DATE&per_page=1" \
        > "$TMP/$i.unmerged30" 2>/dev/null &
      # Contribution concentration, last 90 days: how dependent is the repo
      # on its single most-active author (CHAOSS "Contributor Absence Factor"
      # territory), and who has enough sustained merged work to be a
      # delegation/promotion candidate. The best-documented failure mode in
      # open source is one person doing everything until they quit — this is
      # the load signal that surfaces it before it happens.
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:merged+merged:%3E%3D$SINCE90_DATE&per_page=100" \
        > "$TMP/$i.m90" 2>/dev/null &
      # Approved-and-open PRs: reviewed, ready, just not merged yet — the
      # single worst thing to leave sitting once a contributor has already
      # done the work and a maintainer has already said yes. Oldest-first, up
      # to 10, with enough detail (title/author/url) to link directly.
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:open+review:approved&sort=created&order=asc&per_page=10" \
        > "$TMP/$i.readytomerge" 2>/dev/null &
      SAFEREPO=$(printf '%s' "$REPO" | tr '/' '_')
      KNOWN="$DATA/known-contributors-$SAFEREPO.txt"
      if [ -f "$KNOWN" ] && [ -n "$SINCE_DATE" ]; then
        curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
          "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:merged+merged:%3E%3D$SINCE_DATE&per_page=100" \
          > "$TMP/$i.prs" 2>/dev/null &
      elif [ ! -f "$KNOWN" ]; then
        curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
          "https://api.github.com/repos/$REPO/contributors?per_page=100&anon=false" \
          > "$TMP/$i.contrib" 2>/dev/null &
      fi
      wait

      OI=$(jq '.total_count // "parse-error"' < "$TMP/$i.oi" 2>/dev/null || echo parse-error)
      OP=$(jq '.total_count // "parse-error"' < "$TMP/$i.op" 2>/dev/null || echo parse-error)
      case "$OI" in ''|*parse-error*) OI=null;; esac
      case "$OP" in ''|*parse-error*) OP=null;; esac
      REL=$(jq -c 'if type=="array" then [.[] | {tag: .tag_name, downloads: ([.assets[]?.download_count] | add // 0)}] else null end' < "$TMP/$i.rel" 2>/dev/null || echo null)
      case "$REL" in ''|null) REL=null;; esac
      STARS=$(jq '.stargazers_count // "parse-error"' < "$TMP/$i.meta" 2>/dev/null || echo parse-error)
      FORKS=$(jq '.forks_count // "parse-error"' < "$TMP/$i.meta" 2>/dev/null || echo parse-error)
      case "$STARS" in ''|*parse-error*) STARS=null;; esac
      case "$FORKS" in ''|*parse-error*) FORKS=null;; esac

      ZC_ISSUES=$(jq '.total_count // "parse-error"' < "$TMP/$i.zci" 2>/dev/null || echo parse-error)
      case "$ZC_ISSUES" in ''|*parse-error*) ZC_ISSUES=null;; esac
      OLDEST_ZC_ISSUE=$(jq -r '.items[0].created_at // ""' < "$TMP/$i.zci" 2>/dev/null || echo "")
      ZC_PRS=$(jq '.total_count // "parse-error"' < "$TMP/$i.zcp" 2>/dev/null || echo parse-error)
      case "$ZC_PRS" in ''|*parse-error*) ZC_PRS=null;; esac
      OLDEST_ZC_PR=$(jq -r '.items[0].created_at // ""' < "$TMP/$i.zcp" 2>/dev/null || echo "")

      MERGED30=$(jq '.total_count // "parse-error"' < "$TMP/$i.merged30" 2>/dev/null || echo parse-error)
      case "$MERGED30" in ''|*parse-error*) MERGED30=null;; esac
      UNMERGED30=$(jq '.total_count // "parse-error"' < "$TMP/$i.unmerged30" 2>/dev/null || echo parse-error)
      case "$UNMERGED30" in ''|*parse-error*) UNMERGED30=null;; esac
      # The ratio is arithmetic, not judgment — compute it here, not in the
      # agent's head. null below the 5-sample floor (a noisy percentage from
      # 1-2 PRs is worse than no percentage).
      UNMERGED_RATIO=null
      if [ "$MERGED30" != "null" ] && [ "$UNMERGED30" != "null" ]; then
        TOTAL30=$(( MERGED30 + UNMERGED30 ))
        if [ "$TOTAL30" -ge 5 ]; then
          UNMERGED_RATIO=$(awk -v u="$UNMERGED30" -v t="$TOTAL30" 'BEGIN { printf "%.2f", u/t }')
        fi
      fi
      READYTOMERGE=$(jq -c 'if .items then {count: .total_count, prs: [.items[] | {number, title: (.title[0:120]), author: .user.login, url: .html_url, created_at}]} else null end' < "$TMP/$i.readytomerge" 2>/dev/null || echo null)
      case "$READYTOMERGE" in ''|null) READYTOMERGE=null;; esac
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

      # New-contributor tracking: bootstrap seeds known-contributors from the
      # existing contributor list (first run never reports a count — seeding
      # itself isn't "new"); later runs diff this period's merged-PR authors
      # against the known list, report the new ones, and append them — with
      # today's date, so the return-nudge check below can find them later —
      # so they aren't flagged again. A failed/skipped bootstrap or fetch
      # degrades to null, same as every other metric here. The ledger format
      # is `username,first-contribution-date`. Bootstrap-seeded names get the
      # literal word "seeded" instead of a date: their real first-contribution
      # date is unknown (stamping install-day would dump the entire historical
      # contributor list into the 20-30-day nudge window at once — up to 100
      # sequential search-API calls, a rate-limit flood and a timeout). Only
      # contributors first seen AFTER install ever enter the nudge window.
      NEWCONTRIB=null
      if [ -f "$KNOWN" ] && [ -f "$TMP/$i.prs" ]; then
        AUTHORS=$(jq -c 'if .items then ([.items[].user.login] | unique) else null end' < "$TMP/$i.prs" 2>/dev/null || echo null)
        if [ "$AUTHORS" != "null" ] && [ -n "$AUTHORS" ]; then
          KNOWN_JSON=$(cut -d',' -f1 "$KNOWN" 2>/dev/null | jq -R -s -c 'split("\n") | map(select(length > 0))' || echo '[]')
          NEWCONTRIB=$(jq -c -n --argjson a "$AUTHORS" --argjson k "$KNOWN_JSON" '$a - $k')
          TODAY_D=$(date -u +%Y-%m-%d)
          printf '%s\n' "$NEWCONTRIB" | jq -r --arg d "$TODAY_D" '.[] | "\(.),\($d)"' >> "$KNOWN" 2>/dev/null || true
        else
          NEWCONTRIB='[]'
        fi
      elif [ ! -f "$KNOWN" ] && [ -f "$TMP/$i.contrib" ]; then
        if jq -e 'type=="array"' < "$TMP/$i.contrib" >/dev/null 2>&1; then
          jq -r '.[].login | "\(.),seeded"' < "$TMP/$i.contrib" > "$KNOWN" 2>/dev/null || rm -f "$KNOWN"
          NEWCONTRIB='[]'
        fi
      fi

      # Return-nudge: research shows the steepest contributor drop-off is in
      # the first 30 days, and re-engagement is rare after 90 — so a
      # contributor whose first-ever contribution landed 20-30 days ago,
      # with no second one yet, is in the single highest-leverage window for
      # a maintainer to personally follow up. Checked once per contributor
      # (nudge-sent ledger, so it fires exactly once, not daily), and only
      # for names that just entered the window — a handful of extra calls on
      # a normal day, not a scan of the whole contributor history.
      NUDGES="[]"
      NUDGE_SEEN="$DATA/nudge-sent-$SAFEREPO.txt"
      touch "$NUDGE_SEEN"
      if [ -f "$KNOWN" ]; then
        while IFS=, read -r UNAME UDATE; do
          [ -z "$UNAME" ] && continue
          [ -z "$UDATE" ] && continue
          [ "$UDATE" = "seeded" ] && continue
          if grep -qxF "$UNAME" "$NUDGE_SEEN" 2>/dev/null; then continue; fi
          UEPOCH=$(date -u -d "$UDATE" +%s 2>/dev/null || date -u -j -f %Y-%m-%d "$UDATE" +%s 2>/dev/null || echo "")
          [ -z "$UEPOCH" ] && continue
          AGE_D=$(( (NOW_EPOCH - UEPOCH) / 86400 ))
          if [ "$AGE_D" -ge 20 ] && [ "$AGE_D" -le 30 ]; then
            CNT=$(curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
              "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:merged+author:$UNAME&per_page=1" 2>/dev/null \
              | jq '.total_count // "parse-error"' 2>/dev/null || echo parse-error)
            case "$CNT" in ''|*parse-error*) continue;; esac
            echo "$UNAME" >> "$NUDGE_SEEN"
            if [ "$CNT" -le 1 ]; then
              NUDGES=$(jq -c -n --argjson a "$NUDGES" --arg u "$UNAME" --arg d "$UDATE" --argjson ad "$AGE_D" \
                '$a + [{username: $u, first_contribution: $d, days_ago: $ad}]')
            fi
          fi
        done < "$KNOWN"
      fi

      printf '{"repo": "%s", "stars": %s, "forks": %s, "open_issues": %s, "open_prs": %s, "releases": %s, "new_contributors_7d": %s, "awaiting_first_response": {"issues": %s, "oldest_issue_since": "%s", "prs": %s, "oldest_pr_since": "%s"}, "closed_prs_30d": {"merged": %s, "unmerged": %s, "unmerged_ratio": %s}, "return_nudges": %s, "ready_to_merge": %s, "contribution_concentration": %s}\n' \
        "$REPO" "$STARS" "$FORKS" "$OI" "$OP" "$REL" "$NEWCONTRIB" "$ZC_ISSUES" "$OLDEST_ZC_ISSUE" "$ZC_PRS" "$OLDEST_ZC_PR" "$MERGED30" "$UNMERGED30" "$UNMERGED_RATIO" "$NUDGES" "$READYTOMERGE" "$CONC" > "$TMP/$i.json"
    ) &
    i=$((i+1))
  done
  wait
  # ready_to_merge and return_nudges are live-right-now lists, not trend
  # fields — they're reported fresh every run and never persisted into the
  # 30-day metrics history (a stale PR link in history would be actively
  # misleading once it's merged or closed).
  TODAY=$(cat "$TMP"/*.json | jq -c -s 'map({(.repo): {stars, forks, open_issues, open_prs, releases, new_contributors_7d, awaiting_first_response, closed_prs_30d}}) | add // {}')
  ALL_NUDGES=$(cat "$TMP"/*.json | jq -c -s '[.[] | {repo, nudges: .return_nudges}] | map(select(.nudges | length > 0))')
  ALL_READY=$(cat "$TMP"/*.json | jq -c -s '[.[] | {repo, ready_to_merge}] | map(select(.ready_to_merge != null and (.ready_to_merge.count > 0)))')
  ALL_CONC=$(cat "$TMP"/*.json | jq -c -s '[.[] | {repo, concentration: .contribution_concentration}] | map(select(.concentration != null))')
  rm -rf "$TMP"
  jq -c --argjson m "$TODAY" --arg d "$(date -u +%Y-%m-%d)" \
    '. + [{date: $d, metrics: $m}] | .[-30:]' "$HIST" > "$HIST.tmp" && mv "$HIST.tmp" "$HIST"

  # "previous" is the last snapshot the agent actually REPORTED, not just
  # yesterday's — so when the wake gate below suppresses a few quiet days,
  # the deltas in the next report span the whole gap instead of losing the
  # suppressed days' movement forever. Updated only on a wake.
  LASTREP_F="$DATA/last-reported-metrics.json"
  PREV=$(cat "$LASTREP_F" 2>/dev/null || echo '{}')
  printf '%s' "$PREV" | jq -e . >/dev/null 2>&1 || PREV='{}'

  # A fetch outage must never read as a quiet day: if any repo's core count
  # (open_issues) came back null this run, the token/policy problem gets
  # surfaced immediately — this is the one condition that must not wait for
  # the heartbeat, because "all quiet" and "all broken" would otherwise look
  # identical for up to a week.
  DEGRADED=$(jq -n --argjson t "$TODAY" '[$t | to_entries[] | select(.value.open_issues == null) | .key]' -c)
  HAS_DEGRADED=$(printf '%s' "$DEGRADED" | jq 'length > 0')

  # Wake gate: history is written every day regardless (continuous trend
  # data), but the AGENT only needs to spend tokens writing a report when
  # there's something actionable — a new contributor, a return-nudge window,
  # an approved PR sitting idle, a degraded fetch, or an issue/PR count that
  # actually moved. Cosmetic stars/forks drift alone doesn't justify a daily
  # wake. A 7-day heartbeat forces a wake even on a fully quiet stretch, so
  # the channel never goes silent long enough to look like the task died.
  NOTABLE=$(jq -n --argjson t "$TODAY" --argjson p "$PREV" '
    ($t | to_entries | any(.value.new_contributors_7d != null and (.value.new_contributors_7d | length) > 0)) or
    ($t | to_entries | any(
      ($p[.key].open_issues // null) as $prevoi |
      ($p[.key].open_prs // null) as $prevop |
      (.value.open_issues != $prevoi) or (.value.open_prs != $prevop)
    ))')
  HAS_NUDGES=$(printf '%s' "$ALL_NUDGES" | jq 'length > 0')
  HAS_READY=$(printf '%s' "$ALL_READY" | jq 'length > 0')
  LASTWAKE_F="$DATA/dev-metrics-last-wake"
  DAYS_SINCE_WAKE=999
  if [ -f "$LASTWAKE_F" ]; then
    LW_EPOCH=$(date -u -d "$(cat "$LASTWAKE_F")" +%s 2>/dev/null || date -u -j -f %Y-%m-%d "$(cat "$LASTWAKE_F")" +%s 2>/dev/null || echo 0)
    DAYS_SINCE_WAKE=$(( (NOW_EPOCH - LW_EPOCH) / 86400 ))
  fi
  WAKE=false
  if [ "$NOTABLE" = "true" ] || [ "$HAS_NUDGES" = "true" ] || [ "$HAS_READY" = "true" ] || [ "$HAS_DEGRADED" = "true" ] || [ "$DAYS_SINCE_WAKE" -ge 7 ]; then
    WAKE=true
    date -u +%Y-%m-%d > "$LASTWAKE_F"
    printf '%s' "$TODAY" > "$LASTREP_F"
  fi
  printf '{"wakeAgent": %s, "data": {"today": %s, "previous": %s, "return_nudges": %s, "ready_to_merge": %s, "contribution_concentration": %s, "degraded_repos": %s, "quiet_heartbeat": %s}}\n' \
    "$WAKE" "$TODAY" "$PREV" "$ALL_NUDGES" "$ALL_READY" "$ALL_CONC" "$DEGRADED" "$([ "$NOTABLE" = "false" ] && [ "$HAS_NUDGES" = "false" ] && [ "$HAS_READY" = "false" ] && [ "$HAS_DEGRADED" = "false" ] && echo true || echo false)"
") | map(select(length > 0))' || echo '[]')
          NEWCONTRIB=$(jq -c -n --argjson a "$AUTHORS" --argjson k "$KNOWN_JSON" '$a - $k')
          TODAY_D=$(date -u +%Y-%m-%d)
          printf '%s
' "$NEWCONTRIB" | jq -r --arg d "$TODAY_D" '.[] | "\(.),\($d)"' >> "$KNOWN" 2>/dev/null || true
        else
          NEWCONTRIB='[]'
        fi
      elif [ ! -f "$KNOWN" ] && [ -f "$TMP/$i.contrib" ]; then
        if jq -e 'type=="array"' < "$TMP/$i.contrib" >/dev/null 2>&1; then
          jq -r '.[].login | "\(.),seeded"' < "$TMP/$i.contrib" > "$KNOWN" 2>/dev/null || rm -f "$KNOWN"
          NEWCONTRIB='[]'
        fi
      fi

      # Return-nudge: research shows the steepest contributor drop-off is in
      # the first 30 days, and re-engagement is rare after 90 — so a
      # contributor whose first-ever contribution landed 20-30 days ago,
      # with no second one yet, is in the single highest-leverage window for
      # a maintainer to personally follow up. Checked once per contributor
      # (nudge-sent ledger, so it fires exactly once, not daily), and only
      # for names that just entered the window — a handful of extra calls on
      # a normal day, not a scan of the whole contributor history.
      NUDGES="[]"
      NUDGE_SEEN="$DATA/nudge-sent-$SAFEREPO.txt"
      touch "$NUDGE_SEEN"
      if [ -f "$KNOWN" ]; then
        while IFS=, read -r UNAME UDATE; do
          [ -z "$UNAME" ] && continue
          [ -z "$UDATE" ] && continue
          [ "$UDATE" = "seeded" ] && continue
          if grep -qxF "$UNAME" "$NUDGE_SEEN" 2>/dev/null; then continue; fi
          UEPOCH=$(date -u -d "$UDATE" +%s 2>/dev/null || date -u -j -f %Y-%m-%d "$UDATE" +%s 2>/dev/null || echo "")
          [ -z "$UEPOCH" ] && continue
          AGE_D=$(( (NOW_EPOCH - UEPOCH) / 86400 ))
          if [ "$AGE_D" -ge 20 ] && [ "$AGE_D" -le 30 ]; then
            CNT=$(curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
              "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:merged+author:$UNAME&per_page=1" 2>/dev/null \
              | jq '.total_count // "parse-error"' 2>/dev/null || echo parse-error)
            case "$CNT" in ''|*parse-error*) continue;; esac
            echo "$UNAME" >> "$NUDGE_SEEN"
            if [ "$CNT" -le 1 ]; then
              NUDGES=$(jq -c -n --argjson a "$NUDGES" --arg u "$UNAME" --arg d "$UDATE" --argjson ad "$AGE_D" \
                '$a + [{username: $u, first_contribution: $d, days_ago: $ad}]')
            fi
          fi
        done < "$KNOWN"
      fi

      printf '{"repo": "%s", "stars": %s, "forks": %s, "open_issues": %s, "open_prs": %s, "releases": %s, "new_contributors_7d": %s, "awaiting_first_response": {"issues": %s, "oldest_issue_since": "%s", "prs": %s, "oldest_pr_since": "%s"}, "closed_prs_30d": {"merged": %s, "unmerged": %s, "unmerged_ratio": %s}, "return_nudges": %s, "ready_to_merge": %s}
' \
        "$REPO" "$STARS" "$FORKS" "$OI" "$OP" "$REL" "$NEWCONTRIB" "$ZC_ISSUES" "$OLDEST_ZC_ISSUE" "$ZC_PRS" "$OLDEST_ZC_PR" "$MERGED30" "$UNMERGED30" "$UNMERGED_RATIO" "$NUDGES" "$READYTOMERGE" > "$TMP/$i.json"
    ) &
    i=$((i+1))
  done
  wait
  # ready_to_merge and return_nudges are live-right-now lists, not trend
  # fields — they're reported fresh every run and never persisted into the
  # 30-day metrics history (a stale PR link in history would be actively
  # misleading once it's merged or closed).
  TODAY=$(cat "$TMP"/*.json | jq -c -s 'map({(.repo): {stars, forks, open_issues, open_prs, releases, new_contributors_7d, awaiting_first_response, closed_prs_30d}}) | add // {}')
  ALL_NUDGES=$(cat "$TMP"/*.json | jq -c -s '[.[] | {repo, nudges: .return_nudges}] | map(select(.nudges | length > 0))')
  ALL_READY=$(cat "$TMP"/*.json | jq -c -s '[.[] | {repo, ready_to_merge}] | map(select(.ready_to_merge != null and (.ready_to_merge.count > 0)))')
  rm -rf "$TMP"
  jq -c --argjson m "$TODAY" --arg d "$(date -u +%Y-%m-%d)" \
    '. + [{date: $d, metrics: $m}] | .[-30:]' "$HIST" > "$HIST.tmp" && mv "$HIST.tmp" "$HIST"

  # "previous" is the last snapshot the agent actually REPORTED, not just
  # yesterday's — so when the wake gate below suppresses a few quiet days,
  # the deltas in the next report span the whole gap instead of losing the
  # suppressed days' movement forever. Updated only on a wake.
  LASTREP_F="$DATA/last-reported-metrics.json"
  PREV=$(cat "$LASTREP_F" 2>/dev/null || echo '{}')
  printf '%s' "$PREV" | jq -e . >/dev/null 2>&1 || PREV='{}'

  # A fetch outage must never read as a quiet day: if any repo's core count
  # (open_issues) came back null this run, the token/policy problem gets
  # surfaced immediately — this is the one condition that must not wait for
  # the heartbeat, because "all quiet" and "all broken" would otherwise look
  # identical for up to a week.
  DEGRADED=$(jq -n --argjson t "$TODAY" '[$t | to_entries[] | select(.value.open_issues == null) | .key]' -c)
  HAS_DEGRADED=$(printf '%s' "$DEGRADED" | jq 'length > 0')

  # Wake gate: history is written every day regardless (continuous trend
  # data), but the AGENT only needs to spend tokens writing a report when
  # there's something actionable — a new contributor, a return-nudge window,
  # an approved PR sitting idle, a degraded fetch, or an issue/PR count that
  # actually moved. Cosmetic stars/forks drift alone doesn't justify a daily
  # wake. A 7-day heartbeat forces a wake even on a fully quiet stretch, so
  # the channel never goes silent long enough to look like the task died.
  NOTABLE=$(jq -n --argjson t "$TODAY" --argjson p "$PREV" '
    ($t | to_entries | any(.value.new_contributors_7d != null and (.value.new_contributors_7d | length) > 0)) or
    ($t | to_entries | any(
      ($p[.key].open_issues // null) as $prevoi |
      ($p[.key].open_prs // null) as $prevop |
      (.value.open_issues != $prevoi) or (.value.open_prs != $prevop)
    ))')
  HAS_NUDGES=$(printf '%s' "$ALL_NUDGES" | jq 'length > 0')
  HAS_READY=$(printf '%s' "$ALL_READY" | jq 'length > 0')
  LASTWAKE_F="$DATA/dev-metrics-last-wake"
  DAYS_SINCE_WAKE=999
  if [ -f "$LASTWAKE_F" ]; then
    LW_EPOCH=$(date -u -d "$(cat "$LASTWAKE_F")" +%s 2>/dev/null || date -u -j -f %Y-%m-%d "$(cat "$LASTWAKE_F")" +%s 2>/dev/null || echo 0)
    DAYS_SINCE_WAKE=$(( (NOW_EPOCH - LW_EPOCH) / 86400 ))
  fi
  WAKE=false
  if [ "$NOTABLE" = "true" ] || [ "$HAS_NUDGES" = "true" ] || [ "$HAS_READY" = "true" ] || [ "$HAS_DEGRADED" = "true" ] || [ "$DAYS_SINCE_WAKE" -ge 7 ]; then
    WAKE=true
    date -u +%Y-%m-%d > "$LASTWAKE_F"
    printf '%s' "$TODAY" > "$LASTREP_F"
  fi
  printf '{"wakeAgent": %s, "data": {"today": %s, "previous": %s, "return_nudges": %s, "ready_to_merge": %s, "degraded_repos": %s, "quiet_heartbeat": %s}}
' \
    "$WAKE" "$TODAY" "$PREV" "$ALL_NUDGES" "$ALL_READY" "$DEGRADED" "$([ "$NOTABLE" = "false" ] && [ "$HAS_NUDGES" = "false" ] && [ "$HAS_READY" = "false" ] && [ "$HAS_DEGRADED" = "false" ] && echo true || echo false)"
---
Write the daily dev metrics section for your lead agent's dev-facing report,
using `scriptOutput.today` and `scriptOutput.previous` (the prior run's
numbers, already fetched — don't re-query).

**You're only woken when something moved, a fetch degraded, or a week's gone
by with no wake at all.** History still gets recorded every day whether or
not you're woken, and `previous` is the snapshot from your *last actual
report* (not just yesterday), so your deltas span any suppressed quiet days —
don't second-guess the gate or wonder if data is missing; it isn't.
If `quiet_heartbeat` is `true`, nothing changed at all and you're only being
woken so the channel doesn't go silent long enough to look broken — say one
line ("no notable movement since <date>, still `<key numbers>`") instead of
writing the full skeleton below.

**If `degraded_repos` is non-empty, that comes first, before any numbers**:
those repos' core fetch failed this run (token wiring or network policy, most
likely) — tell your lead which repos and that today's numbers for them are
unknown, not zero. An outage must never be dressed up as a quiet day.

**`ready_to_merge` leads the report, not the trend numbers.** Its shape:
a list of `{repo, ready_to_merge: {count, prs: [...]}}` entries — the actual
PRs are at `prs`, each with number/title/author/url/created_at, and `count`
can exceed the list length (the fetch caps at 10 per repo; when `count` is
larger, say "N approved PRs waiting, oldest 10 listed"). Each PR here has
already been reviewed and approved and is just sitting open — a contributor
did the work, a maintainer already said yes, and nothing happened next.
That's a worse signal than a slow first response: the person cleared every
bar you set and is still waiting. List them oldest first with links, and say
plainly if any have been sitting more than a few days. An empty list is good
news — say so in one line, don't skip the section silently (a lead assembling
the full report needs to know this was checked, not just that it's absent).

Per-release **download deltas** matter: cumulative counts come from
`scriptOutput.today`, yesterday's from `previous` — report both (+N daily /
total). Like the follower series, cumulative downloads are not retroactively
fetchable — and your local history file is NOT backed up, so **always include
the raw cumulative numbers in the report you hand the lead**: the posted
channel message is the recoverable off-box copy of this series.

**A `null` value means the fetch failed — unknown, never zero.** Say
"unavailable today" for it, compute no delta against it, and if the same repo
is null two runs in a row, flag the likely token/policy problem to your lead.
Every real number carries its delta versus the previous run. Call out anything
that moved sharply, and say what you think is behind it only if you actually
checked; otherwise report the move and say the cause is unverified.

**`new_contributors_7d`** is a real, computed list (usernames of people whose
merged PR in the last 7 days is their first ever credited on that repo — not
an estimate). `null` means the fetch failed this run, not zero contributors.
An empty list on the very first run for a repo means the contributor ledger
was just seeded — that run never means "no new contributors," it means
"nothing to compare against yet"; don't report a count from it. If the
project's growth goals include developers/contributors, **name them** in the
report (contributor recognition is the cheapest developer-growth lever there
is — see the marketing agent's growth playbook) rather than just a count.

**`awaiting_first_response`** is a backlog proxy, not a precision metric: the
count of currently-open issues/PRs with zero comments, plus the oldest one's
age. Report it as "N issues have never gotten a reply, oldest is from
`oldest_issue_since`" — never as an average response time, which this data
can't compute. Compare the counts against the previous run; a rising number
or a growing oldest-age is the signal worth flagging, since slow first
response is the single most evidence-backed predictor of a new contributor
never coming back.

**`closed_prs_30d`** gives `merged` and `unmerged` counts over a rolling
30-day window, plus `unmerged_ratio` — already computed by the script, not
something to calculate yourself. `unmerged_ratio` is `null` below a 5-PR
sample floor; when it's `null`, say there's not enough closed-PR volume this
month for a ratio to mean anything, rather than reporting a percentage from
1-2 PRs. When it's a real number, report it as given. A rising ratio over
time can mean more spam/low-quality submissions or a maintainer backlog —
say which, if you can tell, otherwise report the move and mark the cause
unverified.

**`return_nudges`** flags contributors whose first-ever contribution landed
20-30 days ago with no second one yet — the highest-leverage window for a
maintainer to personally reach out (research: this is where most one-time
contributors are lost, and re-engagement is rare after 90 days). Its shape:
`[{repo, nudges: [{username, first_contribution, days_ago}]}]` — the people
are inside each entry's `nudges` list. Each name appears exactly once, ever —
surface it plainly to your lead as a suggested personal outreach, not a
metric to trend. Only contributors whose first contribution happened *after*
this system was installed can appear here (the bootstrap ledger has no real
dates for pre-existing contributors), so expect it empty for the first few
weeks — that's by design, not a bug.

**`contribution_concentration`** is the maintainer-load signal —
`[{repo, concentration: {distinct_authors_90d, total_merged_90d, sampled,
top_author, top_author_share_pct, candidates}}]`. Two things to do with it:
- **Concentration**: when `top_author_share_pct` is high (say 70%+) and
  `distinct_authors_90d` is low, the project is one person deep — the
  best-documented failure mode in open source (58% of maintainers have quit
  or considered quitting; the ones who don't are the ones who share the
  load). Report the number and its trend plainly.
- **`candidates`**: contributors with 5+ merged PRs in 90 days — people with
  demonstrated sustained work who might be worth offering triage rights or a
  bigger role. Frame as suggestions for the owner's judgment; the invitation
  is always the maintainer's, never yours.
**Both go in the owner's private TLDR only, never the public channel report**
— "you are the single point of failure" and "consider promoting X" are
conversations for the maintainer, not announcements. Mark `sampled: true`
data as based on the most recent 100 merged PRs.

This task's numbers are exactly what belongs in the report-formats.md dev
skeleton — nothing more. Security-advisory detail comes from
`security-advisory-sweep` separately, per-PR/issue narrative (duplicates,
stale PRs, maintainer questions) from the triage digest, and the good-first-
issue funnel from `good-first-issue-health`; don't duplicate any of those
here from memory, and don't invent a count no task computes — that would be
guessed, not measured.

Hand it to your lead — you don't post it to a channel yourself.
