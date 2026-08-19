---
schedule: "0 */4 * * *"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, curl, jq. GitHub auth is injected by the OneCLI proxy for
  # api.github.com — no token in this file, no `gh` CLI (it refuses to run
  # without local auth config, which containers deliberately don't have).
  DATA="/workspace/agent/plugin-data/community-coding"
  mkdir -p "$DATA"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  REPOS="${COMMUNITY_REPOS:-}"
  if [ -z "$REPOS" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-coding/config.env"}}'
    exit 0
  fi
  SEEN="$DATA/seen-advisories.txt"
  touch "$SEEN"
  NEW="[]"
  for REPO in $REPOS; do
    ALERTS=$(curl -sS --max-time 15 -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$REPO/dependabot/alerts?state=open&per_page=100" || echo '[]')
    IDS=$(printf '%s' "$ALERTS" | jq -r '.[].number' 2>/dev/null || true)
    for ID in $IDS; do
      if ! grep -qxF "$REPO#$ID" "$SEEN"; then
        echo "$REPO#$ID" >> "$SEEN"
        NEW=$(printf '%s' "$NEW" | jq -c --arg r "$REPO" --arg i "$ID" '. + [{repo: $r, alert: ($i|tonumber)}]')
      fi
    done
  done
  if [ "$(printf '%s' "$NEW" | jq 'length')" -eq 0 ]; then
    echo '{"wakeAgent": false, "data": {"status": "no-new-advisories"}}'
  else
    printf '{"wakeAgent": true, "data": {"status": "new", "advisories": %s}}\n' "$NEW"
  fi
---
Only invoked when the sweep found advisories you haven't seen before —
`scriptOutput.advisories` lists them. For each: read the actual alert, assess
whether the project is genuinely affected (a vulnerable dependency that isn't
reachable in this codebase is worth a different note than an exploitable one),
and hand your assessment to your lead agent.

Never post advisory detail to a public channel yourself, and never open a public
issue about an unfixed vulnerability. Your lead routes this per its own
escalation rules.
