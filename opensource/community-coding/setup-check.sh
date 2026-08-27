#!/bin/bash
set -uo pipefail
# jq is required by this script itself (every check below is built with it) —
# fail loud and jq-free rather than crashing cryptically on the first `add`
# call. Baseline requirement across all four community templates; request via
# the install_packages self-mod tool if missing (apt: jq).
if ! command -v jq >/dev/null 2>&1; then
  printf '{"status": "incomplete", "checks": [{"name": "jq", "status": "missing", "hint": "jq is required to run this script and by task scripts that parse JSON API responses. Request it via the install_packages tool: apt package \"jq\"."}]}\n'
  exit 1
fi
# On-demand, mechanical setup status check — run this (via Bash) whenever the
# owner asks "what's not set up" or "resume onboarding". Re-verifies live,
# every time; never answer from memory.
DATA="/workspace/agent/plugin-data/community-coding"
[ -f "$DATA/config.env" ] && . "$DATA/config.env"
CHECKS="[]"
add() { CHECKS=$(printf '%s' "$CHECKS" | jq -c --arg n "$1" --arg s "$2" --arg h "$3" '. + [{name:$n,status:$s,hint:$h}]'); }

if [ -z "${COMMUNITY_REPOS:-}" ]; then
  add "community_repos_configured" "missing" "set COMMUNITY_REPOS in config.env, or ask the lead to relay it from onboarding"
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

IDENT=$(curl -s -H "Accept: application/vnd.github+json" https://api.github.com/user | jq -r '.login // empty')
if [ -z "$IDENT" ]; then
  add "identity_check" "unreachable" "GET /user failed — token not wired"
elif [ -n "${GITHUB_BOT_USERNAME:-}" ] && [ "$IDENT" != "$GITHUB_BOT_USERNAME" ]; then
  add "identity_check" "mismatch" "token resolves to '$IDENT', expected '$GITHUB_BOT_USERNAME' — hold all GitHub-facing work until the lead confirms this"
else
  add "identity_check" "ok" ""
fi

printf '{"status": %s, "checks": %s}\n' \
  "$(printf '%s' "$CHECKS" | jq 'if any(.[]; .status=="missing" or .status=="unreachable" or .status=="mismatch") then "incomplete" else "complete" end')" \
  "$CHECKS"
