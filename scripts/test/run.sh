#!/bin/bash
# Test harness for the task gate scripts — runs WITHOUT any agent.
#
#   bash scripts/test/run.sh
#
# What it asserts:
#   1a. bash -n syntax, every gate + every setup-check
#   1b. credential invariant — no script may construct an auth header
#   1c. task frontmatter is structurally valid (independent of sync-tasks)
#   1d. onboarding-answers.example.json matches the code, both directions
#   2.  behavioral (assert_gate) — each gate emits exactly ONE line of valid
#       JSON with the expected wakeAgent, for: unconfigured (must not wake)
#       and total fetch failure (must wake — a broken fetch must never read
#       as a quiet day).
#   2b/2c. success paths (assert_scenario) — canned API responses from
#       scripts/test/fixtures/<scenario>/, asserting on the emitted JSON's
#       SHAPE via a jq predicate, because that shape is the contract the task
#       prompts read. Multi-run scenarios cover suppression branches, which
#       only exist from run 2 onward.
#
# HONEST LIMITS, so nobody mistakes green for complete:
#   - Fixtures cover 7 scenarios across 6 gates, not all 16. Uncovered on the
#     success path: security-advisory-sweep, github-ops-triage,
#     daily-github-triage, weekly-analytics-report, repo-hygiene-audit,
#     draft-cleanup, workspace-backup, weekly-identity-integrity-check.
#   - The repo-mirror-sync assertion needs live network to github.com; it is
#     the one test that flips on an offline run.
#   - Fixtures are hand-written, so they encode what we BELIEVE each API
#     returns. They catch our own logic errors, not upstream API changes —
#     only a real install does that.
#
# Mock model: a fake `curl` is placed first on PATH (a real executable, not
# an exported function — exported functions don't survive into `bash x.sh`
# children on bash 3.2/macOS).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0

fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { PASS=$((PASS+1)); }

# --- 1. syntax check on everything -----------------------------------------
for sh in "$ROOT"/scripts/tasks/*/*.sh "$ROOT"/*/*/setup-check.sh; do
  if bash -n "$sh" 2>/dev/null; then pass; else fail "syntax: $sh"; fi
done

# --- 1b. credential invariant -----------------------------------------------
# No task script may ever construct an auth header or read a credential:
# authentication is injected by the OneCLI egress proxy OUTSIDE the container,
# so the scripts (and the ps table, env, and shell history inside the agent
# container) never hold a secret. Comments are allowed to mention tokens;
# code is not allowed to send them.
for sh in "$ROOT"/scripts/tasks/*/*.sh "$ROOT"/*/*/setup-check.sh; do
  if grep -v '^\s*#' "$sh" | grep -qE '\-H *"?(Authorization|X-Api-Key)|Bearer \$|GITHUB_TOKEN|ANTHROPIC_API_KEY|access_token='; then
    fail "credential material in $sh — auth belongs to the proxy, never the script"
  else
    pass
  fi
done

# --- 1c. task frontmatter must be structurally valid ------------------------
# A previous sync-tasks bug left stale script fragments below the block
# scalar in 12 of 18 task files: unindented shell text inside the YAML
# frontmatter, which the runtime parses. Both the injector and the checker
# stopped at the first unindented line, so the corruption was invisible to
# --check while being preserved by every re-sync. This asserts the shape
# directly, independent of the sync tool, so that class of bug can't hide
# again: inside the frontmatter, every line is either a `key:` or indented.
for md in "$ROOT"/*/*/ai.nanoco.nanoclaw/tasks/*.md; do
  if awk '
      /^---$/ { fm++; if (fm==2) exit; next }
      fm==1 && $0 != "" && $0 !~ /^[ \t]/ && $0 !~ /^[a-zA-Z_]+:/ { bad=1; exit }
      END { exit (bad ? 1 : 0) }
    ' "$md"; then
    pass
  else
    fail "corrupt frontmatter (unindented non-key line inside ---): $md"
  fi
done

# --- 1d. onboarding answer template must match the code ---------------------
# Bidirectional key coverage plus a secret-leak guard; see
# scripts/check-onboarding.sh. Counted as one assertion here — it prints its
# own detail on failure.
if bash "$ROOT/scripts/check-onboarding.sh" >/dev/null 2>&1; then
  pass
else
  fail "onboarding-answers.example.json is out of sync with the code (run: bash scripts/check-onboarding.sh)"
fi

# --- 2. behavioral: single-line valid JSON contract ------------------------
# Each script runs in a sandbox dir with plugin-data pre-seeded per scenario.
# assert_gate <script> <scenario-name> <expected-wakeAgent|any> <config-env-content>
assert_gate() {
  local sh="$1" name="$2" expect="$3" cfg="$4"
  local sandbox; sandbox=$(mktemp -d)
  local sname; sname=$(basename "$sh" .sh)
  local fixdir="$ROOT/scripts/test/fixtures/$sname"
  mkdir -p "$sandbox/bin" "$sandbox/plugin-data/community-support" \
           "$sandbox/plugin-data/community-coding" "$sandbox/plugin-data/community-marketing"
  # fake curl: first URL-ish arg is matched against fixture patterns
  cat > "$sandbox/bin/curl" <<MOCK
#!/bin/bash
url=""
for a in "\$@"; do case "\$a" in https://*) url="\$a";; esac; done
if [ -d "$fixdir" ]; then
  while IFS='|' read -r pat file; do
    [ -z "\$pat" ] && continue
    case "\$url" in *"\$pat"*) cat "$fixdir/\$file"; exit 0;; esac
  done < "$fixdir/routes.txt"
fi
exit 22
MOCK
  chmod +x "$sandbox/bin/curl"
  for g in community-support community-coding community-marketing; do
    [ -n "$cfg" ] && printf '%s\n' "$cfg" > "$sandbox/plugin-data/$g/config.env"
  done
  local out
  out=$(cd "$sandbox" && PATH="$sandbox/bin:$PATH" \
        bash <(sed "s#/workspace/agent/plugin-data#$sandbox/plugin-data#g" "$sh") 2>/dev/null | tail -1)
  rm -rf "$sandbox"
  if ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    fail "$sname/$name: last line is not valid JSON: ${out:0:120}"
    return
  fi
  if [ "$expect" != "any" ]; then
    local wake
    wake=$(printf '%s' "$out" | jq -r '.wakeAgent')
    if [ "$wake" != "$expect" ]; then
      fail "$sname/$name: wakeAgent=$wake, expected $expect"
      return
    fi
  fi
  pass
}

# --- 2b. success-path scenarios --------------------------------------------
# assert_scenario <script> <fixture-dir> <expect-wake|any> <jq-predicate|-> \
#                 <config-env> [runs] [seed-shell]
#
# Differs from assert_gate in three ways that matter:
#   - fixture dir is named per SCENARIO, not per script, so one gate can have
#     several canned API states (new-release vs no-change, etc.)
#   - <jq-predicate> asserts on the emitted JSON's SHAPE, which is what the
#     task prompts actually depend on. wakeAgent alone can't catch a renamed
#     or missing field.
#   - [runs] executes the gate N times in the SAME sandbox and asserts on the
#     last run. Suppression branches only exist on run 2+ (run 1 establishes
#     the baseline), so without this the entire "quiet day stays quiet" half
#     of every wake gate is untestable.
assert_scenario() {
  local sh="$1" fixture="$2" expect="$3" pred="$4" cfg="$5" runs="${6:-1}" seed="${7:-}"
  local sandbox; sandbox=$(mktemp -d)
  local sname; sname=$(basename "$sh" .sh)
  local fixdir="$ROOT/scripts/test/fixtures/$fixture"
  mkdir -p "$sandbox/bin" "$sandbox/plugin-data/community-support" \
           "$sandbox/plugin-data/community-coding" "$sandbox/plugin-data/community-marketing"
  cat > "$sandbox/bin/curl" <<MOCK
#!/bin/bash
url=""
for a in "\$@"; do case "\$a" in https://*) url="\$a";; esac; done
if [ -f "$fixdir/routes.txt" ]; then
  while IFS='|' read -r pat file; do
    [ -z "\$pat" ] && continue
    case "\$url" in *"\$pat"*) cat "$fixdir/\$file"; exit 0;; esac
  done < "$fixdir/routes.txt"
fi
exit 22
MOCK
  chmod +x "$sandbox/bin/curl"
  for g in community-support community-coding community-marketing; do
    [ -n "$cfg" ] && printf '%s\n' "$cfg" > "$sandbox/plugin-data/$g/config.env"
  done
  [ -n "$seed" ] && ( cd "$sandbox" && SANDBOX="$sandbox" bash -c "$seed" )
  local out i
  for i in $(seq 1 "$runs"); do
    out=$(cd "$sandbox" && PATH="$sandbox/bin:$PATH" \
          bash <(sed "s#/workspace/agent/plugin-data#$sandbox/plugin-data#g" "$sh") 2>/dev/null | tail -1)
  done
  rm -rf "$sandbox"
  local label="$sname/$fixture"
  [ "$runs" -gt 1 ] && label="$label(run$runs)"
  if ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    fail "$label: last line is not valid JSON: ${out:0:140}"; return
  fi
  if [ "$expect" != "any" ]; then
    local wake; wake=$(printf '%s' "$out" | jq -r '.wakeAgent')
    if [ "$wake" != "$expect" ]; then
      fail "$label: wakeAgent=$wake, expected $expect — got: ${out:0:200}"; return
    fi
  fi
  if [ "$pred" != "-" ]; then
    if ! printf '%s' "$out" | jq -e "$pred" >/dev/null 2>&1; then
      fail "$label: output failed predicate [$pred] — got: ${out:0:260}"; return
    fi
  fi
  pass
}

# Unconfigured: every config-gated script must exit clean without waking.
for sh in "$ROOT"/scripts/tasks/engineering/*.sh "$ROOT"/scripts/tasks/marketing/*.sh \
          "$ROOT"/scripts/tasks/support/daily-github-triage.sh \
          "$ROOT"/scripts/tasks/support/release-announcement-watch.sh; do
  assert_gate "$sh" "unconfigured" "false" ""
done

# Fetch failure with config set: gates that watch external state must WAKE
# (a broken fetch must never read as a quiet day). The mock curl exits 22
# for every URL because no fixtures matched.
assert_gate "$ROOT/scripts/tasks/engineering/security-advisory-sweep.sh" \
  "fetch-fails-must-wake" "true" 'COMMUNITY_REPOS="acme/demo"'
assert_gate "$ROOT/scripts/tasks/engineering/dev-metrics-report.sh" \
  "fetch-fails-must-wake" "true" 'COMMUNITY_REPOS="acme/demo"'
assert_gate "$ROOT/scripts/tasks/engineering/good-first-issue-health.sh" \
  "fetch-fails-must-wake" "true" 'COMMUNITY_REPOS="acme/demo"'
assert_gate "$ROOT/scripts/tasks/support/release-announcement-watch.sh" \
  "fetch-fails-must-wake" "true" 'COMMUNITY_REPOS="acme/demo"'
assert_gate "$ROOT/scripts/tasks/marketing/draft-cleanup.sh" \
  "fetch-fails-must-wake" "true" 'CONTENT_REPO="acme/demo"'
assert_gate "$ROOT/scripts/tasks/engineering/github-ops-triage.sh" \
  "fetch-fails-must-wake" "true" 'COMMUNITY_REPOS="acme/demo"'
assert_gate "$ROOT/scripts/tasks/support/daily-github-triage.sh" \
  "fetch-fails-must-wake" "true" 'COMMUNITY_REPOS="acme/demo"'

# health-check: no config needed; on a healthy fresh box the only wake
# reason is the first-run weekly heartbeat.
assert_gate "$ROOT/scripts/tasks/support/health-check.sh" "first-run-heartbeat" "true" ""

# repo-mirror-sync: a nonexistent repo is a real clone failure (no mock
# needed — git's own error against a real host is the test).
assert_gate "$ROOT/scripts/tasks/engineering/repo-mirror-sync.sh" \
  "nonexistent-repo-clone-must-wake" "true" 'MIRROR_REPOS="acme/this-repo-does-not-exist-xyz-12345"'

# --- 2c. success-path assertions -------------------------------------------
# These check the SHAPE the task prompts actually read. A renamed or dropped
# field here is a broken task even though the gate still emits valid JSON and
# the right wakeAgent — which is exactly what the failure-only tests miss.

# dev-metrics-report: every field its prompt references, in the nesting the
# prompt describes. `count` (14) deliberately exceeds the listed prs (2) so
# the "N approved PRs waiting, oldest 10 listed" truncation path is covered.
assert_scenario "$ROOT/scripts/tasks/engineering/dev-metrics-report.sh" dev-metrics-full true \
  '.data.today["acme/demo"] as $t
   | ($t.stars == 937) and ($t.forks == 558)
     and ($t.open_issues == 42) and ($t.open_prs == 7)
     and ($t.releases[0].downloads == 1000)
     and ($t.awaiting_first_response.issues == 5)
     and ($t.awaiting_first_response.oldest_issue_since == "2026-06-01T00:00:00Z")
     and ($t.closed_prs_30d.merged == 20) and ($t.closed_prs_30d.unmerged == 4)
     and ($t.closed_prs_30d.unmerged_ratio == 0.17)
     and (.data.ready_to_merge[0].ready_to_merge.count == 14)
     and (.data.ready_to_merge[0].ready_to_merge.prs | length == 2)
     and (.data.ready_to_merge[0].ready_to_merge.prs[0].author == "contribA")
     and (.data.degraded_repos | length == 0)' \
  'COMMUNITY_REPOS="acme/demo"'

# dev-metrics-report, run 2: nothing changed between runs, and no approved PRs
# this time, so the wake gate must SUPPRESS. Untestable without multi-run.
assert_scenario "$ROOT/scripts/tasks/engineering/dev-metrics-report.sh" dev-metrics-quiet false \
  '.data.quiet_heartbeat == true' 'COMMUNITY_REPOS="acme/demo"' 2

# posthog: byte-identical insight results across two runs must suppress, and
# previous_result must be populated from history on run 2. This is the exact
# bug the 28-day heartbeat fix addressed — a 7-day heartbeat on a weekly cron
# made this assertion impossible to satisfy.
assert_scenario "$ROOT/scripts/tasks/engineering/posthog-weekly-review.sh" posthog-static false \
  '(.data.quiet_heartbeat == true)
   and (.data.insights[0].result == .data.insights[0].previous_result)
   and (.data.insights[0].name == "Weekly signups")' \
  'POSTHOG_PROJECT_ID="123"' 2

# good-first-issue-health: only the unassigned AND stale issue is listed;
# truncated must be true because total_count (150) > items returned (3).
assert_scenario "$ROOT/scripts/tasks/engineering/good-first-issue-health.sh" gfi-stale true \
  '.data.results[0] as $r
   | ($r.open_count == 150) and ($r.truncated == true)
     and ($r.unassigned_stale | length == 1)
     and ($r.unassigned_stale[0].number == 10)' \
  'COMMUNITY_REPOS="acme/demo"'

# release-announcement-watch: run 1 seeds the baseline WITHOUT announcing (a
# fresh install must not retroactively announce shipped releases)...
assert_scenario "$ROOT/scripts/tasks/support/release-announcement-watch.sh" release-new false \
  '.data.status == "quiet"' 'COMMUNITY_REPOS="acme/demo"'
# ...and stays quiet on run 2 because the AGENT, not the script, advances the
# baseline — so the same release must keep re-surfacing as un-acked, never
# silently vanish. Same fixture, so the tag is unchanged: still no wake.
assert_scenario "$ROOT/scripts/tasks/support/release-announcement-watch.sh" release-new false \
  '.data.status == "quiet"' 'COMMUNITY_REPOS="acme/demo"' 2

# content-draft-cycle: on a fresh sandbox run 1 seeds the release baseline and
# the weekly floor is immediately due, so it wakes with trigger "weekly"...
assert_scenario "$ROOT/scripts/tasks/marketing/content-draft-cycle.sh" content-release true \
  '.data.trigger == "weekly"' \
  'CONTENT_REPO="acme/marketing"
RELEASE_WATCH_REPO="acme/demo"'
# ...and run 2 must suppress: the tag hasn't moved and the floor was just
# reset, so there is genuinely nothing to draft.
assert_scenario "$ROOT/scripts/tasks/marketing/content-draft-cycle.sh" content-release false \
  '.data.status == "no-trigger"' \
  'CONTENT_REPO="acme/marketing"
RELEASE_WATCH_REPO="acme/demo"' 2

# docs-gap-review: pure local-file logic, previously the ONLY gate with no
# behavioral coverage at all. Ledger seeded with one topic 4× inside the
# 60-day window and one 2× — only the 3+ topic may surface.
assert_scenario "$ROOT/scripts/tasks/support/docs-gap-review.sh" no-fixtures true \
  '(.data.status == "hot-topics")
   and (.data.topics | length == 1)
   and (.data.topics[0].topic == "csv-import-fails")
   and (.data.topics[0].count == 4)' \
  '' 1 \
  'D="$SANDBOX/plugin-data/community-support"; mkdir -p "$D";
   NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ);
   for i in 1 2 3 4; do echo "{\"date\":\"$NOW\",\"topic\":\"csv-import-fails\",\"channel\":\"#support\"}" >> "$D/question-ledger.jsonl"; done;
   for i in 1 2; do echo "{\"date\":\"$NOW\",\"topic\":\"how-to-backup\",\"channel\":\"#support\"}" >> "$D/question-ledger.jsonl"; done'

# docs-gap-review: a topic already proposed must not re-surface (the ack
# ledger is what stops the same docs page being proposed every week).
assert_scenario "$ROOT/scripts/tasks/support/docs-gap-review.sh" no-fixtures false \
  '.data.status == "quiet"' '' 1 \
  'D="$SANDBOX/plugin-data/community-support"; mkdir -p "$D";
   NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ);
   for i in 1 2 3 4; do echo "{\"date\":\"$NOW\",\"topic\":\"csv-import-fails\",\"channel\":\"#support\"}" >> "$D/question-ledger.jsonl"; done;
   echo "csv-import-fails" > "$D/docs-proposals-sent.txt"'

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
