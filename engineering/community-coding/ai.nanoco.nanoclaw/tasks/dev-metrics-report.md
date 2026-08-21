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
  TMP=$(mktemp -d)
  i=0
  for REPO in $REPOS; do
    (
      OI=$(curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:issue+is:open&per_page=1" \
        | jq '.total_count // "parse-error"' 2>/dev/null) || OI=null
      OP=$(curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:open&per_page=1" \
        | jq '.total_count // "parse-error"' 2>/dev/null) || OP=null
      case "$OI" in ''|*parse-error*) OI=null;; esac
      case "$OP" in ''|*parse-error*) OP=null;; esac
      REL=$(curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$REPO/releases?per_page=5" \
        | jq -c 'if type=="array" then [.[] | {tag: .tag_name, downloads: ([.assets[]?.download_count] | add // 0)}] else null end' 2>/dev/null) || REL=null
      case "$REL" in ''|null) REL=null;; esac
      printf '{"repo": "%s", "open_issues": %s, "open_prs": %s, "releases": %s}\n' "$REPO" "$OI" "$OP" "$REL" > "$TMP/$i.json"
    ) &
    i=$((i+1))
  done
  wait
  TODAY=$(cat "$TMP"/*.json | jq -c -s 'map({(.repo): {open_issues, open_prs, releases}}) | add // {}')
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

If the project's growth goals include developers/contributors, include the
new-contributor count when asked for it (countable via the GitHub API).

Hand it to your lead — you don't post it to a channel yourself.
