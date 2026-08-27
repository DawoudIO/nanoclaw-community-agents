---
schedule: "26 11 * * 3"
script: |
  #!/bin/bash
  set -uo pipefail
  # Deps: bash, curl, jq, awk. GitHub auth injected by the OneCLI proxy.
  #
  # Maintainer-load and PR-throughput signals: how dependent is each repo on a
  # single author, is the close-without-merge rate drifting, and who has enough
  # sustained merged work to be worth a bigger role.
  #
  # WHY THIS IS THE REVIEWER'S TASK, NOT THE LOCAL AGENT'S.
  # Split out of dev-metrics-report, which lives on the local (narration-only)
  # agent. The numbers below are arithmetic and the script computes them — but
  # every one of them is useless without a judgment the local agent is
  # explicitly forbidden to make:
  #   * a rising unmerged ratio means EITHER more low-quality submissions OR a
  #     maintainer backlog. Opposite problems, opposite responses, same number.
  #   * high top-author share means "one person deep" only in context — a
  #     solo-maintainer project at 95% is normal; a ten-person project at 95%
  #     is a bus-factor emergency.
  #   * naming someone a delegation candidate is a judgment about a PERSON.
  #     That is the last thing to put on the weakest tier.
  # So the fetching stays scripted and the interpreting moves to the tier that
  # can do it. Weekly, because these are slow-moving signals — a daily read of
  # a 90-day window is just noise with extra API calls.
  DATA="/workspace/agent/plugin-data/community-coding"
  mkdir -p "$DATA"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  REPOS="${COMMUNITY_REPOS:-}"
  if [ -z "$REPOS" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-coding/config.env"}}'
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
  HIST="$DATA/contributor-health-history.json"
  [ -f "$HIST" ] || echo '[]' > "$HIST"
  jq -e . "$HIST" >/dev/null 2>&1 || echo '[]' > "$HIST"
  PREV=$(jq -c '.[-1].repos // []' "$HIST" 2>/dev/null || echo '[]')
  jq -c --argjson r "$ALL" --arg d "$(date -u +%Y-%m-%d)" \
    '. + [{date: $d, repos: $r}] | .[-52:]' "$HIST" > "$HIST.tmp" 2>/dev/null \
    && mv "$HIST.tmp" "$HIST" || rm -f "$HIST.tmp"

  # Wake only on a real move. Thresholds are deliberate and stated here rather
  # than left to the model: a 10-point ratio swing or a 10-point concentration
  # swing is a signal; 1-2 points is sampling noise on repos this size.
  MOVED=$(jq -c -n --argjson t "$ALL" --argjson p "$PREV" '
    [ $t[] as $cur
      | ($p[] | select(.repo == $cur.repo)) as $old
      | select(
          (($cur.closed_prs_30d.unmerged_ratio != null) and ($old.closed_prs_30d.unmerged_ratio != null)
            and (((($cur.closed_prs_30d.unmerged_ratio | tonumber) - ($old.closed_prs_30d.unmerged_ratio | tonumber)) | fabs) >= 0.10))
          or (($cur.concentration.top_author_share_pct != null) and ($old.concentration.top_author_share_pct != null)
            and ((($cur.concentration.top_author_share_pct - $old.concentration.top_author_share_pct) | fabs) >= 10))
        )
      | {repo: $cur.repo,
         ratio_now: $cur.closed_prs_30d.unmerged_ratio, ratio_before: $old.closed_prs_30d.unmerged_ratio,
         share_now: $cur.concentration.top_author_share_pct, share_before: $old.concentration.top_author_share_pct} ]' \
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
---

Maintainer load and PR throughput. Two numbers per repo, and both are
meaningless on their own — the interpretation is the deliverable, which is
why this task lives with you and not with the local ops agent.

**If `status` is `partial-fetch-failure`**: name the repos in
`degraded_repos` and interpret only the rest. A missing repo is not a healthy
repo.

**If `first_run` is true**: there is no prior week to compare against. Report
the current picture as a baseline, say plainly that it is a baseline, and
draw no trend conclusions. Next run has something to diff against.

## `closed_prs_30d.unmerged_ratio`

The share of resolved PRs that were closed without merging, over 30 days.
`null` means fewer than five PRs closed in the window — too few for a
percentage to mean anything, so say "not enough volume" rather than
reporting a number the script deliberately withheld.

The ratio moving up has two opposite explanations and you have to pick:

- **More low-quality submissions arriving** — drive-by PRs, AI-generated
  noise, wrong-target changes. Look at whether `distinct_authors_90d` is
  climbing at the same time, and at what the recently-closed PRs actually
  were. If this is it, the answer is contribution guidance and templates, not
  more maintainer hours.
- **Maintainers rejecting work they used to merge** — scope tightening,
  burnout, a review standard that moved without being written down. Look at
  whether the same small set of authors is being closed, and whether
  `top_author_share_pct` is rising too.

Say which one you think it is and what you based it on. If the evidence
genuinely does not separate them, say that — an honest "cannot tell from
these numbers, here is what would" is worth more than a coin flip dressed as
analysis.

## `concentration`

`top_author_share_pct` is the share of merged PRs from the single most active
author over 90 days. **A high number is not automatically a problem** — read
it against `distinct_authors_90d`:

- One or two authors total: this is a solo or duo project. 90% is simply what
  that looks like. Do not call it a bus-factor risk; the risk is real but it
  is structural and the maintainer already knows.
- Ten-plus authors and one holds 70%+: **this is the finding.** The project
  looks healthy from outside and is one person deep in practice. The
  best-documented failure mode in open source is one person doing everything
  until they stop.

If `sampled` is true, more than 100 PRs merged in the window and you are
seeing the most recent 100 — fine for a share estimate, worth mentioning
once.

`candidates` lists contributors with 5+ merged PRs in 90 days. These are
people with demonstrated sustained involvement. **Judge fit, don't just
forward the list** — sustained volume is necessary and not sufficient, and
this is a judgment about a person, so be careful and be specific about what
the record actually shows. Name at most two, with the evidence.

## `moved`

Populated when the ratio shifted by 10+ points or the top-author share by
10+ points against last week. This is why you were woken. Lead with it: what
moved, in which direction, and your read on why.

If `quiet_heartbeat` is true, nothing moved and this is the quarterly look —
one or two lines is the correct length. Do not manufacture a finding to
justify the wake.

## Routing

Hand it to your lead as a digest. Never comment on a PR, never post publicly,
and never contact a contributor about their standing — a
delegation-candidate suggestion goes to the owner through your lead and
nowhere else. Your token is read-only; that is deliberate, and this task is
exactly the reason.
