#!/bin/bash
set -uo pipefail
# jq is required by this script itself (every check below is built with it) —
# fail loud and jq-free rather than crashing cryptically on the first `add`
# call. Baseline requirement across both community templates; request via
# the install_packages self-mod tool if missing (apt: jq).
if ! command -v jq >/dev/null 2>&1; then
  printf '{"status": "incomplete", "checks": [{"name": "jq", "status": "missing", "hint": "jq is required to run this script and by task scripts that parse JSON API responses. Request it via the install_packages tool: apt package \"jq\"."}]}\n'
  exit 1
fi
# On-demand, mechanical setup status check — run this (via Bash) whenever the
# owner asks "what's not set up" or "resume onboarding". Re-verifies live,
# every time; never answer from memory.
DATA="/workspace/agent/plugin-data/community-helper"
[ -f "$DATA/config.env" ] && . "$DATA/config.env"
CHECKS="[]"
add() { CHECKS=$(printf '%s' "$CHECKS" | jq -c --arg n "$1" --arg s "$2" --arg h "$3" '. + [{name:$n,status:$s,hint:$h}]'); }

if [ -z "${COMMUNITY_REPOS:-}" ]; then
  add "community_repos_configured" "missing" "set COMMUNITY_REPOS in config.env, or ask the manager to relay it from onboarding"
else
  for REPO in $COMMUNITY_REPOS; do
    CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$REPO")
    case "$CODE" in
      200) add "repo_access:$REPO" "ok" "";;
      401|403) add "repo_access:$REPO" "unreachable" "$REPO: token not wired or lacks access";;
      404) add "repo_access:$REPO" "unreachable" "$REPO: 404 — name wrong or token has no access";;
      *) add "repo_access:$REPO" "unreachable" "$REPO: unexpected HTTP $CODE (502 = sandbox network policy)";;
    esac
  done
fi

# The ledger repo is where project-health's ledger step commits the history series.
# Reported "skipped" rather than "missing" because every other task here works
# without it — but the hint states the real consequence, because the cost is
# not "a paused task", it is losing series that cannot be rebuilt once this
# container is replaced.
if [ -z "${LEDGER_REPO:-}" ]; then
  add "config:LEDGER_REPO" "skipped" "optional but strongly recommended — without it project-health cannot publish, so the dev-metrics, traffic and follower series stay container-local and are lost at the next rebuild. Follower counts cannot be re-read retroactively from any platform."
else
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$LEDGER_REPO")
  case "$CODE" in
    200) add "ledger_repo_access" "ok" "";;
    401|403) add "ledger_repo_access" "unreachable" "$LEDGER_REPO: token not wired or lacks access (401/403). project-health also needs a github.com (git) PUSH credential, which this REST check cannot verify — confirm that by running the task once.";;
    404) add "ledger_repo_access" "unreachable" "$LEDGER_REPO: 404 — repo name wrong, or the token has no access to it";;
    *) add "ledger_repo_access" "unreachable" "$LEDGER_REPO: unexpected HTTP $CODE (502 = sandbox network policy)";;
  esac
fi

[ -n "${GA4_PROPERTIES:-}${GA4_PROPERTY_ID:-}" ] \
  && add "config:GA4_PROPERTIES" "ok" "" \
  || add "config:GA4_PROPERTIES" "skipped" "optional — project-health skips its traffic section. GA4_PROPERTIES takes one or more properties (id[,label:id...]); GA4_PROPERTY_ID (single bare id) still works too"

# project-health's social half has no gate: on collect days the agent
# opens the profile pages itself (SOCIAL_DAILY=false skips it). That needs a real page-reading capability
# (NanoClaw's agent-browser skill, or a built-in fetch), which no curl call
# from inside a bash gate can prove.
add "page_read_capability" "unknown" "open ONE configured social profile URL yourself and confirm you can read the follower count off it. If you cannot read an exact number, project-health must record null — an estimated follower count is worse than a missing one, because the history is append-only and a wrong entry is permanent."

IDENT=$(curl -s -H "Accept: application/vnd.github+json" https://api.github.com/user | jq -r '.login // empty')
if [ -z "$IDENT" ]; then
  add "identity_check" "unreachable" "GET /user failed — token not wired"
elif [ -n "${GITHUB_BOT_USERNAME:-}" ] && [ "$IDENT" != "$GITHUB_BOT_USERNAME" ]; then
  add "identity_check" "mismatch" "token resolves to '$IDENT', expected '$GITHUB_BOT_USERNAME' — hold all GitHub-facing work until the manager confirms this"
else
  add "identity_check" "ok" ""
fi

printf '{"status": %s, "checks": %s}\n' \
  "$(printf '%s' "$CHECKS" | jq 'if any(.[]; .status=="missing" or .status=="unreachable" or .status=="mismatch") then "incomplete" else "complete" end')" \
  "$CHECKS"
