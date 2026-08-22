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

# --- 1e. docs must not contradict the real topology ------------------------
# Prose that hand-restates counts ("18 tasks", "three agents") goes stale
# silently on every restructure, because prose isn't testable. This makes it
# testable: scripts/gen-task-table.sh derives the truth from the task files
# and fails on any doc still claiming the old shape.
if bash "$ROOT/scripts/gen-task-table.sh" --check >/dev/null 2>&1; then
  pass
else
  fail "docs contradict the real agent/task topology (run: bash scripts/gen-task-table.sh --check)"
fi

# --- 1f. every task file must have a schedule, and none may collide --------
# Two tasks on the same cron minute start two agent containers at once. On a
# 16 GB host that contends with Docker, the sandbox VM, Postgres and the
# local model, so collisions are a resource bug, not a style nit.
MISSING_SCHED=0
for md in "$ROOT"/*/*/ai.nanoco.nanoclaw/tasks/*.md; do
  grep -q '^schedule:' "$md" || { MISSING_SCHED=1; echo "  no schedule: $md"; }
done
[ "$MISSING_SCHED" -eq 0 ] && pass || fail "task file(s) missing a schedule: line"

# Comparing schedule STRINGS is not enough, and this bit us: `5 */3 * * *`
# and `5 15 * * 1` are different strings that both fire at 15:05 on Mondays,
# and `7,22,37,52 * * * *` silently claims four minutes of every hour. Two
# real collisions hid behind the string check. So expand every field and
# compare actual firing slots across minute x hour x day-of-week.
COLLIDE=$(python3 - "$ROOT" <<'PY' 2>/dev/null || echo "SKIP"
import glob, re, sys, collections
root = sys.argv[1]
def expand(f, lo, hi):
    out = set()
    for part in f.split(','):
        if part == '*':
            out |= set(range(lo, hi + 1)); continue
        m = re.fullmatch(r'\*/(\d+)', part)
        if m:
            out |= {v for v in range(lo, hi + 1) if (v - lo) % int(m.group(1)) == 0}; continue
        m = re.fullmatch(r'(\d+)-(\d+)', part)
        if m:
            out |= set(range(int(m.group(1)), int(m.group(2)) + 1)); continue
        try: out.add(int(part))
        except ValueError: pass
    return out
fires = collections.defaultdict(set)
for md in glob.glob(root + '/*/*/ai.nanoco.nanoclaw/tasks/*.md'):
    m = re.search(r'^schedule:\s*"([^"]+)"', open(md).read(), re.M)
    if not m: continue
    parts = m.group(1).split()
    if len(parts) != 5: continue
    mi, ho, _dom, _mon, dow = parts
    name = md.split('/')[-1][:-3]
    for a in expand(mi, 0, 59):
        for b in expand(ho, 0, 23):
            for c in expand(dow, 0, 6):
                fires[(a, b, c)].add(name)
seen, out = set(), []
for slot, names in sorted(fires.items()):
    if len(names) > 1:
        key = tuple(sorted(names))
        if key in seen: continue
        seen.add(key)
        out.append("min=%02d hr=%02d dow=%d -> %s" % (slot[0], slot[1], slot[2], ", ".join(sorted(names))))
print("\n".join(out))
PY
)
if [ "$COLLIDE" = "SKIP" ]; then
  # No python3 in this image — fall back to the weaker string check rather
  # than silently asserting nothing.
  DUPE=$(grep -h '^schedule:' "$ROOT"/*/*/ai.nanoco.nanoclaw/tasks/*.md | sort | uniq -d)
  if [ -z "$DUPE" ]; then pass; else fail "two tasks share a cron schedule string: $DUPE"; fi
elif [ -z "$COLLIDE" ]; then
  pass
else
  printf '  %s\n' "$COLLIDE"
  fail "two or more tasks fire in the same minute — on a 16 GB host that starts multiple agent containers at once"
fi

# --- 1g. no task may reference ANOTHER agent's plugin-data ----------------
# Each agent sees only its own /workspace/agent/plugin-data/<its-name>/. A
# path naming a different agent's dir is not a slow failure, it is a
# permanently dead task: the file is simply never there.
#
# This shipped three times at once. `docs-gap-review` read the lead's
# question-ledger from the coding agent's dir (and its own test fixture seeded
# the same wrong path, so the suite agreed with the bug); `social-metrics-snapshot`
# appended the follower series into marketing's dir; `health-check` watched an
# owner-instruction ledger only the lead writes. Two of the three were
# append-only ledgers, where a silent miss is unrecoverable data loss.
#
# Checked on BOTH sides: the gate scripts and the task prompts, because the
# prompt is what tells the agent where to write.
agent_of() {
  case "$1" in
    support)     echo "community-support";;
    local)       echo "community-local";;
    engineering) echo "community-coding";;
    marketing)   echo "community-marketing";;
  esac
}
dir_of() {
  case "$1" in
    support)     echo "support/community-support";;
    local)       echo "local/community-local";;
    engineering) echo "engineering/community-coding";;
    marketing)   echo "marketing/community-marketing";;
  esac
}
CROSS=0
for group in support local engineering marketing; do
  own=$(agent_of "$group")
  gdir=$(dir_of "$group")
  for f in "$ROOT/scripts/tasks/$group"/*.sh "$ROOT/$gdir"/ai.nanoco.nanoclaw/tasks/*.md; do
    [ -f "$f" ] || continue
    for other in community-support community-local community-coding community-marketing; do
      [ "$other" = "$own" ] && continue
      if grep -q "plugin-data/$other" "$f" 2>/dev/null; then
        echo "  cross-agent path: ${f#"$ROOT"/} (owned by $own) references plugin-data/$other"
        CROSS=1
      fi
    done
  done
done
[ "$CROSS" -eq 0 ] && pass || fail "task(s) reference another agent's plugin-data — those paths are never readable"

# --- 1h. sub-agent tasks must report through the lead, never to the owner --
# Every sub-agent is headless: its only outbound path is the `parent`
# destination to the lead, which relays to the owner DM. A sub-agent task that
# tells the agent to "send the owner" a report is asking for a route that does
# not exist, so the report reaches nobody.
#
# This shipped in three of the local agent's tasks at once — health-check's
# proof-of-life heartbeat, workspace-backup's failure report, and
# unanswered-watch's urgent security flag. All three are exactly the messages
# you cannot afford to lose, which is what makes this worth a hard gate rather
# than a review habit.
#
# Lead-owned tasks are exempt: the lead HAS the owner DM, so addressing the
# owner is correct for them.
OWNER_DIRECT=0
for group in local engineering marketing; do
  gdir=$(dir_of "$group")
  for md in "$ROOT/$gdir"/ai.nanoco.nanoclaw/tasks/*.md; do
    [ -f "$md" ] || continue
    # Imperative constructions only, and never a line that also names the lead
    # — "hand it to your lead marked for the owner" is the CORRECT phrasing and
    # must not trip this. Likewise "you have no owner DM" is the rule itself.
    if hits=$(grep -nEi 'send the owner|tell the owner|DM the owner|report [^.]{0,24}to the owner|flag [^.]{0,24}to the owner' "$md" \
              | grep -vi 'your lead\|no owner DM'); then
      echo "  direct-to-owner in a sub-agent task: ${md#"$ROOT"/}"
      printf '    %s\n' "$hits"
      OWNER_DIRECT=1
    fi
  done
done
[ "$OWNER_DIRECT" -eq 0 ] && pass || fail "sub-agent task(s) address the owner directly — they have no owner DM; route via the lead"

# --- 2. behavioral: single-line valid JSON contract ------------------------
# Each script runs in a sandbox dir with plugin-data pre-seeded per scenario.
# assert_gate <script> <scenario-name> <expected-wakeAgent|any> <config-env-content>
assert_gate() {
  local sh="$1" name="$2" expect="$3" cfg="$4"
  local sandbox; sandbox=$(mktemp -d)
  local sname; sname=$(basename "$sh" .sh)
  local fixdir="$ROOT/scripts/test/fixtures/$sname"
  mkdir -p "$sandbox/bin" "$sandbox/plugin-data/community-support" \
           "$sandbox/plugin-data/community-coding" "$sandbox/plugin-data/community-marketing" \
           "$sandbox/plugin-data/community-local"
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
  for g in community-support community-coding community-marketing community-local; do
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
           "$sandbox/plugin-data/community-coding" "$sandbox/plugin-data/community-marketing" \
           "$sandbox/plugin-data/community-local"
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
  for g in community-support community-coding community-marketing community-local; do
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
# Two local gates are deliberately excluded: health-check isn't config-gated
# (it wakes on its own first-run heartbeat, asserted separately below) and
# workspace-backup requires a real /workspace/agent git checkout rather than
# a config key, so "unconfigured" isn't a meaningful state for it.
for sh in "$ROOT"/scripts/tasks/engineering/*.sh "$ROOT"/scripts/tasks/marketing/*.sh \
          "$ROOT"/scripts/tasks/local/*.sh \
          "$ROOT"/scripts/tasks/support/release-announcement-watch.sh; do
  case "$(basename "$sh")" in
    health-check.sh|workspace-backup.sh) continue;;
  esac
  assert_gate "$sh" "unconfigured" "false" ""
done

# Fetch failure with config set: gates that watch external state must WAKE
# (a broken fetch must never read as a quiet day). The mock curl exits 22
# for every URL because no fixtures matched.
assert_gate "$ROOT/scripts/tasks/engineering/security-advisory-sweep.sh" \
  "fetch-fails-must-wake" "true" 'COMMUNITY_REPOS="acme/demo"'
assert_gate "$ROOT/scripts/tasks/local/dev-metrics-report.sh" \
  "fetch-fails-must-wake" "true" 'COMMUNITY_REPOS="acme/demo"'
assert_gate "$ROOT/scripts/tasks/local/good-first-issue-health.sh" \
  "fetch-fails-must-wake" "true" 'COMMUNITY_REPOS="acme/demo"'
assert_gate "$ROOT/scripts/tasks/support/release-announcement-watch.sh" \
  "fetch-fails-must-wake" "true" 'COMMUNITY_REPOS="acme/demo"'
assert_gate "$ROOT/scripts/tasks/local/draft-cleanup.sh" \
  "fetch-fails-must-wake" "true" 'CONTENT_REPO="acme/demo"'
assert_gate "$ROOT/scripts/tasks/engineering/github-ops-triage.sh" \
  "fetch-fails-must-wake" "true" 'COMMUNITY_REPOS="acme/demo"'
assert_gate "$ROOT/scripts/tasks/support/daily-github-triage.sh" \
  "fetch-fails-must-wake" "true" 'COMMUNITY_REPOS="acme/demo"'

# health-check: no config needed; on a healthy fresh box the only wake
# reason is the first-run weekly heartbeat.
assert_gate "$ROOT/scripts/tasks/local/health-check.sh" "first-run-heartbeat" "true" ""

# repo-mirror-sync: a nonexistent repo is a real clone failure (no mock
# needed — git's own error against a real host is the test).
assert_gate "$ROOT/scripts/tasks/local/repo-mirror-sync.sh" \
  "nonexistent-repo-clone-must-wake" "true" 'MIRROR_REPOS="acme/this-repo-does-not-exist-xyz-12345"'

# --- 2c. success-path assertions -------------------------------------------
# These check the SHAPE the task prompts actually read. A renamed or dropped
# field here is a broken task even though the gate still emits valid JSON and
# the right wakeAgent — which is exactly what the failure-only tests miss.

# dev-metrics-report: every field its prompt references, in the nesting the
# prompt describes. `count` (14) deliberately exceeds the listed prs (2) so
# the "N approved PRs waiting, oldest 10 listed" truncation path is covered.
assert_scenario "$ROOT/scripts/tasks/local/dev-metrics-report.sh" dev-metrics-full true \
  '.data.today["acme/demo"] as $t
   | ($t.stars == 937) and ($t.forks == 558)
     and ($t.open_issues == 42) and ($t.open_prs == 7)
     and ($t.releases[0].downloads == 1000)
     and ($t.awaiting_first_response.issues == 5)
     and ($t.awaiting_first_response.oldest_issue_since == "2026-06-01T00:00:00Z")
     and (.data.degraded_repos | length == 0)
     and (($t | has("closed_prs_30d")) | not)
     and ((.data | has("ready_to_merge")) | not)
     and ((.data | has("contribution_concentration")) | not)' \
  'COMMUNITY_REPOS="acme/demo"'
# The three `has(...) | not` assertions are the split's regression test: those
# fields moved to ready-to-merge and contributor-health-review, so if one
# reappears here the split has been partially reverted and two tasks are
# reporting the same thing.

# ready-to-merge: 14 approved PRs waiting with only the 2 oldest listed, so
# the truncation path is covered. First run has no prior set, so every PR is
# "newly ready" and the gate must wake.
assert_scenario "$ROOT/scripts/tasks/local/ready-to-merge.sh" ready-to-merge-waiting true \
  '(.data.status == "ready")
   and (.data.total == 14)
   and (.data.repos[0].truncated == true)
   and (.data.repos[0].prs | length == 2)
   and (.data.repos[0].prs[0].author == "contribA")
   and (.data.newly_ready | length == 2)
   and (.data.resurfaced == false)
   and (.data.degraded_repos | length == 0)' \
  'COMMUNITY_REPOS="acme/demo"'

# ready-to-merge, run 2: identical approved set, so the "changed" gate must
# SUPPRESS rather than re-report the same PRs the next morning. This is the
# difference between useful and nagging, and it only exists from run 2 on.
assert_scenario "$ROOT/scripts/tasks/local/ready-to-merge.sh" ready-to-merge-waiting false \
  '(.data.resurfaced == true) and (.data.newly_ready | length == 0)' \
  'COMMUNITY_REPOS="acme/demo"' 2

# contributor-health-review: the Reviewer's half of the split. Asserts the
# histogram maths the script does so the agent never has to — 20/6/4 across
# three authors is a 67% top-author share and exactly two candidates at the
# 5-merged floor. first_run must be true (no history to diff yet) and must
# wake, because a baseline is worth one report.
assert_scenario "$ROOT/scripts/tasks/engineering/contributor-health-review.sh" contributor-health-move true \
  '.data.repos[0] as $r
   | ($r.closed_prs_30d.merged == 20)
     and ($r.closed_prs_30d.unmerged == 4)
     and ($r.closed_prs_30d.unmerged_ratio == 0.17)
     and ($r.concentration.distinct_authors_90d == 3)
     and ($r.concentration.top_author == "maintainer")
     and ($r.concentration.top_author_share_pct == 67)
     and ($r.concentration.candidates | length == 2)
     and (.data.first_run == true)
     and (.data.degraded_repos | length == 0)' \
  'COMMUNITY_REPOS="acme/demo"'

# contributor-health-review, run 2: byte-identical numbers, so nothing
# "moved" and the quarterly heartbeat has not elapsed — must suppress.
assert_scenario "$ROOT/scripts/tasks/engineering/contributor-health-review.sh" contributor-health-move false \
  '(.data.quiet_heartbeat == true) and (.data.moved | length == 0) and (.data.first_run == false)' \
  'COMMUNITY_REPOS="acme/demo"' 2

# dev-metrics-report, run 2: nothing changed between runs, and no approved PRs
# this time, so the wake gate must SUPPRESS. Untestable without multi-run.
assert_scenario "$ROOT/scripts/tasks/local/dev-metrics-report.sh" dev-metrics-quiet false \
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
assert_scenario "$ROOT/scripts/tasks/local/good-first-issue-health.sh" gfi-stale true \
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
