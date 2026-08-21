#!/bin/bash
set -euo pipefail
# Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy — no token
# in this file, no `gh` CLI (it refuses to run without local auth config,
# which containers deliberately don't have).
# Failure design: an HTTP error (incl. 403 = fine-grained token missing the
# Dependabot alerts read permission) WAKES the agent as fetch-failed — it
# must never read as "no new advisories". And the script never marks
# alerts seen: the AGENT acks them after handing off, so a lost wake
# re-surfaces the alert next run.
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
NEW="[]"; FAILED=""
for REPO in $REPOS; do
  ALERTS=$(curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/dependabot/alerts?state=open&per_page=100") || { FAILED="$FAILED $REPO"; continue; }
  IDS=$(printf '%s' "$ALERTS" | jq -r 'if type=="array" then .[].number else empty end' 2>/dev/null || true)
  for ID in $IDS; do
    if ! grep -qxF "$REPO#$ID" "$SEEN"; then
      NEW=$(printf '%s' "$NEW" | jq -c --arg r "$REPO" --arg i "$ID" '. + [{repo: $r, alert: ($i|tonumber)}]')
    fi
  done
done
if [ -n "$FAILED" ]; then
  printf '{"wakeAgent": true, "data": {"status": "fetch-failed", "failed_repos": "%s", "hint": "403 usually means the fine-grained token is missing the Dependabot alerts (read) permission", "new": %s}}\n' "${FAILED# }" "$NEW"
  exit 0
fi
if [ "$(printf '%s' "$NEW" | jq 'length')" -eq 0 ]; then
  echo '{"wakeAgent": false, "data": {"status": "no-new-advisories"}}'
else
  printf '{"wakeAgent": true, "data": {"status": "new", "advisories": %s}}\n' "$NEW"
fi
