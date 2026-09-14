#!/bin/bash
set -uo pipefail
# jq is required by this script itself (every check below is built with it) —
# fail loud and jq-free rather than crashing cryptically on the first `add`
# call. Baseline requirement across all three community templates; request via
# the install_packages self-mod tool if missing (apt: jq).
if ! command -v jq >/dev/null 2>&1; then
  printf '{"status": "incomplete", "checks": [{"name": "jq", "status": "missing", "hint": "jq is required to run this script and by task scripts that parse JSON API responses. Request it via the install_packages tool: apt package \"jq\"."}]}\n'
  exit 1
fi
# On-demand, mechanical setup status check — run this (via Bash) whenever the
# owner asks "what's not set up" or "resume onboarding". Never guess status
# by memory; this script re-verifies live, every time. Output is one JSON
# object; no field here requires agent judgment to produce.
DATA="/workspace/agent/plugin-data/community-marketing"
[ -f "$DATA/config.env" ] && . "$DATA/config.env"
CHECKS="[]"
add() { CHECKS=$(printf '%s' "$CHECKS" | jq -c --arg n "$1" --arg s "$2" --arg h "$3" '. + [{name:$n,status:$s,hint:$h}]'); }

# The marketing repo is where ledger-publish commits the history series. It is
# reported "skipped" rather than "missing" because every other task here works
# without it — but the hint states the real consequence, because the cost of
# leaving it unset is not "a paused task", it is losing a series that cannot
# be rebuilt after this container is replaced.
LEDGER_TARGET="${LEDGER_REPO:-${MARKETING_REPO:-}}"
if [ -z "$LEDGER_TARGET" ]; then
  add "config:MARKETING_REPO" "skipped" "optional but strongly recommended — without it ledger-publish cannot run, so the follower and traffic series stay container-local and are lost at the next rebuild. Follower counts cannot be re-read retroactively from any platform."
else
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$LEDGER_TARGET")
  case "$CODE" in
    200) add "ledger_repo_access" "ok" "";;
    401|403) add "ledger_repo_access" "unreachable" "$LEDGER_TARGET: token not wired or lacks access (401/403). ledger-publish also needs a github.com (git) PUSH credential, which this REST check cannot verify — confirm that by running the task once.";;
    404) add "ledger_repo_access" "unreachable" "$LEDGER_TARGET: 404 — repo name wrong, or the token has no access to it";;
    *) add "ledger_repo_access" "unreachable" "$LEDGER_TARGET: unexpected HTTP $CODE (502 = sandbox network policy)";;
  esac
fi

[ -n "${GA4_PROPERTIES:-}${GA4_PROPERTY_ID:-}" ] \
  && add "config:GA4_PROPERTIES" "ok" "" \
  || add "config:GA4_PROPERTIES" "skipped" "optional — weekly-analytics-report stays paused. GA4_PROPERTIES takes one or more properties (id[,label:id...]); GA4_PROPERTY_ID (single bare id) still works too"

IDENT=$(curl -s -H "Accept: application/vnd.github+json" https://api.github.com/user | jq -r '.login // empty')
if [ -z "$IDENT" ]; then
  add "identity_check" "unreachable" "GET /user failed — token not wired"
elif [ -n "${GITHUB_BOT_USERNAME:-}" ] && [ "$IDENT" != "$GITHUB_BOT_USERNAME" ]; then
  add "identity_check" "mismatch" "token resolves to '$IDENT', expected '$GITHUB_BOT_USERNAME' — hold all GitHub-facing work until the lead confirms this"
else
  add "identity_check" "ok" ""
fi

# social-metrics-snapshot is the one task here with NO gate script: the agent
# opens the profile pages itself. That needs a real page-reading capability
# (NanoClaw's agent-browser skill, or a built-in fetch), which no curl call
# from inside a bash gate can prove.
add "page_read_capability" "unknown" "open ONE configured social profile URL yourself and confirm you can read the follower count off it. If you cannot read an exact number, social-metrics-snapshot must record null — an estimated follower count is worse than a missing one, because the history is append-only and a wrong entry is permanent."

printf '{"status": %s, "checks": %s}\n' \
  "$(printf '%s' "$CHECKS" | jq 'if any(.[]; .status=="missing" or .status=="unreachable") then "incomplete" else "complete" end')" \
  "$CHECKS"
