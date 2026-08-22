---
schedule: "15 12 * * *"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
  # Repos are fetched IN PARALLEL to stay inside the platform's script
  # timeout, and a failed fetch records null (unknown) — never zero, which
  # would corrupt the delta series with fake swings.
  DATA="/workspace/agent/plugin-data/community-local"
  mkdir -p "$DATA"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  REPOS="${COMMUNITY_REPOS:-}"
  if [ -z "$REPOS" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-local/config.env"}}'
    exit 0
  fi
  HIST="$DATA/metrics-history.json"
  if [ ! -f "$HIST" ]; then echo '[]' > "$HIST"; fi
  NOW_EPOCH=$(date +%s)
  CUTOFF_EPOCH=$(( NOW_EPOCH - 604800 ))
  SINCE_DATE=$(date -u -d "@$CUTOFF_EPOCH" +%Y-%m-%d 2>/dev/null || date -u -r "$CUTOFF_EPOCH" +%Y-%m-%d 2>/dev/null || echo "")
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

      # Return-nudge lived here and moved to `contributor-nudge`: it was the one
      # serial network path in this otherwise parallel script, and because it
      # printed from the same statement below, a slow nudge check took the whole
      # metrics report down with it. It also reads the ledger this task WRITES
      # (known-contributors-<repo>.txt), which is why the write above stays here.

      printf '{"repo": "%s", "stars": %s, "forks": %s, "open_issues": %s, "open_prs": %s, "releases": %s, "new_contributors_7d": %s, "awaiting_first_response": {"issues": %s, "oldest_issue_since": "%s", "prs": %s, "oldest_pr_since": "%s"}}\n' \
        "$REPO" "$STARS" "$FORKS" "$OI" "$OP" "$REL" "$NEWCONTRIB" "$ZC_ISSUES" "$OLDEST_ZC_ISSUE" "$ZC_PRS" "$OLDEST_ZC_PR" > "$TMP/$i.json"
    ) &
    i=$((i+1))
  done
  wait
  #
  # Approved-PR and maintainer-load signals used to live here too. They moved:
  # ready-to-merge to its own local task (time-sensitive, needs its own
  # cadence), and contributor-health-review to the Reviewer (its numbers are
  # meaningless without a judgment this tier must not make).
  TODAY=$(cat "$TMP"/*.json | jq -c -s 'map({(.repo): {stars, forks, open_issues, open_prs, releases, new_contributors_7d, awaiting_first_response}}) | add // {}')
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
  # there's something actionable — a new contributor, a degraded fetch, or an
  # issue/PR count that
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
  LASTWAKE_F="$DATA/dev-metrics-last-wake"
  DAYS_SINCE_WAKE=999
  if [ -f "$LASTWAKE_F" ]; then
    LW_EPOCH=$(date -u -d "$(cat "$LASTWAKE_F")" +%s 2>/dev/null || date -u -j -f %Y-%m-%d "$(cat "$LASTWAKE_F")" +%s 2>/dev/null || echo 0)
    DAYS_SINCE_WAKE=$(( (NOW_EPOCH - LW_EPOCH) / 86400 ))
  fi
  WAKE=false
  if [ "$NOTABLE" = "true" ] || [ "$HAS_DEGRADED" = "true" ] || [ "$DAYS_SINCE_WAKE" -ge 7 ]; then
    WAKE=true
    date -u +%Y-%m-%d > "$LASTWAKE_F"
    printf '%s' "$TODAY" > "$LASTREP_F"
  fi
  printf '{"wakeAgent": %s, "data": {"today": %s, "previous": %s, "degraded_repos": %s, "quiet_heartbeat": %s}}\n' \
    "$WAKE" "$TODAY" "$PREV" "$DEGRADED" "$([ "$NOTABLE" = "false" ] && [ "$HAS_DEGRADED" = "false" ] && echo true || echo false)"
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

**Not yours:** merge-readiness (the `ready-to-merge` task) — don't mention it.

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

**Not yours:** first-contributor re-engagement. The 20–30 day nudge window
moved to `contributor-nudge` — it is a list of people to follow up with, not a
metric, and it ran on the one serial network path that could take this whole
report down with it.

**Not yours either:** contribution concentration, the unmerged-PR ratio, and
delegation candidates — the Reviewer's `contributor-health-review` owns those,
because each needs a *why* decided before it means anything. If a number here
looks like it belongs there, pass the observation up without interpreting it.
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
