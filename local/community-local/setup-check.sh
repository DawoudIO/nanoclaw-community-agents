#!/bin/bash
set -uo pipefail
# jq is required by this script itself (every check below is built with it) —
# fail loud and jq-free rather than crashing cryptically on the first `add`
# call. Baseline requirement across all four community templates; request via
# the install_packages self-mod tool if missing (apt: jq).
if ! command -v jq >/dev/null 2>&1; then
  printf '{"status": "incomplete", "checks": [{"name": "jq", "status": "missing", "hint": "jq is required to run this script and by task scripts that parse JSON API responses (e.g. weekly-analytics-report). Request it via the install_packages tool: apt package \"jq\"."}]}\n'
  exit 1
fi
# On-demand mechanical status check. Run when config arrives, and whenever
# asked "what's not set up". Re-verifies live; never answer from memory.
DATA="/workspace/agent/plugin-data/community-local"
[ -f "$DATA/config.env" ] && . "$DATA/config.env"
CHECKS="[]"
add() { CHECKS=$(printf '%s' "$CHECKS" | jq -c --arg n "$1" --arg s "$2" --arg h "$3" '. + [{name:$n,status:$s,hint:$h}]'); }

# For this phase this agent runs on the cloud default (Haiku), same as the
# others — a local-model provider was evaluated and set aside; see
# SKILLS-ADOPTION.md. If you've since adopted one, ANTHROPIC_BASE_URL will be
# set here; that's expected and not checked either way.

[ -n "${COMMUNITY_REPOS:-}" ] && add "config:COMMUNITY_REPOS" "ok" "" || add "config:COMMUNITY_REPOS" "missing" "relay COMMUNITY_REPOS from the lead"
# MIRROR_REPOS is OPTIONAL: repo-mirror-sync falls back to COMMUNITY_REPOS
# when it is unset. Reporting it "missing" flipped the whole check to
# "incomplete" on a correctly-configured install, which trains the owner to
# ignore this report — the opposite of what it is for.
[ -n "${MIRROR_REPOS:-}" ] && add "config:MIRROR_REPOS" "ok" "" || add "config:MIRROR_REPOS" "skipped" "optional — repo-mirror-sync falls back to COMMUNITY_REPOS. Set it only to mirror MORE than the triaged repos (e.g. the wiki)"
[ -n "${CONTENT_REPO:-}" ] && add "config:CONTENT_REPO" "ok" "" || add "config:CONTENT_REPO" "skipped" "optional — draft-cleanup stays paused"
[ -n "${GA4_PROPERTY_ID:-}" ] && add "config:GA4_PROPERTY_ID" "ok" "" || add "config:GA4_PROPERTY_ID" "skipped" "optional — weekly-analytics-report stays paused"
# No PostHog check: posthog-weekly-review moved to the Reviewer
# (engineering/community-coding). Its numbers only matter once someone judges
# whether an anomaly is a real defect, which this tier must not do. GA4 stays
# here because traffic counts are narration, not assessment.

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

# social-metrics-snapshot is the one task here with NO gate script: this agent
# opens the profile pages itself. That needs a real page-reading capability
# (NanoClaw's agent-browser skill, or a built-in fetch), which no curl call
# from inside a bash gate can prove. It moved here with the task — it used to
# live in the marketing template, which no longer owns the task.
add "page_read_capability" "unknown" "open ONE configured social profile URL yourself and confirm you can read the follower count off it. If you cannot read an exact number, social-metrics-snapshot must record null — an estimated follower count is worse than a missing one, because the history ledger is append-only and a wrong entry is permanent."

printf '{"status": %s, "checks": %s}\n' \
  "$(printf '%s' "$CHECKS" | jq 'if any(.[]; .status=="missing" or .status=="unreachable") then "incomplete" else "complete" end')" \
  "$CHECKS"
