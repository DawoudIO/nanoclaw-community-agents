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
# On-demand, mechanical setup status check for the LEAD's own config — run
# whenever the owner asks "what's not set up". This checks only what a
# script can verify; Discord wiring, sub-agent stamping, and the owner-DM
# round trip are NOT curl-testable and stay on the ready gate (CHECKPOINTS.md)
# for a human/agent to confirm conversationally.
DATA="/workspace/agent/plugin-data/community-support"
[ -f "$DATA/config.env" ] && . "$DATA/config.env"
CHECKS="[]"
add() { CHECKS=$(printf '%s' "$CHECKS" | jq -c --arg n "$1" --arg s "$2" --arg h "$3" '. + [{name:$n,status:$s,hint:$h}]'); }

if [ -z "${COMMUNITY_REPOS:-}" ]; then
  add "community_repos_configured" "missing" "set COMMUNITY_REPOS in config.env — needed for triage/release-watch even in standalone mode"
else
  for REPO in $COMMUNITY_REPOS; do
    CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$REPO")
    case "$CODE" in
      200) add "repo_access:$REPO" "ok" "";;
      *) add "repo_access:$REPO" "unreachable" "$REPO: HTTP $CODE (401/403 = token, 404 = name, 502 = sandbox policy)";;
    esac
  done
fi

IDENT=$(curl -s -H "Accept: application/vnd.github+json" https://api.github.com/user | jq -r '.login // empty')
if [ -z "$IDENT" ]; then
  add "identity_check" "unreachable" "GET /user failed — lead's GitHub token not wired"
elif [ -n "${GITHUB_BOT_USERNAME:-}" ] && [ "$IDENT" != "$GITHUB_BOT_USERNAME" ]; then
  add "identity_check" "mismatch" "token resolves to '$IDENT', expected '$GITHUB_BOT_USERNAME'"
else
  add "identity_check" "ok" ""
fi

if [ -d "/workspace/agent/.git" ]; then
  if git -C /workspace/agent remote get-url origin >/dev/null 2>&1; then
    add "workspace_backup_configured" "ok" ""
  else
    add "workspace_backup_configured" "missing" "git repo exists but no 'origin' remote — see README, Workspace backup setup"
  fi
else
  add "workspace_backup_configured" "missing" "no git repo in workspace yet — optional, but the follower-count series has nowhere durable to live without it"
fi

for k in github_bot_username security_contact escalation_backstop docs_style; do
  if grep -q "^$k" "$DATA/project-config.md" 2>/dev/null; then
    add "config:$k" "ok" ""
  else
    add "config:$k" "missing" "not found in project-config.md — ask the owner this welcome-interview question again"
  fi
done

add "discord_wiring" "unknown" "not curl-testable from here — confirm with a live DM round trip (CHECKPOINTS.md, ready gate #1)"
add "subagents_stamped" "unknown" "check via 'ncl groups list' or ask each sub-agent to run its own setup-check.sh"

printf '{"status": %s, "checks": %s}\n' \
  "$(printf '%s' "$CHECKS" | jq 'if any(.[]; .status=="missing" or .status=="unreachable" or .status=="mismatch") then "incomplete" else "complete" end')" \
  "$CHECKS"
