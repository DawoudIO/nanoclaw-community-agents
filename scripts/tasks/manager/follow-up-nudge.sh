#!/bin/bash
set -uo pipefail
# Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
#
# FOLLOW-UP NUDGE — weekly. Two kinds of silence that cost the project a
# person, found by one task:
#   PRs    open, non-draft, from outside the maintainer team, untouched for
#          STALE_PR_DAYS — the author is quietly deciding whether to come
#          back. One friendly check-in: still open, here is where it stands,
#          need help? the team is reachable at CHAT_INVITE_URL.
#   issues where the agent posted a fix, recommendation or workaround (it
#          logs those to issue-followups.csv) and the reporter has said
#          nothing for FOLLOWUP_DAYS — did it work? anything else needed?
# Never a review, never a nag: one comment per item per RENUDGE_DAYS,
# recorded locally by the agent, so a lost wake re-surfaces the item and a
# sent one does not. Config: STALE_PR_DAYS (7), FOLLOWUP_DAYS (5),
# RENUDGE_DAYS (30), CHAT_INVITE_URL.
DATA="/workspace/agent/plugin-data/community-manager"
mkdir -p "$DATA"

# --- local telemetry (best-effort; never blocks the gate) -------------------
mkdir -p "$DATA/telemetry" 2>/dev/null || true
exec > >(tee >(sed -u "s/^{/{\"_ts\":\"$(date -u +%FT%TZ)\",/" >> "$DATA/telemetry/follow-up-nudge.jsonl" 2>/dev/null) 2>/dev/null)
# config.env is parsed, never sourced: the model writes into this same
# directory, so a line planted here must stay a string, never become code.
if [ -f "$DATA/config.env" ]; then
  while IFS='=' read -r k v; do
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    export "$k=$v"
  done < <(grep -E '^[A-Z][A-Z0-9_]*=' "$DATA/config.env")
fi
REPOS="${COMMUNITY_REPOS:-}"
if [ -z "$REPOS" ]; then
  echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-manager/config.env"}}'
  exit 0
fi
STALE_DAYS="${STALE_PR_DAYS:-7}";    case "$STALE_DAYS"    in [1-9]|[1-9][0-9]) ;; *) STALE_DAYS=7;; esac
FOLLOWUP_DAYS="${FOLLOWUP_DAYS:-5}"; case "$FOLLOWUP_DAYS" in [1-9]|[1-9][0-9]) ;; *) FOLLOWUP_DAYS=5;; esac
RENUDGE_DAYS="${RENUDGE_DAYS:-30}";  case "$RENUDGE_DAYS"  in [1-9]|[1-9][0-9]|[1-9][0-9][0-9]) ;; *) RENUDGE_DAYS=30;; esac
INVITE="${CHAT_INVITE_URL:-}"

NOW_EPOCH=$(date +%s)
TODAY_D=$(date -u +%Y-%m-%d)
CUTOFF=$(( NOW_EPOCH - STALE_DAYS * 86400 ))
STALE_BEFORE=$(date -u -d "@$CUTOFF" +%Y-%m-%d 2>/dev/null || date -u -r "$CUTOFF" +%Y-%m-%d 2>/dev/null || echo "")
SENT="$DATA/nudged.csv"               # repo,number,nudged_on — appended by the agent after it comments
[ -s "$SENT" ] || echo 'repo,number,nudged_on' > "$SENT"
FOLLOW="$DATA/issue-followups.csv"    # repo,number,posted_on,kind — appended by the agent when it posts a fix/workaround
[ -s "$FOLLOW" ] || echo 'repo,number,posted_on,kind' > "$FOLLOW"
FCUT=$(( NOW_EPOCH - FOLLOWUP_DAYS * 86400 ))
FOLLOW_BEFORE=$(date -u -d "@$FCUT" +%Y-%m-%d 2>/dev/null || date -u -r "$FCUT" +%Y-%m-%d 2>/dev/null || echo "")
RECUT=$(( NOW_EPOCH - RENUDGE_DAYS * 86400 ))
RENUDGE_BEFORE=$(date -u -d "@$RECUT" +%Y-%m-%d 2>/dev/null || date -u -r "$RECUT" +%Y-%m-%d 2>/dev/null || echo "")
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
gh() { curl -fsS --max-time 10 -H "Accept: application/vnd.github+json" "$1" 2>/dev/null; }

i=0; PIDS=()
for REPO in $REPOS; do
  if ! [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    jq -nc --arg r "$REPO" '{repo:$r, ok:false, reason:"bad-config", prs:[]}' > "$TMP/$i.json"; i=$((i+1)); continue
  fi
  (
    # Oldest-untouched first; maintainers' own PRs are filtered by association.
    gh "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:open+draft:false+updated:%3C$STALE_BEFORE&sort=updated&order=asc&per_page=20" > "$TMP/$i.open" &
    gh "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:open+review:changes_requested&per_page=100" > "$TMP/$i.cr" &
    wait
    if ! jq -e '.items' < "$TMP/$i.open" >/dev/null 2>&1; then
      jq -nc --arg r "$REPO" '{repo:$r, ok:false, reason:"fetch-failed", prs:[]}' > "$TMP/$i.json"; exit 0
    fi
    CR=$(jq -c '[.items[]?.number]' < "$TMP/$i.cr" 2>/dev/null || echo '[]'); [ -n "$CR" ] || CR='[]'
    jq -c --arg r "$REPO" --argjson cr "$CR" --argjson now "$NOW_EPOCH" '
      {repo:$r, ok:true, prs: [.items[]
        | select((.author_association // "NONE") | IN("OWNER","MEMBER","COLLABORATOR") | not)
        | select((.user.type // "User") != "Bot")
        | {number, title: (.title[0:120]), author: .user.login, url: .html_url,
           first_time: ((.author_association // "NONE") | IN("FIRST_TIME_CONTRIBUTOR","FIRST_TIMER")),
           changes_requested: (.number | IN($cr[])),
           days_idle: ((($now - ((.updated_at | fromdateiso8601?) // $now)) / 86400) | floor),
           comments}]}' < "$TMP/$i.open" > "$TMP/$i.json" 2>/dev/null \
      || jq -nc --arg r "$REPO" '{repo:$r, ok:false, reason:"json-failed", prs:[]}' > "$TMP/$i.json"
  ) &
  PIDS+=("$!"); i=$((i+1))
done
wait "${PIDS[@]}"

# Issues we answered with a fix/workaround FOLLOWUP_DAYS+ ago: has anyone
# spoken since? Open issues only; a closed one answered itself. Capped so a
# busy week cannot turn into a comment flood.
ISSUES='[]'; IFAIL='[]'
while IFS=, read -r R N POSTED KIND; do
  [ -z "$R" ] || [ -z "$N" ] || [ "$R" = "repo" ] && continue
  [[ "$R" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && [[ "$N" =~ ^[0-9]+$ ]] || continue
  [ -n "$FOLLOW_BEFORE" ] && [ "$POSTED" \> "$FOLLOW_BEFORE" ] && continue
  [ "$(printf '%s' "$ISSUES" | jq 'length')" -ge 10 ] && break
  if ! gh "https://api.github.com/repos/$R/issues/$N" > "$TMP/iss.tmp"; then
    IFAIL=$(jq -c --arg r "$R" --argjson n "$N" '. + [{repo:$r, number:$n}]' <<< "$IFAIL"); continue
  fi
  STATE=$(jq -r '.state // ""' < "$TMP/iss.tmp"); [ "$STATE" = "open" ] || continue
  LAST_HUMAN=$(gh "https://api.github.com/repos/$R/issues/$N/comments?per_page=100" | jq -r --arg bot "${GITHUB_BOT_USERNAME:-}" \
    '[.[] | select((.user.type // "User") != "Bot") | select(($bot == "") or ((.user.login | ascii_downcase) != ($bot | ascii_downcase)))] | (last.created_at // "")' 2>/dev/null)
  [ -n "$LAST_HUMAN" ] && [ "${LAST_HUMAN:0:10}" \> "$POSTED" ] && continue   # someone replied after us: first-response handles it
  ISSUES=$(jq -c --arg r "$R" --argjson n "$N" --arg p "$POSTED" --arg k "$KIND" \
    --argjson t "$(jq -c '{title: (.title[0:120]), author: .user.login, url: .html_url}' < "$TMP/iss.tmp")" \
    '. + [{repo:$r, number:$n, posted_on:$p, kind:$k} + $t]' <<< "$ISSUES")
done < "$FOLLOW"

ALL=$(cat "$TMP"/*.json 2>/dev/null | jq -c -s '.' 2>/dev/null || echo '[]')
if [ "$(printf '%s' "$ALL" | jq 'length' 2>/dev/null || echo 0)" -eq 0 ]; then
  echo '{"wakeAgent": true, "data": {"status": "fetch-failed", "hint": "no repo produced a result — check the token and the sandbox network policy"}}'
  exit 0
fi
# Drop PRs nudged within the re-nudge window. The agent appends to pr-nudged.csv
# after it comments; the gate never writes that file itself.
RECENT=$(awk -F, -v cut="$RENUDGE_BEFORE" 'NR>1 && $3 >= cut {print $1"#"$2}' "$SENT" | jq -R . | jq -sc .)
PRS=$(printf '%s' "$ALL" | jq -c --argjson recent "$RECENT" '[.[] | select(.ok) | .repo as $r | .prs[] | . + {repo:$r} | select((($r + "#" + (.number|tostring)) | IN($recent[])) | not)] | .[0:10]')
ISSUES=$(printf '%s' "$ISSUES" | jq -c --argjson recent "$RECENT" '[.[] | select(((.repo + "#" + (.number|tostring)) | IN($recent[])) | not)]')
DEGRADED=$(printf '%s' "$ALL" | jq -c --argjson f "$IFAIL" '[.[] | select(.ok | not) | {repo, reason}] + [$f[] | . + {reason:"fetch-failed"}]')

N_PR=$(printf '%s' "$PRS" | jq 'length'); N_IS=$(printf '%s' "$ISSUES" | jq 'length'); N_DG=$(printf '%s' "$DEGRADED" | jq 'length')
WAKE=false
[ $(( N_PR + N_IS )) -gt 0 ] && WAKE=true
[ "$N_DG" -gt 0 ] && WAKE=true   # a broken fetch must never read as "nothing to follow up"
STATUS=quiet
[ $(( N_PR + N_IS )) -gt 0 ] && STATUS=follow-ups
[ $(( N_PR + N_IS )) -eq 0 ] && [ "$N_DG" -gt 0 ] && STATUS=fetch-failed
jq -nc --argjson w "$WAKE" --arg s "$STATUS" --arg d "$TODAY_D" --argjson sd "$STALE_DAYS" --argjson fd "$FOLLOWUP_DAYS" --argjson rd "$RENUDGE_DAYS" --arg inv "$INVITE" \
  --argjson p "$PRS" --argjson is "$ISSUES" --argjson dg "$DEGRADED" \
  '{wakeAgent:$w, data:{status:$s, date:$d, stale_pr_days:$sd, followup_days:$fd, renudge_days:$rd, chat_invite:(if $inv == "" then null else $inv end), prs:$p, issues:$is, degraded:$dg}}'
