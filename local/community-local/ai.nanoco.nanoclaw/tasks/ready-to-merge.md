---
schedule: "47 9,17 * * *"
script: |
  #!/bin/bash
  set -uo pipefail
  # Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
  #
  # Approved-and-open PRs: reviewed, ready, and just not merged yet. A
  # contributor did the work and a maintainer already said yes — leaving that
  # sitting is the single most discouraging thing this system can fail to
  # notice, which is why it gets its own task instead of being buried in a
  # daily metrics digest.
  #
  # Split out of dev-metrics-report. It belongs to the LOCAL agent because the
  # output is a list, not an assessment: the search itself decides what is
  # approved, so the model only has to relay it. It runs twice daily rather
  # than daily because merge-readiness is time-sensitive in a way that trend
  # counts are not.
  #
  # Wake policy — the honest middle between nagging and forgetting:
  #   * the set of approved PRs CHANGED  -> wake now (something new is ready)
  #   * same set as last reported        -> stay quiet, but resurface weekly,
  #                                         so a PR sitting for a month gets
  #                                         mentioned ~4 times, not 60
  #   * a fetch failed                   -> wake, because "nothing ready" and
  #                                         "cannot see" must never look alike
  DATA="/workspace/agent/plugin-data/community-local"
  mkdir -p "$DATA"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  REPOS="${COMMUNITY_REPOS:-}"
  if [ -z "$REPOS" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-local/config.env"}}'
    exit 0
  fi

  NOW_EPOCH=$(date +%s)
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  i=0
  for REPO in $REPOS; do
    (
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:open+review:approved&sort=created&order=asc&per_page=10" \
        > "$TMP/$i.raw" 2>/dev/null
      # A failed fetch records null, never an empty list — an empty list would
      # read as "nothing is waiting", which is the opposite of the truth.
      OUT=$(jq -c --arg r "$REPO" 'if .items then
          {repo: $r,
           count: .total_count,
           truncated: (.total_count > (.items | length)),
           prs: [.items[] | {number,
                             title: (.title[0:120]),
                             author: .user.login,
                             url: .html_url,
                             created_at,
                             days_open: (((now - ((.created_at | fromdateiso8601?) // now)) / 86400) | floor)}]}
        else {repo: $r, count: null, truncated: false, prs: []} end' \
        < "$TMP/$i.raw" 2>/dev/null || echo "")
      [ -z "$OUT" ] && OUT=$(jq -c -n --arg r "$REPO" '{repo: $r, count: null, truncated: false, prs: []}')
      printf '%s\n' "$OUT" > "$TMP/$i.json"
    ) &
    i=$((i+1))
  done
  wait

  # No .json at all (every subshell died) must still produce valid JSON.
  if ! ls "$TMP"/*.json >/dev/null 2>&1; then
    echo '{"wakeAgent": true, "data": {"status": "fetch-failed", "hint": "no repo produced a result — check the token and the sandbox network policy"}}'
    exit 0
  fi

  ALL=$(cat "$TMP"/*.json | jq -c -s '.' 2>/dev/null || echo '[]')
  DEGRADED=$(printf '%s' "$ALL" | jq -c '[.[] | select(.count == null) | .repo]')
  HAS_DEGRADED=$(printf '%s' "$DEGRADED" | jq 'length > 0')
  READY=$(printf '%s' "$ALL" | jq -c '[.[] | select(.count != null and .count > 0)]')
  TOTAL=$(printf '%s' "$READY" | jq '[.[].count] | add // 0')

  # Identity of the current set: repo#number pairs, sorted. This is what
  # "changed" means — a title edit or a new approval on an already-listed PR
  # is not news; a different PR being ready is.
  KEYS=$(printf '%s' "$READY" | jq -r '[.[] | .repo as $r | .prs[] | "\($r)#\(.number)"] | sort | join(",")')
  SEEN_F="$DATA/ready-to-merge-last"
  PREV_KEYS=$(cat "$SEEN_F" 2>/dev/null || echo "")
  CHANGED=false
  [ "$KEYS" != "$PREV_KEYS" ] && CHANGED=true

  # Weekly resurface for an unchanged, non-empty set.
  HB_F="$DATA/ready-to-merge-last-wake"
  DAYS_SINCE_WAKE=999
  if [ -f "$HB_F" ]; then
    HB=$(cat "$HB_F" 2>/dev/null || echo "")
    case "$HB" in ''|*[!0-9]*) HB=0;; esac
    [ "$HB" -gt 0 ] && DAYS_SINCE_WAKE=$(( (NOW_EPOCH - HB) / 86400 ))
  fi

  # Which are new since last report, and which the maintainers have now been
  # told about more than once — computed here so the agent never has to guess.
  NEWLY=$(jq -c -n --argjson r "$READY" --arg prev "$PREV_KEYS" '
    ($prev | split(",") | map(select(length > 0))) as $p
    | [ $r[] | .repo as $repo | .prs[] | select((($repo + "#" + (.number|tostring)) | IN($p[])) | not) | {repo: $repo, number, title, author, url, days_open} ]')

  WAKE=false
  if [ "$CHANGED" = "true" ] && [ "$TOTAL" -gt 0 ]; then WAKE=true; fi
  if [ "$HAS_DEGRADED" = "true" ]; then WAKE=true; fi
  if [ "$TOTAL" -gt 0 ] && [ "$DAYS_SINCE_WAKE" -ge 7 ]; then WAKE=true; fi

  if [ "$WAKE" = "true" ]; then
    printf '%s' "$KEYS" > "$SEEN_F"
    printf '%s' "$NOW_EPOCH" > "$HB_F"
  fi

  STATUS=ready
  [ "$TOTAL" -eq 0 ] && STATUS=none-waiting
  [ "$HAS_DEGRADED" = "true" ] && STATUS=partial-fetch-failure

  printf '{"wakeAgent": %s, "data": {"status": "%s", "total": %s, "repos": %s, "newly_ready": %s, "degraded_repos": %s, "resurfaced": %s}}\n' \
    "$WAKE" "$STATUS" "$TOTAL" "$READY" "$NEWLY" "$DEGRADED" \
    "$([ "$CHANGED" = "false" ] && [ "$TOTAL" -gt 0 ] && echo true || echo false)"
---

Approved PRs that are still open. Someone did the work, a maintainer already
said yes, and it is sitting there — which is the most discouraging way for a
contribution to end, and the cheapest thing in this whole system to fix.

**This is a list, not an assessment.** The search decided what counts as
approved; you relay it. Do not judge whether a PR *should* be merged, do not
review the code, and do not tell anyone to merge it. You are surfacing
something that fell through a gap.

**If `status` is `fetch-failed` or `partial-fetch-failure`**: say which repos
could not be read and stop. `degraded_repos` names them. "Nothing is waiting"
and "I cannot see" must never come out of your mouth sounding the same.

Otherwise, hand your lead one short block per repo in `repos`:

- The PR number, title, author, and URL — the URL matters most, it is what
  turns this from a notification into a click.
- `days_open`, said plainly ("open 34 days"). No adjectives; the number
  carries it.
- Oldest first. The script already sorted them that way.

Two fields shape the framing, and getting this right is the difference
between useful and nagging:

- **`newly_ready`** — approved since your last report. Lead with these. This
  is the actionable half.
- **`resurfaced: true`** — the set has not changed since last time; this is
  the weekly re-mention of PRs you have already reported. Say so explicitly
  ("still waiting, no change since last week") so nobody reads it as new
  activity. It fires weekly, not daily, precisely so it stays readable.

If `truncated` is true on a repo, more than ten approved PRs are open there
and you are seeing the ten oldest — say so, because that is a queue problem
rather than a list.

Keep the whole thing short. A maintainer reading this wants the links.
