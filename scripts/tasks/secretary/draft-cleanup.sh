#!/bin/bash
set -euo pipefail
# Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
# A ledger keyed on number:updated_at means each stale PR is reported once
# per state — not re-nagged daily until a human acts.
DATA="/workspace/agent/plugin-data/community-secretary"
mkdir -p "$DATA"
if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
REPO="${CONTENT_REPO:-}"
if [ -z "$REPO" ]; then
  echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set CONTENT_REPO in plugin-data/community-secretary/config.env"}}'
  exit 0
fi
PRS=$(curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/pulls?state=open&per_page=100") || {
  echo '{"wakeAgent": true, "data": {"status": "fetch-failed", "hint": "401/403 = token wiring; 502 = sandbox network policy"}}'
  exit 0
}
CUTOFF=$(( $(date +%s) - 604800 ))
STALE=$(printf '%s' "$PRS" | jq -c --argjson c "$CUTOFF" \
  'if type=="array" then [.[] | select((.updated_at | fromdateiso8601) < $c) | {number, title, updated_at}] else null end' 2>/dev/null || echo null)
if [ "$STALE" = "null" ]; then
  echo '{"wakeAgent": true, "data": {"status": "fetch-failed", "hint": "unexpected API response shape"}}'
  exit 0
fi
LEDGER="$DATA/stale-drafts-seen.txt"
touch "$LEDGER"
NEWSTALE="[]"
while IFS= read -r ROW; do
  [ -z "$ROW" ] && continue
  KEY=$(printf '%s' "$ROW" | jq -r '"\(.number):\(.updated_at)"')
  if ! grep -qxF "$KEY" "$LEDGER"; then
    echo "$KEY" >> "$LEDGER"
    NEWSTALE=$(jq -c -n --argjson a "$NEWSTALE" --argjson b "$ROW" '$a + [$b]')
  fi
done <<EOF_ROWS
$(printf '%s' "$STALE" | jq -c '.[]' 2>/dev/null || true)
EOF_ROWS
TOTAL=$(printf '%s' "$STALE" | jq 'length')
if [ "$(printf '%s' "$NEWSTALE" | jq 'length')" -eq 0 ]; then
  printf '{"wakeAgent": false, "data": {"status": "no-new-stale", "still_open_stale": %s}}\n' "$TOTAL"
else
  printf '{"wakeAgent": true, "data": {"status": "stale", "new": %s, "total_stale_open": %s}}\n' "$NEWSTALE" "$TOTAL"
fi
