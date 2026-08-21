#!/bin/bash
set -uo pipefail
# On-demand, mechanical setup status check — run this (via Bash) whenever the
# owner asks "what's not set up" or "resume onboarding". Never guess status
# by memory; this script re-verifies live, every time. Output is one JSON
# object; no field here requires agent judgment to produce.
DATA="/workspace/agent/plugin-data/community-marketing"
[ -f "$DATA/config.env" ] && . "$DATA/config.env"
CHECKS="[]"
add() { CHECKS=$(printf '%s' "$CHECKS" | jq -c --arg n "$1" --arg s "$2" --arg h "$3" '. + [{name:$n,status:$s,hint:$h}]'); }

if [ -z "${CONTENT_REPO:-}" ]; then
  add "content_repo_configured" "missing" "set CONTENT_REPO in config.env, or ask the lead to relay it from onboarding"
else
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$CONTENT_REPO")
  case "$CODE" in
    200) add "content_repo_access" "ok" "";;
    401|403) add "content_repo_access" "unreachable" "$CONTENT_REPO: token not wired or lacks access (401/403)";;
    404) add "content_repo_access" "unreachable" "$CONTENT_REPO: 404 — repo name wrong, or token has no access to it";;
    *) add "content_repo_access" "unreachable" "$CONTENT_REPO: unexpected HTTP $CODE (502 = sandbox network policy)";;
  esac
fi

if [ -n "${BRAND_SOURCE_REPO:-}" ] && [ "${BRAND_SOURCE_REPO:-}" != "${CONTENT_REPO:-}" ]; then
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$BRAND_SOURCE_REPO")
  case "$CODE" in
    200) add "brand_source_access" "ok" "";;
    401|403|404) add "brand_source_access" "unreachable" "$BRAND_SOURCE_REPO is a different repo from CONTENT_REPO — the marketing PAT is fine-grained and single-repo by default. Recreate it including BOTH repos in its repository access list.";;
    *) add "brand_source_access" "unreachable" "$BRAND_SOURCE_REPO: unexpected HTTP $CODE";;
  esac
elif [ -z "${BRAND_SOURCE_REPO:-}" ]; then
  add "brand_source_configured" "unknown" "BRAND_SOURCE_REPO not set — if the brand/strategy doc lives outside CONTENT_REPO, set it so this check can verify access"
fi

if [ -n "${RELEASE_WATCH_REPO:-}" ]; then
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$RELEASE_WATCH_REPO/releases/latest")
  case "$CODE" in
    200|404) add "release_watch_repo_access" "ok" "";; # 404 = no releases yet, not a permission problem
    401|403) add "release_watch_repo_access" "unreachable" "$RELEASE_WATCH_REPO: the marketing PAT can't reach it. Fine-grained PATs are repo-scoped even for public data — RELEASE_WATCH_REPO must be added to this token's repository access list alongside CONTENT_REPO, or content-draft-cycle's release trigger will silently never fire.";;
    *) add "release_watch_repo_access" "unreachable" "$RELEASE_WATCH_REPO: unexpected HTTP $CODE";;
  esac
fi

IDENT=$(curl -s -H "Accept: application/vnd.github+json" https://api.github.com/user | jq -r '.login // empty')
if [ -z "$IDENT" ]; then
  add "identity_check" "unreachable" "GET /user failed — token not wired"
elif [ -n "${GITHUB_BOT_USERNAME:-}" ] && [ "$IDENT" != "$GITHUB_BOT_USERNAME" ]; then
  add "identity_check" "mismatch" "token resolves to '$IDENT', expected '$GITHUB_BOT_USERNAME' — hold all GitHub-facing work until the lead confirms this"
else
  add "identity_check" "ok" ""
fi

if [ -n "${GA4_PROPERTY_ID:-}" ]; then
  add "ga4_configured" "ok" ""
else
  add "ga4_configured" "skipped" "optional — GA4_PROPERTY_ID unset, weekly-analytics-report stays paused"
fi

# agent-browser: social-metrics-snapshot needs a page-reading capability
# (Claude's built-in web fetch, or NanoClaw's agent-browser skill). No API
# call proves this from inside a bash gate — the agent itself must confirm
# it can actually open a URL and read content before trusting this task.
add "page_read_capability" "unknown" "run one real fetch of a configured social profile URL yourself and confirm you can read it — this is not curl-testable"

printf '{"status": %s, "checks": %s}\n' \
  "$(printf '%s' "$CHECKS" | jq 'if any(.[]; .status=="missing" or .status=="unreachable") then "incomplete" else "complete" end')" \
  "$CHECKS"
