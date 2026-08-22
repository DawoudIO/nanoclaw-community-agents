#!/bin/bash
set -euo pipefail
# Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy — no token
# in this file, no `gh` CLI (it refuses to run without local auth config,
# which containers deliberately don't have).
# Failure design: an HTTP error (incl. 403 = fine-grained token missing the
# Dependabot alerts read permission) WAKES the agent as fetch-failed — it
# must never read as "no new advisories". And the script never marks
# alerts seen: the AGENT acks them after handing off, so a lost wake
# re-surfaces the alert next run.
DATA="/workspace/agent/plugin-data/community-coding"
mkdir -p "$DATA"
if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
REPOS="${COMMUNITY_REPOS:-}"
if [ -z "$REPOS" ]; then
  echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-coding/config.env"}}'
  exit 0
fi
SEEN="$DATA/seen-advisories.txt"
touch "$SEEN"
NEW="[]"; FAILED=""
for REPO in $REPOS; do
  ALERTS=$(curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/dependabot/alerts?state=open&per_page=100") || { FAILED="$FAILED $REPO"; continue; }
  # Carry the whole finding, not just the id. This response already contains
  # severity, package, scope and the patched version — the previous version
  # extracted `.number` and threw the rest away, which forced the agent to
  # re-fetch every alert just to learn whether it was critical or low, and made
  # severity-based routing impossible. `dependency.scope` matters most of all:
  # a development-only dependency is a materially different risk from a runtime
  # one, and it is the first input to the reachability judgment.
  ENRICHED=$(printf '%s' "$ALERTS" | jq -c --arg r "$REPO" 'if type=="array" then
    [ .[] | {
        repo: $r,
        alert: .number,
        ghsa_id: (.security_advisory.ghsa_id // null),
        cve_id: (.security_advisory.cve_id // null),
        severity: ((.security_advisory.severity // .security_vulnerability.severity // "unknown") | ascii_downcase),
        cvss: (.security_advisory.cvss.score // null),
        package: (.security_vulnerability.package.name // null),
        ecosystem: (.security_vulnerability.package.ecosystem // null),
        scope: (.dependency.scope // null),
        vulnerable_range: (.security_vulnerability.vulnerable_version_range // null),
        first_patched: (.security_vulnerability.first_patched_version.identifier // null),
        summary: ((.security_advisory.summary // "") | .[0:200]),
        url: (.html_url // null)
      } ]
    else [] end' 2>/dev/null || echo '[]')
  while IFS= read -r ONE; do
    [ -z "$ONE" ] && continue
    ID=$(printf '%s' "$ONE" | jq -r '.alert')
    if ! grep -qxF "$REPO#$ID" "$SEEN"; then
      NEW=$(printf '%s' "$NEW" | jq -c --argjson o "$ONE" '. + [$o]')
    fi
  done <<EOF
$(printf '%s' "$ENRICHED" | jq -c '.[]' 2>/dev/null)
EOF
done
if [ -n "$FAILED" ]; then
  printf '{"wakeAgent": true, "data": {"status": "fetch-failed", "failed_repos": "%s", "hint": "403 usually means the fine-grained token is missing the Dependabot alerts (read) permission", "new": %s}}\n' "${FAILED# }" "$NEW"
  exit 0
fi
if [ "$(printf '%s' "$NEW" | jq 'length')" -eq 0 ]; then
  echo '{"wakeAgent": false, "data": {"status": "no-new-advisories"}}'
else
  # Sort worst-first and roll up the counts, so the report can lead with what
  # matters instead of the order GitHub happened to return.
  SORTED=$(printf '%s' "$NEW" | jq -c '
    def rank: {"critical":0,"high":1,"moderate":2,"medium":2,"low":3,"unknown":4};
    sort_by(rank[.severity] // 4, .repo, .alert)')
  COUNTS=$(printf '%s' "$SORTED" | jq -c '
    reduce .[] as $a ({}; .[$a.severity] = ((.[$a.severity] // 0) + 1))')
  TOP=$(printf '%s' "$SORTED" | jq -r '.[0].severity // "unknown"')
  RUNTIME=$(printf '%s' "$SORTED" | jq '[.[] | select(.scope != "development")] | length')
  printf '{"wakeAgent": true, "data": {"status": "new", "count": %s, "highest_severity": "%s", "by_severity": %s, "runtime_scoped": %s, "advisories": %s}}\n' \
    "$(printf '%s' "$SORTED" | jq 'length')" "$TOP" "$COUNTS" "$RUNTIME" "$SORTED"
fi
