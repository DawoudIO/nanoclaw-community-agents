---
schedule: "55 10 * * *"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
  # Daily newcomer-path audit via GitHub's community-profile endpoint —
  # ONE call per repo answers all of it: CONTRIBUTING, CODE_OF_CONDUCT, issue
  # and PR templates, README, license, plus GitHub's own health percentage.
  # Research context: failed OSS projects had contributing guidelines 16% of
  # the time vs 72% for healthy ones — a well-tended good-first-issue list on
  # a repo with no CONTRIBUTING.md optimizes step two of a path with no step
  # one. Wakes only when something is missing or a fetch failed.
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
  exec > >(tee >(sed -u "s/^{/{\"_ts\":\"$(date -u +%FT%TZ)\",/" >> "$DATA/telemetry/repo-hygiene-audit.jsonl" 2>/dev/null) 2>/dev/null)
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  REPOS="${COMMUNITY_REPOS:-}"
  if [ -z "$REPOS" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-helper/config.env"}}'
    exit 0
  fi
  TMP=$(mktemp -d)
  i=0
  PIDS=()   # deadlock fix: exec > >(tee ...) puts a background subshell in this shell's
  # own job table, so a BARE 'wait' below would also wait on it -- and it
  # cannot exit until this script's stdout closes, which cannot happen until
  # the script exits, which is blocked on that same wait. Track only the
  # per-repo PIDs and wait on those explicitly.
  for REPO in $REPOS; do
    (
      RESP=$(curl -fsS --max-time 10 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$REPO/community/profile" 2>/dev/null) || RESP=""
      if [ -z "$RESP" ] || ! printf '%s' "$RESP" | jq -e '.health_percentage' >/dev/null 2>&1; then
        printf '{"repo": "%s", "status": "fetch-failed"}\n' "$REPO" > "$TMP/$i.json"
        exit 0
      fi
      printf '%s' "$RESP" | jq -c --arg r "$REPO" '{
        repo: $r,
        status: "ok",
        health_percentage: .health_percentage,
        missing: ([.files | to_entries[] | select(.value == null) | .key])
      }' > "$TMP/$i.json" 2>/dev/null \
        || printf '{"repo": "%s", "status": "fetch-failed"}\n' "$REPO" > "$TMP/$i.json"
    ) &
    PIDS+=("$!")
    i=$((i+1))
  done
  wait "${PIDS[@]}"
  ALL=$(cat "$TMP"/*.json | jq -c -s '.')
  rm -rf "$TMP"
  FAILED=$(printf '%s' "$ALL" | jq -c '[.[] | select(.status=="fetch-failed") | .repo]')
  GAPS=$(printf '%s' "$ALL" | jq '[.[] | select(.status=="ok" and (.missing | length) > 0)] | length')
  if [ "$(printf '%s' "$FAILED" | jq 'length')" -gt 0 ] || [ "$GAPS" -gt 0 ]; then
    printf '{"wakeAgent": true, "data": {"status": "attention", "failed_repos": %s, "results": %s}}\n' "$FAILED" "$ALL"
  else
    echo '{"wakeAgent": false, "data": {"status": "all-complete"}}'
  fi
---
Daily newcomer-path audit. Only invoked when a repo is missing community
health files or a fetch failed — a fully complete repo set stays silent, which
on a healthy project is most days.

**These absences change on the scale of months, not days.** Running daily
catches a newly-added repo (or a file someone deleted) quickly, but it also
means the same missing `CONTRIBUTING.md` is true again tomorrow. Say it once
and let it rest: if you already reported a repo's missing files and nothing
about that list has changed, don't re-report it — note only what is new since
your last report. Re-sending an identical audit daily is how a real finding
gets tuned out.

**If a repo is in `failed_repos`**: report the symptom to your manager (`401/403`
= token wiring, `502` = sandbox network policy) and skip it this run.

For each repo in `scriptOutput.results` with a non-empty `missing` list:
GitHub's community profile has flagged absent files —
possible values include `code_of_conduct`, `contributing`, `issue_template`,
`pull_request_template`, `readme`, `license`. For each:

- Say plainly what's missing and why it matters in one line each (a repo with
  no CONTRIBUTING.md has no documented first step for a newcomer; no
  CODE_OF_CONDUCT.md means no named process when something goes wrong — and
  a code of conduct needs a *human* responder named in it, which no agent can
  be).
- **Do not write the files.** These land in the repo under the project's name
  and are read as the project speaking, which is not yours to do — a
  CONTRIBUTING.md is the first thing a newcomer reads. Name the absence and
  its cost; ask your manager to draft the content. (This is a deliberate change:
  handing over a ready-to-commit draft was faster, but a file committed under
  the project's name speaks for the project, and that is the owner's voice to
  use, not yours.)
- For CODE_OF_CONDUCT.md, note only that one is absent and that any code of
  conduct needs a named *human* reporting contact before it means anything.
  Which document to adopt is the owner's call — don't name a specific one.

Hand the audit to your manager as one short report, worst repo first. Include
each repo's `health_percentage` so the owner can see whether it's moving.
Don't re-litigate files that exist — this task is about absences.
