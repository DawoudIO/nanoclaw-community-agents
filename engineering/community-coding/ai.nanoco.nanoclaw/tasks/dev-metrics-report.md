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
  CUTOFF_EPOCH=$(( $(date +%s) - 604800 ))
  SINCE_DATE=$(date -u -d "@$CUTOFF_EPOCH" +%Y-%m-%d 2>/dev/null || date -u -r "$CUTOFF_EPOCH" +%Y-%m-%d 2>/dev/null || echo "")
  TMP=$(mktemp -d)
  i=0
  for REPO in $REPOS; do
    (
      # Four calls fire concurrently (not sequentially) so one repo's total
      # wall time stays near one request's latency, not the sum of four.
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:issue+is:open&per_page=1" \
        > "$TMP/$i.oi" 2>/dev/null &
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:open&per_page=1" \
        > "$TMP/$i.op" 2>/dev/null &
      curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$REPO/releases?per_page=5" \
        > "$TMP/$i.rel" 2>/dev/null &
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

      # New-contributor tracking: bootstrap seeds known-contributors from the
      # existing contributor list (first run never reports a count — seeding
      # itself isn't "new"); later runs diff this period's merged-PR authors
      # against the known list, report the new ones, and append them so they
      # aren't flagged again. A failed/skipped bootstrap or fetch degrades to
      # null, same as every other metric here.
      NEWCONTRIB=null
      if [ -f "$KNOWN" ] && [ -f "$TMP/$i.prs" ]; then
        AUTHORS=$(jq -c 'if .items then ([.items[].user.login] | unique) else null end' < "$TMP/$i.prs" 2>/dev/null || echo null)
        if [ "$AUTHORS" != "null" ] && [ -n "$AUTHORS" ]; then
          KNOWN_JSON=$(jq -R -s -c 'split("\n") | map(select(length > 0))' < "$KNOWN" 2>/dev/null || echo '[]')
          NEWCONTRIB=$(jq -c -n --argjson a "$AUTHORS" --argjson k "$KNOWN_JSON" '$a - $k')
          printf '%s\n' "$NEWCONTRIB" | jq -r '.[]' >> "$KNOWN" 2>/dev/null || true
        else
          NEWCONTRIB='[]'
        fi
      elif [ ! -f "$KNOWN" ] && [ -f "$TMP/$i.contrib" ]; then
        if jq -e 'type=="array"' < "$TMP/$i.contrib" >/dev/null 2>&1; then
          jq -r '.[].login' < "$TMP/$i.contrib" > "$KNOWN" 2>/dev/null || rm -f "$KNOWN"
          NEWCONTRIB='[]'
        fi
      fi

      printf '{"repo": "%s", "open_issues": %s, "open_prs": %s, "releases": %s, "new_contributors_7d": %s}\n' \
        "$REPO" "$OI" "$OP" "$REL" "$NEWCONTRIB" > "$TMP/$i.json"
    ) &
    i=$((i+1))
  done
  wait
  TODAY=$(cat "$TMP"/*.json | jq -c -s 'map({(.repo): {open_issues, open_prs, releases, new_contributors_7d}}) | add // {}')
  rm -rf "$TMP"
  PREV=$(jq -c '.[-1].metrics // {}' "$HIST")
  jq -c --argjson m "$TODAY" --arg d "$(date -u +%Y-%m-%d)" \
    '. + [{date: $d, metrics: $m}] | .[-30:]' "$HIST" > "$HIST.tmp" && mv "$HIST.tmp" "$HIST"
  printf '{"wakeAgent": true, "data": {"today": %s, "previous": %s}}\n' "$TODAY" "$PREV"
---
Write the daily dev metrics section for your lead agent's dev-facing report,
using `scriptOutput.today` and `scriptOutput.previous` (the prior run's
numbers, already fetched — don't re-query).

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

Hand it to your lead — you don't post it to a channel yourself.
