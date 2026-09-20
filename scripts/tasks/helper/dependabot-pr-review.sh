#!/bin/bash
set -uo pipefail
# Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
#
# Review Dependabot's open pull requests. This is deliberately separate from
# security-advisory-sweep, because they take different inputs and produce
# different deliverables — keep them apart:
#
#   security-advisory-sweep  — input: ALERTS. "Are we affected, and if nobody
#                              else is fixing it, draft the bump."
#   dependabot-pr-review     — input: PULL REQUESTS. "Dependabot proposed a
#                              version change; what does it actually cost us?"
#
# The review half matters more often: Dependabot tells you a version changed
# and says nothing about what it means in this codebase. A major bump inside a
# security PR is a breaking change wearing a security label, and that is why
# these sit unmerged.
#
# Re-review on force-push: Dependabot rebases its branches constantly. The
# ledger key is PR number + head SHA, so a rebased or retargeted PR comes back
# for review instead of being remembered as done.
DATA="/workspace/agent/plugin-data/community-helper"
mkdir -p "$DATA"

# --- local telemetry (best-effort; never blocks the gate) -------------------
# Mirrors this gate's one-line JSON output to a local per-task log so the
# owner can review wake/error patterns weekly and adjust gates or budgets.
# Not published anywhere (unlike ledger-publish's series) and not a source
# of truth -- a background pipe means a very fast exit can occasionally drop
# the last line, an accepted trade for never risking the gate's real output
# or exit code.
mkdir -p "$DATA/telemetry" 2>/dev/null || true
exec > >(tee >(sed -u "s/^{/{\"_ts\":\"$(date -u +%FT%TZ)\",/" >> "$DATA/telemetry/dependabot-pr-review.jsonl" 2>/dev/null) 2>/dev/null)
if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
REPOS="${COMMUNITY_REPOS:-}"
if [ -z "$REPOS" ]; then
  echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-helper/config.env"}}'
  exit 0
fi
MAX_PER_RUN="${DEPENDABOT_REVIEW_MAX:-8}"
case "$MAX_PER_RUN" in ''|*[!0-9]*) MAX_PER_RUN=8;; esac

SEEN="$DATA/dependabot-reviewed.txt"
touch "$SEEN"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
i=0
PIDS=()   # deadlock fix: exec > >(tee ...) puts a background subshell in this shell's
# own job table, so a BARE 'wait' below would also wait on it -- and it
# cannot exit until this script's stdout closes, which cannot happen until
# the script exits, which is blocked on that same wait. Track only the
# per-repo PIDs and wait on those explicitly.
for REPO in $REPOS; do
  (
    curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$REPO/pulls?state=open&per_page=100" \
      > "$TMP/$i.pulls" 2>/dev/null
    # Security alerts, purely to mark which PRs are security-backed. A failure
    # here is not fatal: an unreviewed version bump is still worth reviewing,
    # it just loses its severity label.
    curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$REPO/dependabot/alerts?state=open&per_page=100" \
      > "$TMP/$i.alerts" 2>/dev/null || true

    ALERTS=$(jq -c 'if type=="array" then
        [ .[] | {package: (.security_vulnerability.package.name // null),
                 severity: ((.security_advisory.severity // "unknown") | ascii_downcase),
                 ghsa_id: (.security_advisory.ghsa_id // null),
                 scope: (.dependency.scope // null)} ]
      else [] end' < "$TMP/$i.alerts" 2>/dev/null || echo '[]')
    [ -z "$ALERTS" ] && ALERTS='[]'

    OUT=$(jq -c --arg r "$REPO" --argjson al "$ALERTS" 'if type=="array" then
        [ .[]
          | select((.user.login // "") | test("^dependabot(\\[bot\\])?$"))
          | {repo: $r, number, title, url: .html_url, draft,
             head_sha: (.head.sha // ""),
             base: (.base.ref // null),
             created_at, updated_at,
             package: ((.title | capture("(?i)bump (?<p>[^ ]+) from") | .p) // null),
             from_version: ((.title | capture("(?i) from (?<v>[^ ]+) to ") | .v) // null),
             to_version: ((.title | capture("(?i) to (?<v>[^ ]+)$") | .v) // null)}
          | . as $pr
          | .alert = ( [ $al[]
              | select(($pr.package // "") != "" and (.package // "") != "")
              | select((.package | ascii_downcase) == ($pr.package | ascii_downcase)) ] | first // null)
          | .security_backed = (.alert != null)
          | .severity = (.alert.severity // null)
          | .bump = ( ((.from_version // "") | split(".") | .[0]) as $f
                    | ((.to_version // "") | split(".") | .[0]) as $t
                    | if ($f|length) == 0 or ($t|length) == 0 then "unknown"
                      elif $f != $t then "major" else "minor-or-patch" end ) ]
      else [] end' < "$TMP/$i.pulls" 2>/dev/null || echo "")
    [ -z "$OUT" ] && OUT='[]'
    printf '%s\n' "$OUT" > "$TMP/$i.json"
  ) &
  PIDS+=("$!")
  i=$((i+1))
done
wait "${PIDS[@]}"

if ! ls "$TMP"/*.json >/dev/null 2>&1; then
  echo '{"wakeAgent": true, "data": {"status": "fetch-failed", "hint": "no repo produced a result — check the token and the sandbox network policy"}}'
  exit 0
fi
ALL=$(cat "$TMP"/*.json 2>/dev/null | jq -c -s 'add // []' 2>/dev/null || echo '[]')
SEEN_JSON=$(jq -R -s -c 'split("\n") | map(select(length > 0))' < "$SEEN" 2>/dev/null || echo '[]')
# Key on number + head SHA so a rebase re-opens the review.
FRESH=$(jq -c -n --argjson a "$ALL" --argjson seen "$SEEN_JSON" '
  [ $a[] | select((("\(.repo)#\(.number)@\(.head_sha)") | IN($seen[])) | not) ]' 2>/dev/null || echo '[]')
# Security-backed first, then majors — the ones that stall.
SORTED=$(printf '%s' "$FRESH" | jq -c '
  def sev: {"critical":0,"high":1,"moderate":2,"medium":2,"low":3};
  sort_by((if .security_backed then 0 else 1 end),
          (sev[.severity // ""] // 9),
          (if .bump == "major" then 0 else 1 end),
          .repo, .number)')
TOTAL=$(printf '%s' "$SORTED" | jq 'length')
BATCH=$(printf '%s' "$SORTED" | jq -c --argjson n "$MAX_PER_RUN" '.[0:$n]')
DEFERRED=$(( TOTAL - $(printf '%s' "$BATCH" | jq 'length') ))
[ "$DEFERRED" -lt 0 ] && DEFERRED=0

if [ "$(printf '%s' "$BATCH" | jq 'length')" -eq 0 ]; then
  echo '{"wakeAgent": false, "data": {"status": "nothing-to-review"}}'
  exit 0
fi

# Ack now: Dependabot PRs are long-lived, so re-waking on the same unchanged PR
# every 6 hours would be the dominant cost of this task. A rebase changes the
# SHA and brings it back, which is the case that actually needs re-reading.
printf '%s' "$BATCH" | jq -r '.[] | "\(.repo)#\(.number)@\(.head_sha)"' >> "$SEEN" 2>/dev/null || true
tail -n 500 "$SEEN" > "$SEEN.t" 2>/dev/null && mv "$SEEN.t" "$SEEN"

printf '{"wakeAgent": true, "data": {"status": "to-review", "count": %s, "deferred": %s, "security_backed": %s, "major_bumps": %s, "prs": %s}}\n' \
  "$(printf '%s' "$BATCH" | jq 'length')" "$DEFERRED" \
  "$(printf '%s' "$BATCH" | jq '[.[] | select(.security_backed)] | length')" \
  "$(printf '%s' "$BATCH" | jq '[.[] | select(.bump == "major")] | length')" \
  "$BATCH"
