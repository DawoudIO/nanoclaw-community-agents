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
exec > >(tee >(sed -u "s/^{/{\"_ts\":\"$(date -u +%FT%TZ)\",/" >> "$DATA/telemetry/security-advisory-sweep.jsonl" 2>/dev/null) 2>/dev/null)
if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
# SECURITY_WATCH_REPOS is an OPTIONAL narrower override, falling back to
# COMMUNITY_REPOS. A docs site or content repo rarely has dependencies worth
# a security sweep, and the Dependabot alerts (read) permission has to be
# granted per-repo on the token — set this to just the repos that actually
# ship code, e.g. the primary product repo, if you don't want the rest.
REPOS="${SECURITY_WATCH_REPOS:-${COMMUNITY_REPOS:-}}"
if [ -z "$REPOS" ]; then
  echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set SECURITY_WATCH_REPOS (or COMMUNITY_REPOS) in plugin-data/community-helper/config.env"}}'
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
  # Dependabot usually FIXES what it reports: with security updates enabled it
  # opens the bump PR itself. So list its open PRs and correlate them to the
  # alerts by package name — otherwise this agent drafts a second branch for a
  # fix that already exists, and the maintainer gets two PRs for one CVE.
  # When a PR exists the job is REVIEWING that diff, not recreating it.
  DPRS=$(curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/pulls?state=open&per_page=100" 2>/dev/null \
    | jq -c '[ .[]
        | select((.user.login // "") | test("^dependabot(\\[bot\\])?$"))
        | {number, title, url: .html_url, draft,
           head: (.head.ref // null),
           # Dependabot titles are machine-generated and stable:
           # "Bump <pkg> from <a> to <b>" (or "chore(deps): bump ...").
           package: ((.title | capture("(?i)bump (?<p>[^ ]+) from") | .p) // null),
           from_version: ((.title | capture("(?i) from (?<v>[^ ]+) to ") | .v) // null),
           to_version: ((.title | capture("(?i) to (?<v>[^ ]+)$") | .v) // null),
           created_at} ]' 2>/dev/null || echo '[]')
  [ -z "$DPRS" ] && DPRS='[]'

  ENRICHED=$(printf '%s' "$ALERTS" | jq -c --arg r "$REPO" --argjson dprs "$DPRS" 'if type=="array" then
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
      }
      | . as $a
      # Match a Dependabot PR to this alert by package name, case-insensitively.
      | .dependabot_pr = ( [ $dprs[]
          | select(($a.package // "") != "" and (.package // "") != "")
          | select((.package | ascii_downcase) == ($a.package | ascii_downcase)) ] | first // null)
      | .has_fix_pr = (.dependabot_pr != null)
      # semver delta of the proposed bump — the single best predictor of whether
      # this is a safe merge or a breaking change wearing a security label.
      | .bump = (if .dependabot_pr == null then null
                 else ((.dependabot_pr.from_version // "") | split(".") | .[0]) as $fj
                    | ((.dependabot_pr.to_version // "") | split(".") | .[0]) as $tj
                    | (if ($fj|length) == 0 or ($tj|length) == 0 then "unknown"
                       elif $fj != $tj then "major" else "minor-or-patch" end) end)
    ]
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
  WITH_PR=$(printf '%s' "$SORTED" | jq '[.[] | select(.has_fix_pr)] | length')
  NEEDS_PR=$(printf '%s' "$SORTED" | jq '[.[] | select(.has_fix_pr | not)] | length')
  MAJOR=$(printf '%s' "$SORTED" | jq '[.[] | select(.bump == "major")] | length')
  printf '{"wakeAgent": true, "data": {"status": "new", "count": %s, "highest_severity": "%s", "by_severity": %s, "runtime_scoped": %s, "with_fix_pr": %s, "needs_fix_pr": %s, "major_bumps": %s, "advisories": %s}}\n' \
    "$(printf '%s' "$SORTED" | jq 'length')" "$TOP" "$COUNTS" "$RUNTIME" "$WITH_PR" "$NEEDS_PR" "$MAJOR" "$SORTED"
fi
