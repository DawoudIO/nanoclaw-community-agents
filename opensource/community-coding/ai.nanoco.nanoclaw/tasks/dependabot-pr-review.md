---
schedule: "11 */6 * * *"
script: |
  #!/bin/bash
  set -uo pipefail
  # Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
  #
  # Review Dependabot's open pull requests. Split out of
  # security-advisory-sweep, which had grown two distinct jobs under one name:
  #
  #   security-advisory-sweep  — input: ALERTS. "Are we affected, and if nobody
  #                              else is fixing it, draft the bump."
  #   dependabot-pr-review     — input: PULL REQUESTS. "Dependabot proposed a
  #                              version change; what does it actually cost us?"
  #
  # Different inputs, different deliverables, and the review half is the one that
  # matters more often: Dependabot tells you a version changed and says nothing
  # about what it means in this codebase. A major bump inside a security PR is a
  # breaking change wearing a security label, and that is why these sit unmerged.
  #
  # Re-review on force-push: Dependabot rebases its branches constantly. The
  # ledger key is PR number + head SHA, so a rebased or retargeted PR comes back
  # for review instead of being remembered as done.
  DATA="/workspace/agent/plugin-data/community-coding"
  mkdir -p "$DATA"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  REPOS="${COMMUNITY_REPOS:-}"
  if [ -z "$REPOS" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-coding/config.env"}}'
    exit 0
  fi
  MAX_PER_RUN="${DEPENDABOT_REVIEW_MAX:-8}"
  case "$MAX_PER_RUN" in ''|*[!0-9]*) MAX_PER_RUN=8;; esac

  SEEN="$DATA/dependabot-reviewed.txt"
  touch "$SEEN"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  i=0
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
    i=$((i+1))
  done
  wait

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
---

Dependabot proposed a version change. **Your job is making its cost clear** —
Dependabot says what changed and nothing about what it means here, which is
exactly why these PRs sit unmerged.

`prs` is sorted worst-first: security-backed before routine, and within that,
majors before patches. Each entry has the package, `from_version`/`to_version`,
`bump` (`major` / `minor-or-patch` / `unknown`), and — when a Dependabot alert
backs it — `alert`, `severity` and `security_backed: true`.

**If `deferred` is non-zero**, more PRs are waiting than the per-run cap. Say
the number; a pile-up of unreviewed bumps is itself the finding.

## Per PR

- **`bump: "major"` is the headline.** A major version inside a security PR is a
  breaking change wearing a security label. Read the release notes between the
  two versions and say what breaks. This is the single most useful thing you
  produce here, because it is the reason a maintainer has been avoiding the PR.
- **Do we call the affected code?** Read the files that import the package —
  **if `/workspace/shared-repos/<repo>/` exists (the shared mirror local ops
  keeps in sync — check `.last-sync-epoch`'s age first, and say "as of
  <sync time>" if you use it), grep it directly.** Otherwise fall back to the
  API, or ask your lead to have the local ops agent grep its mirror. "We
  import this in two places, neither touches the changed API" is worth more
  than any severity score.
- **Read the diff, not the title.** A lockfile-only change is routine. A bump
  that drags in transitive majors is not, and the title won't tell you.
- **`security_backed: false`** means this is a routine version update, not a
  vulnerability. Those deserve one line each at most — don't spend a paragraph
  on a patch bump nobody is waiting for.

## The verdict

One of three, with the evidence:

- **Safe to merge** — patch/minor, no API surface we touch, tests exist.
- **Merge, expect X** — name what breaks and roughly what it costs.
- **Do not merge yet** — a human has to decide something specific. Say what.

Always say **what you did not check**. You have not run the tests, and a
reviewer trusting an untested "safe to merge" is a worse outcome than no review.

## Boundaries

**You cannot comment on the PR, and that is deliberate** — your token has
Issues read only, and PR comments are issue comments. PR conversation belongs to
the lead's single public voice. Hand it your review; the lead posts it.

Never approve, never mark ready, never merge, and never push to a Dependabot
branch — it force-pushes on its own schedule and would clobber you anyway.

## Reporting

To your lead, worst-first. Lead with anything `security_backed` and `major`
together — that combination is what stalls, and getting a decision on it is the
whole point of this task. Routine patch bumps roll into one line.
