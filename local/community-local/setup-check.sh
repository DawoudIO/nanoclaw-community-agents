#!/bin/bash
set -uo pipefail
# On-demand mechanical status check. Run when config arrives, and whenever
# asked "what's not set up". Re-verifies live; never answer from memory.
DATA="/workspace/agent/plugin-data/community-local"
[ -f "$DATA/config.env" ] && . "$DATA/config.env"
CHECKS="[]"
add() { CHECKS=$(printf '%s' "$CHECKS" | jq -c --arg n "$1" --arg s "$2" --arg h "$3" '. + [{name:$n,status:$s,hint:$h}]'); }

# The defining property of this agent: it must not depend on the cloud window.
if [ -n "${ANTHROPIC_BASE_URL:-}" ]; then
  add "local_provider_active" "ok" "routed to $ANTHROPIC_BASE_URL"
else
  add "local_provider_active" "missing" "ANTHROPIC_BASE_URL is unset — this group is still on the CLOUD provider, so it shares the usage window and defeats its own purpose. Re-run /add-ollama-provider for this group."
fi

for k in COMMUNITY_REPOS MIRROR_REPOS; do
  eval "v=\${$k:-}"
  [ -n "$v" ] && add "config:$k" "ok" "" || add "config:$k" "missing" "relay $k from the lead"
done
[ -n "${CONTENT_REPO:-}" ] && add "config:CONTENT_REPO" "ok" "" || add "config:CONTENT_REPO" "skipped" "optional — draft-cleanup stays paused"
[ -n "${GA4_PROPERTY_ID:-}" ] && add "config:GA4_PROPERTY_ID" "ok" "" || add "config:GA4_PROPERTY_ID" "skipped" "optional — weekly-analytics-report stays paused"
[ -n "${POSTHOG_PROJECT_ID:-}" ] && add "config:POSTHOG_PROJECT_ID" "ok" "" || add "config:POSTHOG_PROJECT_ID" "skipped" "optional — posthog-weekly-review stays paused"

if [ -n "${COMMUNITY_REPOS:-}" ]; then
  for REPO in $COMMUNITY_REPOS; do
    CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$REPO" 2>/dev/null || echo 000)
    case "$CODE" in
      200) add "repo_read:$REPO" "ok" "";;
      *) add "repo_read:$REPO" "unreachable" "$REPO: HTTP $CODE (401/403 = token, 404 = name, 502 = sandbox policy)";;
    esac
  done
fi

add "message_visibility" "unknown" "unanswered-watch depends on 'ncl messages list --json' — run it once by hand and confirm the shape, or the acknowledger fails silent"

printf '{"status": %s, "checks": %s}\n' \
  "$(printf '%s' "$CHECKS" | jq 'if any(.[]; .status=="missing" or .status=="unreachable") then "incomplete" else "complete" end')" \
  "$CHECKS"
