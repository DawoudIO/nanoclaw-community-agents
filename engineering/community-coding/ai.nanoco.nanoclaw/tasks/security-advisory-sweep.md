---
schedule: "45 */4 * * *"
script: |
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
  # SECURITY_WATCH_REPOS is an OPTIONAL narrower override, falling back to
  # COMMUNITY_REPOS. A docs site or content repo rarely has dependencies worth
  # a security sweep, and the Dependabot alerts (read) permission has to be
  # granted per-repo on the token — set this to just the repos that actually
  # ship code, e.g. the primary product repo, if you don't want the rest.
  REPOS="${SECURITY_WATCH_REPOS:-${COMMUNITY_REPOS:-}}"
  if [ -z "$REPOS" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set SECURITY_WATCH_REPOS (or COMMUNITY_REPOS) in plugin-data/community-coding/config.env"}}'
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
---
**If `status` is `fetch-failed`**: report to your lead — a `403` here almost
always means the fine-grained token is missing the **Dependabot alerts
(read)** repository permission. This is a security task; a broken fetch must
be surfaced, never mistaken for a quiet day.

**If `status` is `new`**: the gate hands you every open alert, worst-first,
already enriched — `severity`, `cvss`, `package`, `ecosystem`, `scope`,
`vulnerable_range`, `first_patched`, `ghsa_id`, `summary`, `url` — plus
`by_severity`, `highest_severity` and `runtime_scoped`. You do not need to
re-fetch anything to triage.

Two jobs per advisory, in order.

## 1. Is the severity real *for this repo*?

GitHub's severity is generic; yours is specific. Downgrade or upgrade it with
reasons, and say which you did:

- **`scope: "development"`** is the biggest discount. A build-time dependency
  is not in the shipped attack surface. It still gets patched eventually, but
  it is not an incident.
- **Reachability.** Is the vulnerable function actually called? **Grep
  `/workspace/shared-repos/<repo>/` if it exists** (the shared mirror local
  ops keeps in sync — check `.last-sync-epoch`'s age and note it if you use
  this) rather than fetching individual files via the API one at a time.
  "Vulnerable version present but the affected API is never invoked" is a
  legitimate, defensible downgrade — write down the path you checked so a
  human can disagree with a specific claim rather than a vibe.
- **Exploitability in context.** A DoS in a CLI a maintainer runs locally is
  not the same as one in a request path.
- **Project rules.** If `project-config.md` sets a security policy — a minimum
  severity to act on, a dependency-freeze, a supported-version window — that
  overrides these defaults. Read it before deciding.

Record the verdict as **confirmed**, **downgraded** or **not-applicable**,
always with the reason. `not-applicable` is a real and valuable answer;
inflating everything to critical is how a security channel gets muted.

## 2. If it is a true risk, make sure a fix exists

**Check `has_fix_pr` first.** Dependabot usually fixes what it reports: with
security updates enabled it opens the bump PR itself, and the gate has already
correlated its open PRs to these alerts by package name. Opening your own branch
for a fix that already exists gives the maintainer two PRs for one CVE.

### `has_fix_pr: true` — someone else is already fixing it

Record it and move on. **Do not open a second branch**, and do not review the
diff here — reviewing Dependabot's proposal is `dependabot-pr-review`'s job,
which is a separate task precisely so this one stays about "are we affected"
rather than also becoming "is that bump safe". Note in your report that the
advisory is covered by PR #N so the owner can see it is handled.

### `has_fix_pr: false` — draft it yourself

**You draft a patch PR. This is the one place you write.** Move the advisory
out of triage and into a reviewable change — a report saying "you should
upgrade lodash" is strictly worse than a branch that already does it.

`needs_fix_pr` counts these. Draft when all three hold:

1. `first_patched` exists (there is somewhere to go), **and**
2. the verdict is **confirmed** — a real risk to this project, **and**
3. the bump is non-breaking: a patch or minor version, or a major one the
   project has already moved past elsewhere.

Then:

- Branch from the default branch: `security/<ghsa-id>` or
  `security/bump-<package>-<version>`.
- Change **only** the dependency version — manifest and lockfile. Nothing else,
  no drive-by tidying, no reformatting.
- Open it as a **DRAFT** pull request. Never ready-for-review, never merged,
  never pushed to the default branch.
- Body: the GHSA id and link, severity as GitHub states it **and** your verdict
  with its reason, the version change, and what you did *not* verify — say
  plainly that tests have not been run and a human must confirm nothing broke.
- Reference the alert so GitHub links them.

**Do not attempt the fix** when it needs a code change, a major upgrade with
breaking changes, or a transitive dependency you cannot pin directly. Say so,
name what a human has to decide, and stop. A confidently wrong security patch
costs more than an honest hand-off.

**Never write a code-level vulnerability fix.** Your scope is version bumps.
Fixing the vulnerable logic itself belongs to a maintainer.

**If `status` is `new`**: for each advisory in `scriptOutput.new`/`advisories`:
**Then ack**: append one `owner/repo#id` line per handled alert to
`plugin-data/community-coding/seen-advisories.txt` — that's your
acknowledgment, and it's yours to write, not the script's, so an alert whose
wake was lost re-surfaces next run instead of vanishing. Duplicates beat
losses.

## Routing

Hand your lead: the verdict per advisory, which ones are already covered by a
Dependabot PR (number only — the review comes from `dependabot-pr-review`),
the draft PR links for ones you created, and anything you declined to patch
with the reason. A `critical` or `high` with a **confirmed**
verdict and runtime scope is owner-urgent — it bypasses the daily digest.
Everything downgraded or not-applicable rides the normal digest.

Never post advisory detail to a public channel yourself, and never open a
public *issue* about an unfixed vulnerability — a draft PR referencing an
already-public GHSA is fine, an issue advertising an unpatched hole is not.
Your lead routes disclosure per its own escalation rules.
