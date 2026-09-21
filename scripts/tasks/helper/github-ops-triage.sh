#!/bin/bash
set -euo pipefail
# Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
# Gate: fetch the delta since last run; wake the model only if there is one.
# The cursor advances ONLY on a fully successful fetch — a failed or
# unauthorized fetch must never silently swallow a window of updates.
DATA="/workspace/agent/plugin-data/community-helper"
mkdir -p "$DATA"

# --- local telemetry (best-effort; never blocks the gate) -------------------
# Mirrors this gate's one-line JSON output to a local per-task log so the
# owner can review wake/error patterns weekly and adjust gates or budgets.
# Not published anywhere (unlike project-health's series) and not a source
# of truth -- a background pipe means a very fast exit can occasionally drop
# the last line, an accepted trade for never risking the gate's real output
# or exit code.
mkdir -p "$DATA/telemetry" 2>/dev/null || true
exec > >(tee >(sed -u "s/^{/{\"_ts\":\"$(date -u +%FT%TZ)\",/" >> "$DATA/telemetry/github-ops-triage.jsonl" 2>/dev/null) 2>/dev/null)
if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
REPOS="${COMMUNITY_REPOS:-}"
if [ -z "$REPOS" ]; then
  echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-helper/config.env"}}'
  exit 0
fi
SINCE_F="$DATA/triage-last-run"
SINCE=$(cat "$SINCE_F" 2>/dev/null || echo "")
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ITEMS="[]"; FAILED=""; TRUNC=""
for REPO in $REPOS; do
  URL="https://api.github.com/repos/$REPO/issues?state=open&sort=updated&direction=desc&per_page=50"
  if [ -n "$SINCE" ]; then URL="$URL&since=$SINCE"; fi
  RESP=$(curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" "$URL") || { FAILED="$FAILED $REPO"; continue; }
  BATCH=$(printf '%s' "$RESP" | jq -c 'if type=="array" then [.[] | {number, title: (.title[0:120]), is_pr: (has("pull_request")), updated_at, labels: [.labels[].name]}] else null end' 2>/dev/null || echo null)
  if [ "$BATCH" = "null" ]; then FAILED="$FAILED $REPO"; continue; fi
  BATCH=$(printf '%s' "$BATCH" | jq -c --arg r "$REPO" 'map(. + {repo: $r})')
  if [ "$(printf '%s' "$BATCH" | jq 'length')" -eq 50 ]; then TRUNC="$TRUNC $REPO"; fi
  ITEMS=$(jq -c -n --argjson a "$ITEMS" --argjson b "$BATCH" '$a + $b')
done
if [ -n "$FAILED" ]; then
  printf '{"wakeAgent": true, "data": {"status": "fetch-failed", "failed_repos": "%s", "items": %s}}\n' "${FAILED# }" "$ITEMS"
  exit 0
fi
echo "$NOW" > "$SINCE_F"
if [ "$(printf '%s' "$ITEMS" | jq 'length')" -eq 0 ]; then
  echo '{"wakeAgent": false, "data": {"status": "quiet"}}'
else
  printf '{"wakeAgent": true, "data": {"since": "%s", "truncated_repos": "%s", "items": %s}}\n' "${SINCE:-first-run}" "${TRUNC# }" "$ITEMS"
fi
