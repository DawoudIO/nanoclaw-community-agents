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
#   - Fixtures cover a handful of scenarios, not every gate. Uncovered on the
#     success path: security-advisory-sweep, github-ops-triage,
#     weekly-identity-integrity-check.
#   - project-health's ledger step (orphan branch creation, read-back of
#     today's row, unpushed-commit recovery, refusal to force) is verified
#     against a real local bare repo rather than mocked; see 2d. Its social
#     half (the model reading follower pages) is a prompt, not a script, and
#     is not covered here.
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

# --- 1d2. task frontmatter must NOT carry unrecognized keys ----------------
# History here, because the wrong direction was shipped once already: a prior
# pass added `name:`/`status: paused` to every task file on the theory that
# the platform needed them to create tasks paused. That was never verified
# against the real platform, and a real install on 2026-08-22 confirmed it
# was wrong — those exact keys caused validator errors that blocked template
# stamping entirely, and had to be removed (commit 4a978e5) before anything
# would stamp. Tasks are apparently paused/enabled by a mechanism outside
# this frontmatter; `schedule` and `script` are the only keys a task file
# should declare. This check now guards the OPPOSITE regression — don't
# reintroduce `name`/`status` (or any other unrecognized key) without first
# confirming against a real stamp attempt that the platform accepts it.
BADKEY=0
for md in "$ROOT"/*/*/ai.nanoco.nanoclaw/tasks/*.md; do
  if awk '/^---$/{c++; next} c==1 && /^[a-zA-Z_]+:/ && $1 !~ /^(schedule:|script:)/ {print; bad=1} END{exit !bad}' "$md" >/tmp/badkeys.$$ 2>/dev/null; then
    echo "  unrecognized frontmatter key(s) in ${md#"$ROOT"/}: $(cat /tmp/badkeys.$$ | tr '\n' ' ')"
    BADKEY=1
  fi
  rm -f /tmp/badkeys.$$
done
[ "$BADKEY" -eq 0 ] && pass || fail "task file(s) declare a frontmatter key other than schedule/script — verify against a real stamp attempt before adding one"

# --- 1e. docs must not contradict the real topology ------------------------
# Prose that hand-restates counts ("18 tasks", "four agents") goes stale
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
# This is worth a hard gate because it has shipped repeatedly, and once with
# the test fixture seeding the same wrong path, so the suite agreed with the
# bug. Two of those cases were append-only ledgers, where a silent miss is
# unrecoverable data loss rather than a late report.
#
# Checked on BOTH sides: the gate scripts and the task prompts, because the
# prompt is what tells the agent where to write.
agent_of() {
  case "$1" in
    manager)     echo "community-manager";;
    helper)      echo "community-helper";;
  esac
}
dir_of() {
  case "$1" in
    manager)     echo "opensource/community-manager";;
    helper)      echo "opensource/community-helper";;
  esac
}
CROSS=0
for group in manager helper; do
  own=$(agent_of "$group")
  gdir=$(dir_of "$group")
  for f in "$ROOT/scripts/tasks/$group"/*.sh "$ROOT/$gdir"/ai.nanoco.nanoclaw/tasks/*.md; do
    [ -f "$f" ] || continue
    for other in community-manager community-helper; do
      [ "$other" = "$own" ] && continue
      if grep -q "plugin-data/$other" "$f" 2>/dev/null; then
        echo "  cross-agent path: ${f#"$ROOT"/} (owned by $own) references plugin-data/$other"
        CROSS=1
      fi
    done
  done
done
[ "$CROSS" -eq 0 ] && pass || fail "task(s) reference another agent's plugin-data — those paths are never readable"

# --- 1h. sub-agent tasks must report through the manager, never to the owner --
# Every sub-agent is headless: its only outbound path is the `parent`
# destination to the manager, which relays to the owner DM. A sub-agent task that
# tells the agent to "send the owner" a report is asking for a route that does
# not exist, so the report reaches nobody.
#
# This has shipped in several tasks at once before, and always in the ones you
# can least afford to lose — a failure report, an urgent security flag. That
# is what makes it worth a hard gate rather than a review habit.
#
# Manager-owned tasks are exempt: the manager HAS the owner DM, so addressing the
# owner is correct for them.
OWNER_DIRECT=0
for group in helper; do
  gdir=$(dir_of "$group")
  for md in "$ROOT/$gdir"/ai.nanoco.nanoclaw/tasks/*.md; do
    [ -f "$md" ] || continue
    # Imperative constructions only, and never a line that also names the manager
    # — "hand it to your manager marked for the owner" is the CORRECT phrasing and
    # must not trip this. Likewise "you have no owner DM" is the rule itself.
    if hits=$(grep -nEi 'send the owner|tell the owner|DM the owner|report [^.]{0,24}to the owner|flag [^.]{0,24}to the owner' "$md" \
              | grep -vi 'your manager\|no owner DM'); then
      echo "  direct-to-owner in a sub-agent task: ${md#"$ROOT"/}"
      printf '    %s\n' "$hits"
      OWNER_DIRECT=1
    fi
  done
done
[ "$OWNER_DIRECT" -eq 0 ] && pass || fail "sub-agent task(s) address the owner directly — they have no owner DM; route via the manager"

# --- 1i. single voice: no sub-agent task may instruct a public comment -----
# The Helper now opens pull requests (security patches, docs PRs), which is a
# deliberate exception. The line it must not cross is CONVERSATION: commenting
# on an issue or PR is the manager's job, and the real control is that the
# Helper's token has Issues *read* only, so PR comments are impossible.
#
# This guards the prompt side of that, because a prompt telling an agent to
# comment would produce silent 403s rather than an obvious failure — and would
# be an argument for widening the token, which is exactly the wrong fix.
COMMENTERS=0
for group in helper; do
  gdir=$(dir_of "$group")
  for md in "$ROOT/$gdir"/ai.nanoco.nanoclaw/tasks/*.md; do
    [ -f "$md" ] || continue
    if hits=$(grep -nEi 'post a (public )?comment|comment on the (issue|pr|pull)|reply (on|to) the (issue|pr|pull)|leave a comment' "$md"               | grep -viE 'never|not |do not|cannot|forbidden|instead of'); then
      echo "  public-comment instruction in a sub-agent task: ${md#"$ROOT"/}"
      printf '    %s\n' "$hits"
      COMMENTERS=1
    fi
  done
done
[ "$COMMENTERS" -eq 0 ] && pass || fail "sub-agent task(s) instruct posting a public comment — conversation is the manager's, and their tokens cannot do it anyway"

# --- 1j. every `references/...md` a prompt points at must exist ------------
# Moving craft rules out of a prompt into a skill reference cuts per-wake cost,
# but it makes the POINTER load-bearing: a wrong path doesn't error, the agent
# just never reads the guidance and quietly does a worse job. Nothing else in
# this suite would catch that.
BADREF=0
for md in "$ROOT"/*/*/ai.nanoco.nanoclaw/tasks/*.md "$ROOT"/*/*/ai.nanoco.nanoclaw/context/instructions.md; do
  [ -f "$md" ] || continue
  tpl=$(cd "$(dirname "$md")" && cd .. && pwd)          # .../ai.nanoco.nanoclaw
  root=$(dirname "$tpl")                                 # the template root
  for ref in $(grep -ohE '(references|skills)/[A-Za-z0-9._/-]+\.md' "$md" | sort -u); do
    found=0
    for cand in "$root/$ref" "$root"/skills/*/"$ref" "$root/skills/$ref"; do
      [ -f "$cand" ] && { found=1; break; }
    done
    [ "$found" -eq 1 ] || { echo "  dangling reference in ${md#"$ROOT"/}: $ref"; BADREF=1; }
  done
done
[ "$BADREF" -eq 0 ] && pass || fail "task prompt(s) point at a reference file that does not exist — the agent silently never reads it"

# Render a fixture directory into the sandbox, substituting date placeholders.
#
# WHY: a fixture with a hardcoded date is tested against a gate that compares
# against `now`, so the fixture silently changes meaning as real time passes.
# This bit (in a since-removed staleness gate): a fixture issue dated
# 2026-08-20 was deliberately NOT stale when written, quietly crossed the
# 14-day threshold months later, and the test asserted one stale issue and
# found two. Placeholders keep a fixture's
# *meaning* fixed instead of its literal value.
#
#   __RECENT_ISO__  — 2 days ago: inside every freshness window in this kit
#   __STALE_ISO__   — 120 days ago: outside every staleness window
#   __D30__         — 30 days ago as YYYY-MM-DD: the exact `merged:>=` date
#                     project-health puts in its 30-day search URL, so a
#                     routes.txt pattern can tell that query apart from the
#                     7- and 90-day ones that differ only by date
render_fixtures() {
  local src="$1" dst="$2" recent stale d30
  [ -d "$src" ] || return 0
  mkdir -p "$dst"
  recent=$(date -u -v-2d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)
  stale=$(date -u -v-120d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '120 days ago' +%Y-%m-%dT%H:%M:%SZ)
  d30=$(date -u -v-30d +%Y-%m-%d 2>/dev/null || date -u -d '30 days ago' +%Y-%m-%d)
  for f in "$src"/*; do
    [ -f "$f" ] || continue
    sed -e "s#__RECENT_ISO__#$recent#g" -e "s#__STALE_ISO__#$stale#g" -e "s#__D30__#$d30#g" "$f" > "$dst/$(basename "$f")"
  done
}

# --- 2. behavioral: single-line valid JSON contract ------------------------
# Each script runs in a sandbox dir with plugin-data pre-seeded per scenario.
# assert_gate <script> <scenario-name> <expected-wakeAgent|any> <config-env-content>
assert_gate() {
  local sh="$1" name="$2" expect="$3" cfg="$4"
  local sandbox; sandbox=$(mktemp -d)
  local sname; sname=$(basename "$sh" .sh)
  local fixdir="$sandbox/.fixtures"
  render_fixtures "$ROOT/scripts/test/fixtures/$sname" "$fixdir"
  mkdir -p "$sandbox/bin" "$sandbox/plugin-data/community-manager" \
           "$sandbox/plugin-data/community-helper"
  # fake curl: first URL-ish arg is matched against fixture patterns
  cat > "$sandbox/bin/curl" <<MOCK
#!/bin/bash
url=""
wants_code=false
for a in "\$@"; do
  case "\$a" in https://*) url="\$a";; esac
  case "\$a" in *%{http_code}*) wants_code=true;; esac
done
if [ -d "$fixdir" ]; then
  while IFS='|' read -r pat file; do
    [ -z "\$pat" ] && continue
    case "\$url" in *"\$pat"*)
      cat "$fixdir/\$file"
      # -w '%{http_code}' callers read the trailing status line themselves
      # and don't rely on curl's exit code (unlike -f callers) — append it
      # on a match, and on no-match too (rather than the -f-style exit 22),
      # so a script testing for a real HTTP status (e.g. 404 vs 200) can be
      # exercised here.
      \$wants_code && printf '\n200'
      exit 0
    ;;
    esac
  done < "$fixdir/routes.txt"
fi
if \$wants_code; then printf '\n000'; exit 0; fi
exit 22
MOCK
  chmod +x "$sandbox/bin/curl"
  for g in community-manager community-helper; do
    [ -n "$cfg" ] && printf '%s\n' "$cfg" > "$sandbox/plugin-data/$g/config.env"
  done
  local out
  out=$(cd "$sandbox" && PATH="$sandbox/bin:$PATH" \
        bash <(sed -e "s#/workspace/agent/plugin-data#$sandbox/plugin-data#g" "$sh") 2>/dev/null | tail -1)
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
  local fixdir="$sandbox/.fixtures"
  render_fixtures "$ROOT/scripts/test/fixtures/$fixture" "$fixdir"
  mkdir -p "$sandbox/bin" "$sandbox/plugin-data/community-manager" \
           "$sandbox/plugin-data/community-helper"
  cat > "$sandbox/bin/curl" <<MOCK
#!/bin/bash
url=""
wants_code=false
for a in "\$@"; do
  case "\$a" in https://*) url="\$a";; esac
  case "\$a" in *%{http_code}*) wants_code=true;; esac
done
if [ -f "$fixdir/routes.txt" ]; then
  while IFS='|' read -r pat file code; do
    [ -z "\$pat" ] && continue
    case "\$url" in *"\$pat"*)
      [ -n "\$file" ] && [ -f "$fixdir/\$file" ] && cat "$fixdir/\$file"
      \$wants_code && printf '\n%s' "\${code:-200}"
      exit 0
    ;;
    esac
  done < "$fixdir/routes.txt"
fi
if \$wants_code; then printf '\n000'; exit 0; fi
exit 22
MOCK
  chmod +x "$sandbox/bin/curl"
  for g in community-manager community-helper; do
    [ -n "$cfg" ] && printf '%s\n' "$cfg" > "$sandbox/plugin-data/$g/config.env"
  done
  [ -n "$seed" ] && ( cd "$sandbox" && SANDBOX="$sandbox" bash -c "$seed" )
  local out i
  for i in $(seq 1 "$runs"); do
    out=$(cd "$sandbox" && PATH="$sandbox/bin:$PATH" \
          bash <(sed -e "s#/workspace/agent/plugin-data#$sandbox/plugin-data#g" "$sh") 2>/dev/null | tail -1)
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
for sh in "$ROOT"/scripts/tasks/helper/*.sh; do
  assert_gate "$sh" "unconfigured" "false" ""
done

# Fetch failure with config set: gates that watch external state must WAKE
# (a broken fetch must never read as a quiet day). The mock curl exits 22
# for every URL because no fixtures matched.
assert_gate "$ROOT/scripts/tasks/helper/security-advisory-sweep.sh" \
  "fetch-fails-must-wake" "true" 'COMMUNITY_REPOS="acme/demo"'
assert_gate "$ROOT/scripts/tasks/helper/github-ops-triage.sh" \
  "fetch-fails-must-wake" "true" 'COMMUNITY_REPOS="acme/demo"'
# project-health: even with the social wake switched off, a day where every
# GitHub fetch failed must wake — degraded_repos overrides SOCIAL_DAILY=false.
assert_gate "$ROOT/scripts/tasks/helper/project-health.sh" \
  "fetch-fails-must-wake" "true" 'COMMUNITY_REPOS="acme/demo"
SOCIAL_DAILY=false'

# --- 2c. success-path assertions -------------------------------------------
# These check the SHAPE the task prompts actually read. A renamed or dropped
# field here is a broken task even though the gate still emits valid JSON and
# the right wakeAgent — which is exactly what the failure-only tests miss.

# project-health: the one metrics task. Its mode is decided by the weekday,
# so the tests pin HEALTH_POST_DOW to "today" or "not today" rather than
# passing or failing depending on which day the suite happens to run.
TODAY_DOW=$(date -u +%w); NOT_TODAY_DOW=$(( (TODAY_DOW + 1) % 7 ))

# collect day: every GitHub field the prompt reads, in the nesting it reads
# it; everything post-only (health, nudges, traffic) must be empty even with
# GA4 configured, because collect day is the cheap wake — nothing to compose.
assert_scenario "$ROOT/scripts/tasks/helper/project-health.sh" project-health true \
  '.data.repos[0] as $r
   | (.data.mode == "collect")
     and ($r.repo == "acme/demo")
     and ($r.stars == 937) and ($r.forks == 558)
     and ($r.open_issues == 42) and ($r.open_prs == 7)
     and ($r.releases[0].downloads == 1000)
     and ($r.awaiting_issues == 5)
     and ($r.awaiting_oldest == "2026-06-01T00:00:00Z")
     and ($r.new_contributors_7d == [])
     and ($r.health == null)
     and (.data.nudges == []) and (.data.traffic == [])
     and (.data.degraded_repos | length == 0)
     and (.data.ledger.status == "not-configured")' \
  "COMMUNITY_REPOS=\"acme/demo\"
GA4_PROPERTIES=\"main:123\"
HEALTH_POST_DOW=$NOT_TODAY_DOW"

# collect day, SOCIAL_DAILY=false: THE 0-TOKEN ASSERTION. With no social
# row to append and nothing to post, the run must not wake at all — the CSV
# rows are written by bash either way.
assert_scenario "$ROOT/scripts/tasks/helper/project-health.sh" project-health false \
  '(.data.mode == "collect") and (.data.degraded_repos | length == 0)' \
  "COMMUNITY_REPOS=\"acme/demo\"
SOCIAL_DAILY=false
HEALTH_POST_DOW=$NOT_TODAY_DOW"

# A repo string that is not owner/name never reaches a URL, a JSON object or
# a CSV row: it is recorded as bad-config, counts as degraded, and therefore
# wakes the agent even on a SOCIAL_DAILY=false day. The good repo beside it
# still gets its row. Also proves config.env is parsed, not sourced: the
# value would otherwise be a shell word boundary.
assert_scenario "$ROOT/scripts/tasks/helper/project-health.sh" project-health true \
  '(.data.degraded_repos == ["acme/demo?per_page=100"]) and ([.data.repos[] | select(.status == "bad-config")] | length == 1) and ([.data.repos[] | select(.repo == "acme/demo" and .stars == 937)] | length == 1)' \
  "COMMUNITY_REPOS=\"acme/demo acme/demo?per_page=100\"
SOCIAL_DAILY=false
HEALTH_POST_DOW=$NOT_TODAY_DOW"

# collect day, run 2: run 1 seeded the known-contributors list from
# /contributors (maintainer1, maintainer2, olddev) and reported nothing —
# seeding is not "new". Run 2 diffs the week's merged-PR authors against it
# and must surface exactly the three names that weren't there.
assert_scenario "$ROOT/scripts/tasks/helper/project-health.sh" project-health true \
  '(.data.repos[0].new_contributors_7d | sort) == ["contribA","contribB","maintainer"]' \
  "COMMUNITY_REPOS=\"acme/demo\"
HEALTH_POST_DOW=$NOT_TODAY_DOW" 2

# post day: the contributor-health maths the script does so the agent never
# has to — 20/6/4 merged across three authors is a 67% top-author share and
# exactly two candidates at the 5-merged floor; 4 unmerged of 24 closed is
# 0.17. GA4's three date ranges come back as current/previous_week/
# previous_month so WoW and MoM are GA4's own windows, not two CSV rows.
assert_scenario "$ROOT/scripts/tasks/helper/project-health.sh" project-health true \
  '.data.repos[0].health as $h
   | (.data.mode == "post")
     and ($h.merged_30d == 20) and ($h.unmerged_30d == 4)
     and ($h.unmerged_ratio == 0.17)
     and ($h.concentration.distinct_authors_90d == 3)
     and ($h.concentration.top_author == "maintainer")
     and ($h.concentration.top_author_share_pct == 67)
     and ($h.concentration.candidates | length == 2)
     and (.data.traffic[0].label == "main")
     and (.data.traffic[0].status == "ok")
     and (.data.traffic[0].current.activeUsers == 120)
     and (.data.traffic[0].previous_week.activeUsers == 100)
     and (.data.traffic[0].previous_month.sessions == 110)' \
  "COMMUNITY_REPOS=\"acme/demo\"
GA4_PROPERTIES=\"main:123\"
HEALTH_POST_DOW=$TODAY_DOW"

# post day, GA4 unreachable: the traffic entry must say so rather than
# vanish — a missing series and a failed fetch are different reports.
assert_scenario "$ROOT/scripts/tasks/helper/project-health.sh" project-health true \
  '(.data.traffic[0].status == "fetch-failed") and (.data.traffic[0].property_id == "999")' \
  "COMMUNITY_REPOS=\"acme/demo\"
GA4_PROPERTIES=\"999\"
HEALTH_POST_DOW=$TODAY_DOW" 1 \
  'sed -i.bak "/analyticsdata/d" "$SANDBOX/.fixtures/routes.txt"'

# posthog-weekly-review is removed for now (never got working end to end).
# If it comes back, restore this scenario: byte-identical insight results
# across two runs must suppress, and previous_result must be populated from
# history on run 2 — the exact bug the 28-day heartbeat fix addressed, since a
# 7-day heartbeat on a weekly cron made this assertion impossible to satisfy.

# docs-gap-review: pure local-file logic, previously the ONLY gate with no
# behavioral coverage at all. Ledger seeded with one topic 4× inside the
# 60-day window and one 2× — only the 3+ topic may surface.
assert_scenario "$ROOT/scripts/tasks/manager/docs-gap-review.sh" no-fixtures true \
  '(.data.status == "hot-topics")
   and (.data.topics | length == 1)
   and (.data.topics[0].topic == "csv-import-fails")
   and (.data.topics[0].count == 4)' \
  '' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ);
   echo date,topic,channel > "$D/question-ledger.csv";
   for i in 1 2 3 4; do echo "$NOW,csv-import-fails,#support" >> "$D/question-ledger.csv"; done;
   for i in 1 2; do echo "$NOW,how-to-backup,#support" >> "$D/question-ledger.csv"; done'

# docs-gap-review: a topic already proposed must not re-surface (the ack
# ledger is what stops the same docs page being proposed every week).
assert_scenario "$ROOT/scripts/tasks/manager/docs-gap-review.sh" no-fixtures false \
  '.data.status == "quiet"' '' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ);
   echo date,topic,channel > "$D/question-ledger.csv";
   for i in 1 2 3 4; do echo "$NOW,csv-import-fails,#support" >> "$D/question-ledger.csv"; done;
   echo "csv-import-fails" > "$D/docs-proposals-sent.txt"'

# owner-instruction-watch: the dropped-ack safety net the persona already
# claims exists (instructions.md says so) but nothing implemented before
# this task. Day one: no ledger yet must never look like a false-positive
# stale thread.
assert_scenario "$ROOT/scripts/tasks/manager/owner-instruction-watch.sh" no-fixtures false \
  '.data.status == "no-ledger-yet"' '' 1 \
  'true'

# A `received` with no closing event, past the 24h default, must surface —
# and the gist field's own comma must not corrupt the parse (the whole
# reason this ledger stays JSONL instead of the CSV default).
assert_scenario "$ROOT/scripts/tasks/manager/owner-instruction-watch.sh" no-fixtures true \
  '(.data.status == "stale-threads")
   and (.data.detail.count == 1)
   and (.data.detail.open[0].id == "1")' \
  '' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   OLD=$(date -u -d "@$(( $(date +%s) - 108000 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r $(( $(date +%s) - 108000 )) +%Y-%m-%dT%H:%M:%SZ);
   echo "{\"id\": 1, \"ts\": \"$OLD\", \"event\": \"received\", \"gist\": \"has, a comma, on purpose\"}" > "$D/owner-instructions.jsonl"'

# A closed thread (done/blocked/dropped) and a recent-but-open thread must
# both stay quiet — closing beats staleness, and staleness has a real floor.
assert_scenario "$ROOT/scripts/tasks/manager/owner-instruction-watch.sh" no-fixtures false \
  '.data.status == "quiet"' '' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   OLD=$(date -u -d "@$(( $(date +%s) - 108000 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r $(( $(date +%s) - 108000 )) +%Y-%m-%dT%H:%M:%SZ);
   RECENT=$(date -u -d "@$(( $(date +%s) - 3600 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r $(( $(date +%s) - 3600 )) +%Y-%m-%dT%H:%M:%SZ);
   {
     echo "{\"id\": 1, \"ts\": \"$OLD\", \"event\": \"received\", \"gist\": \"closed one\"}";
     echo "{\"id\": 1, \"ts\": \"$OLD\", \"event\": \"blocked\", \"gist\": \"waiting on owner\"}";
     echo "{\"id\": 2, \"ts\": \"$RECENT\", \"event\": \"received\", \"gist\": \"too new to flag\"}";
   } > "$D/owner-instructions.jsonl"'

# owner-tldr: the digest gate. Empty queue must NOT wake — a quiet day is the
# common case and must cost nothing.
assert_scenario "$ROOT/scripts/tasks/manager/owner-tldr.sh" no-fixtures false \
  '.data.status == "nothing-queued"' '' 1

# owner-tldr: three queued entries produce one digest, grouped by source.
assert_scenario "$ROOT/scripts/tasks/manager/owner-tldr.sh" no-fixtures true \
  '(.data.status == "digest-ready")
   and (.data.total == 3)
   and (.data.deferred_runs == 0)
   and (.data.misfiled_present == false)
   and ([.data.by_source[].source] | sort == ["helper","manager"])' '' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   printf "OWNER_TZ=\"UTC\"\nTLDR_LOCAL_HOUR=\"%s\"\n" "$(date -u +%-H)" > "$D/config.env";
   NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ);
   echo "{\"at\":\"$NOW\",\"source\":\"helper\",\"severity\":\"info\",\"line\":\"metrics history published\"}" >> "$D/digest-queue.jsonl";
   echo "{\"at\":\"$NOW\",\"source\":\"manager\",\"severity\":\"info\",\"line\":\"release announced\"}" >> "$D/digest-queue.jsonl";
   echo "{\"at\":\"$NOW\",\"source\":\"helper\",\"severity\":\"attention\",\"line\":\"advisory needs a look\"}" >> "$D/digest-queue.jsonl"'

# owner-tldr, RATE-LIMIT SAFETY — the assertion that matters most here.
# Simulates the exact state a spent usage window leaves behind: a .processing
# batch the agent never got budget to post, PLUS new entries that arrived
# while it was blocked. The gate must FOLD them together (2 + 1 = 3) and
# report the delay, never drop either side. A usage limit must delay the
# digest, not lose it.
assert_scenario "$ROOT/scripts/tasks/manager/owner-tldr.sh" no-fixtures true \
  '(.data.total == 3) and (.data.deferred_runs == 1)' '' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   printf "OWNER_TZ=\"UTC\"\nTLDR_LOCAL_HOUR=\"%s\"\n" "$(date -u +%-H)" > "$D/config.env";
   NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ);
   echo "{\"at\":\"$NOW\",\"source\":\"local\",\"severity\":\"info\",\"line\":\"queued before the limit hit\"}" >> "$D/digest-queue.processing.jsonl";
   echo "{\"at\":\"$NOW\",\"source\":\"local\",\"severity\":\"info\",\"line\":\"also before\"}" >> "$D/digest-queue.processing.jsonl";
   echo "{\"at\":\"$NOW\",\"source\":\"helper\",\"severity\":\"attention\",\"line\":\"arrived while rate-limited\"}" >> "$D/digest-queue.jsonl"'

# owner-tldr, REGRESSION for the escalated-send-suppresses-next-routine-slot
# bug. Seeds a `digest-last-sent` timestamp 8 hours ago — as an escalated
# send the previous evening would leave — with NO routine-date marker (a
# fresh install's state). It is now the routine hour. The old logic checked
# `hours-since-any-send >= 20`, which 8 fails, silently swallowing this
# morning's routine digest. The routine slot must fire regardless of how
# recently an escalated send happened, because it answers a different
# question (today's calendar date, not an hours-since counter).
assert_scenario "$ROOT/scripts/tasks/manager/owner-tldr.sh" no-fixtures true \
  '(.data.status == "digest-ready") and (.data.trigger == "routine")' '' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   printf "OWNER_TZ=\"UTC\"\nTLDR_LOCAL_HOUR=\"%s\"\n" "$(date -u +%-H)" > "$D/config.env";
   printf "%s" "$(( $(date +%s) - 8*3600 ))" > "$D/digest-last-sent";
   NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ);
   echo "{\"at\":\"$NOW\",\"source\":\"local\",\"severity\":\"info\",\"line\":\"routine item\"}" >> "$D/digest-queue.jsonl"'

# owner-tldr: an `attention` item must be HELD while the owner is asleep. The
# seed puts local time 6 hours BEFORE the digest hour — i.e. the middle of the
# night — so the 15-hour waking window is closed. Escalating here would spend a
# wake to deliver something that is read at 07:00 anyway, which the routine
# digest would have carried for free.
assert_scenario "$ROOT/scripts/tasks/manager/owner-tldr.sh" no-fixtures false \
  '(.data.status == "held") and (.data.owner_awake == false) and (.data.attention_pending == 1)' '' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   printf "OWNER_TZ=\"UTC\"\nTLDR_LOCAL_HOUR=\"%s\"\n" "$(( ($(date -u +%-H) + 6) % 24 ))" > "$D/config.env";
   NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ);
   echo "{\"at\":\"$NOW\",\"source\":\"local\",\"severity\":\"attention\",\"line\":\"we may be blind\"}" >> "$D/digest-queue.jsonl"'

# owner-tldr: an unresolvable timezone must be REPORTED, not silently treated
# as UTC. Verified behaviour: `date` falls back to UTC without complaint, so an
# owner told "07:00 local" would quietly get 07:00 UTC instead.
assert_scenario "$ROOT/scripts/tasks/manager/owner-tldr.sh" no-fixtures any \
  '(.data.tz_resolved == false) and (.data.tz == "UTC")' '' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   printf "OWNER_TZ=\"Not/AZone\"\n" > "$D/config.env";
   NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ);
   echo "{\"at\":\"$NOW\",\"source\":\"local\",\"severity\":\"info\",\"line\":\"x\"}" >> "$D/digest-queue.jsonl"'

# owner-tldr: routine info items must be HELD outside the owner's chosen hour.
# This is the assertion that keeps the digest at one message a day instead of
# one per two-hour gate run. TLDR_HOUR is set 5 hours away in the seed so the
# routine tier cannot fire, and nothing is `attention`, so nothing escalates.
assert_scenario "$ROOT/scripts/tasks/manager/owner-tldr.sh" no-fixtures false \
  '(.data.status == "held") and (.data.pending == 2) and (.data.attention_pending == 0)' '' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   printf "OWNER_TZ=\"UTC\"\nTLDR_LOCAL_HOUR=\"%s\"\n" "$(( ($(date -u +%-H) + 5) % 24 ))" > "$D/config.env";
   NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ);
   echo "{\"at\":\"$NOW\",\"source\":\"local\",\"severity\":\"info\",\"line\":\"mirror ok\"}" >> "$D/digest-queue.jsonl";
   echo "{\"at\":\"$NOW\",\"source\":\"local\",\"severity\":\"info\",\"line\":\"backup ok\"}" >> "$D/digest-queue.jsonl"'

# owner-tldr: ...and the same items DO go out at the chosen hour.
assert_scenario "$ROOT/scripts/tasks/manager/owner-tldr.sh" no-fixtures true \
  '(.data.trigger == "routine") and (.data.total == 2)' '' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   printf "OWNER_TZ=\"UTC\"\nTLDR_LOCAL_HOUR=\"%s\"\n" "$(date -u +%-H)" > "$D/config.env";
   NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ);
   echo "{\"at\":\"$NOW\",\"source\":\"local\",\"severity\":\"info\",\"line\":\"mirror ok\"}" >> "$D/digest-queue.jsonl";
   echo "{\"at\":\"$NOW\",\"source\":\"local\",\"severity\":\"info\",\"line\":\"backup ok\"}" >> "$D/digest-queue.jsonl"'

# owner-tldr: an entry marked urgent should never be in the queue at all —
# urgent bypasses it. The gate flags it as a process failure.
assert_scenario "$ROOT/scripts/tasks/manager/owner-tldr.sh" no-fixtures true \
  '(.data.misfiled_present == true) and (.data.misfiled_urgent | length == 1)' '' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   printf "OWNER_TZ=\"UTC\"\nTLDR_LOCAL_HOUR=\"%s\"\n" "$(date -u +%-H)" > "$D/config.env";
   NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ);
   echo "{\"at\":\"$NOW\",\"source\":\"local\",\"severity\":\"urgent\",\"line\":\"should have bypassed\"}" >> "$D/digest-queue.jsonl";
   echo "{\"at\":\"$NOW\",\"source\":\"local\",\"severity\":\"attention\",\"line\":\"and something blind\"}" >> "$D/digest-queue.jsonl"'

# owner-tldr: a malformed line must not lose the batch or break the contract.
assert_scenario "$ROOT/scripts/tasks/manager/owner-tldr.sh" no-fixtures true \
  '.data.status == "queue-unparseable"' '' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   printf "not json at all\n" >> "$D/digest-queue.jsonl"'
# github-first-response: two brand-new unanswered items, but only ONE is past
# the 15-minute grace. The fresh one must NOT surface — replying 2 minutes
# after someone opens a PR reads as a bot, which is the whole reason the grace
# exists. A third item opened by the OWNER is present and must never surface:
# maintainers' own issues are not waiting for a first reply. Asserts the
# filter, not just the fetch.
assert_scenario "$ROOT/scripts/tasks/manager/github-first-response.sh" first-response-new true \
  '(.data.status == "needs-first-response")
   and (.data.count == 1)
   and (.data.items[0].number == 501)
   and (.data.items[0].type == "issue")
   and (.data.grace_minutes == 15)
   and (.data.degraded_repos | length == 0)' \
  'COMMUNITY_REPOS="acme/crm"'

# github-first-response: FOLLOW-UP coverage. Six threads with recent comments;
# exactly one has an outsider as the latest commenter, past grace, still open.
# Excluded on purpose: our own bot answered last (602), a maintainer answered
# last (603), CI's bot answered last (604), the thread is closed (605), the
# comment is inside the grace window (606). The new-item search returns
# nothing, so count==1 proves the follow-up path alone.
assert_scenario "$ROOT/scripts/tasks/manager/github-first-response.sh" first-response-followup true \
  '(.data.status == "needs-first-response")
   and (.data.count == 1)
   and (.data.followups == "enabled")
   and (.data.items[0].kind == "follow-up")
   and (.data.items[0].number == 601)
   and (.data.items[0].author == "newcomer2")
   and (.data.items[0].title == "Import fails on 7.7.0")
   and (.data.items[0].url | endswith("#issuecomment-12"))' \
  'COMMUNITY_REPOS="acme/crm"
GITHUB_BOT_USERNAME="Helper-Bot"'

# Without GITHUB_BOT_USERNAME the gate cannot tell its own replies from theirs,
# so follow-up detection must stay OFF and say so — never loop on itself.
assert_scenario "$ROOT/scripts/tasks/manager/github-first-response.sh" first-response-followup false \
  '(.data.count == 0) and (.data.followups | startswith("disabled"))' \
  'COMMUNITY_REPOS="acme/crm"'

# A second run must not hand the same follow-up over again (keyed on comment id).
assert_scenario "$ROOT/scripts/tasks/manager/github-first-response.sh" first-response-followup false \
  '.data.count == 0' \
  'COMMUNITY_REPOS="acme/crm"
GITHUB_BOT_USERNAME="helper-bot"' 2

# github-first-response, run 2: the same item must not surface again. At six
# runs an hour, a gate that re-reports the same issue would wake the manager 144
# times a day for one unanswered issue.
assert_scenario "$ROOT/scripts/tasks/manager/github-first-response.sh" first-response-new false \
  '(.data.status == "all-answered") and (.data.count == 0)' \
  'COMMUNITY_REPOS="acme/crm"' 2

# github-first-response: BOUNDED RETRY regression (traced from #9836, which
# was acked ("seen") right as an org-wide spend-limit outage killed the reply
# and then never resurfaced — see the comment in the script). An item seen
# well past the retry window, with retries still available, must resurface
# marked as a retry.
assert_scenario "$ROOT/scripts/tasks/manager/github-first-response.sh" first-response-new true \
  '(.data.count == 1) and (.data.items[0].retry == true) and (.data.items[0].retries == 1)' \
  'COMMUNITY_REPOS="acme/crm"' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   OLD=$(( $(date +%s) - 3600 ));
   { echo key,seen_at,retries; echo "acme/crm#501,$OLD,0"; } > "$D/first-response-seen.csv"'

# ...but an item seen only moments ago must stay suppressed, even though it
# is past the grace period and GitHub still shows it as comments:0 — the
# retry window, not just the grace period, gates a resurface.
assert_scenario "$ROOT/scripts/tasks/manager/github-first-response.sh" first-response-new false \
  '(.data.status == "all-answered") and (.data.count == 0)' \
  'COMMUNITY_REPOS="acme/crm"' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   { echo key,seen_at,retries; echo "acme/crm#501,$(date +%s),0"; } > "$D/first-response-seen.csv"'

# ...and once retries are exhausted, the item must stop resurfacing here at
# all — backlog belongs to triage from that point on, per the task's own
# stated design, not to a gate that would otherwise retry forever.
assert_scenario "$ROOT/scripts/tasks/manager/github-first-response.sh" first-response-new false \
  '(.data.status == "all-answered") and (.data.count == 0)' \
  'COMMUNITY_REPOS="acme/crm"' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   OLD=$(( $(date +%s) - 3600 ));
   { echo key,seen_at,retries; echo "acme/crm#501,$OLD,3"; } > "$D/first-response-seen.csv"'

# inbox-check: this task had NO gate until now — it woke the Sonnet-tier
# manager twice a day on an empty inbox, the most expensive guaranteed wake
# in the system. Unconfigured must stay silent forever (most projects have no
# shared inbox, and a permanent 401 reported twice daily is worse than
# nothing).
assert_gate "$ROOT/scripts/tasks/helper/inbox-check.sh" "unconfigured" "false" ""

# A broken fetch must WAKE, never read as an empty inbox — this is the one
# gate where a swallowed failure could hide a security disclosure. No fixture
# matches, so the mock curl returns HTTP 000.
assert_gate "$ROOT/scripts/tasks/helper/inbox-check.sh" \
  "fetch-fails-must-wake" "true" 'INBOX_ENABLED="true"'

# An empty inbox is the common case and must cost nothing. Gmail omits the
# `messages` key entirely on a zero-match query (rather than returning an
# empty array), which is exactly the shape this fixture encodes.
assert_scenario "$ROOT/scripts/tasks/helper/inbox-check.sh" inbox-empty false \
  '(.data.status == "empty") and (.data.unread == 0)' \
  'INBOX_ENABLED="true"'

# Two unread messages: hand over ids only — never subjects, senders or
# bodies. The gate's JSON is mirrored verbatim into a telemetry log on disk,
# so mail content here would persist private mail outside the agent context.
assert_scenario "$ROOT/scripts/tasks/helper/inbox-check.sh" inbox-unread true \
  '(.data.status == "needs-triage") and (.data.count == 2) and (.data.unread == 2)
   and ([.data.messages[].id] | sort == ["m1","m2"])
   and (.data.messages[0].retry == false)
   and ([.data.messages[] | has("subject") or has("from") or has("snippet")] | any | not)' \
  'INBOX_ENABLED="true"'

# Run 2, same fixture: THE 0-TOKEN ASSERTION. The token is read-only, so this
# agent cannot mark mail read — without the seen ledger the same unread
# message would re-wake the manager twice a day forever.
assert_scenario "$ROOT/scripts/tasks/helper/inbox-check.sh" inbox-unread false \
  '(.data.status == "all-handed-over") and (.data.unread == 2)' \
  'INBOX_ENABLED="true"' 2

# weekly-identity-integrity-check: previously had NO behavioral coverage at
# all (it was named in this file's own HONEST LIMITS list). Now that its
# baseline is a per-task CSV of prompt hashes rather than one global hash of
# everything, the thing worth asserting is that drift is LOCALISED — the old
# design could only say "something changed".
#
# `ncl` is stubbed via a seed-written shim on PATH, and for the drift case it
# returns different task prompts on its second call, which is what lets a
# single fixture exercise baseline-then-drift.
# `ncl` is stubbed with fixed output; the BASELINE is pre-seeded directly as
# CSV, which is what lets each case run once instead of needing a stub that
# changes behaviour between calls. H() computes a prompt hash exactly the way
# the gate does (sha256 of jq's @base64), so the seeds stay honest if that
# ever changes.
IDENTITY_STUB='mkdir -p "$SANDBOX/bin"
printf "#!/bin/bash\ncat %s/live.json\n" "$SANDBOX" > "$SANDBOX/bin/ncl"
chmod +x "$SANDBOX/bin/ncl"
printf %s "[{\"id\":\"t1\",\"prompt\":\"alpha\"},{\"id\":\"t2\",\"prompt\":\"beta\"}]" > "$SANDBOX/live.json"
H() { printf %s "$(printf %s "$1" | base64)" | sha256sum | cut -d" " -f1; }
D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D"'

# No baseline yet: record it and do NOT wake — a baseline is not news.
assert_scenario "$ROOT/scripts/tasks/manager/weekly-identity-integrity-check.sh" no-fixtures false \
  '.data.status == "baseline-initialized"' '' 1 \
  "$IDENTITY_STUB"

# Baseline matches the live prompts exactly: the quiet weekly case, no wake.
assert_scenario "$ROOT/scripts/tasks/manager/weekly-identity-integrity-check.sh" no-fixtures false \
  '.data.status == "no-drift"' '' 1 \
  "$IDENTITY_STUB
   { echo task_id,prompt_sha256; echo t1,\$(H alpha); echo t2,\$(H beta); } > \"\$D/task-prompt-hashes.csv\""

# One tampered prompt must wake AND name the drifted task. That specificity
# is the whole point of the per-task hash CSV — the previous single global
# hash could only ever report that *something* had changed.
assert_scenario "$ROOT/scripts/tasks/manager/weekly-identity-integrity-check.sh" no-fixtures true \
  '(.data.status == "drift") and (.data.drifted == "t2")
   and (.data.added == "") and (.data.removed == "")' '' 1 \
  "$IDENTITY_STUB
   { echo task_id,prompt_sha256; echo t1,\$(H alpha); echo t2,\$(H SOMETHING-ELSE); } > \"\$D/task-prompt-hashes.csv\""

# A task that DISAPPEARED is as much a tamper signal as a changed one, and was
# previously indistinguishable: a removed task just changed the global hash.
assert_scenario "$ROOT/scripts/tasks/manager/weekly-identity-integrity-check.sh" no-fixtures true \
  '(.data.status == "drift") and (.data.removed == "t2") and (.data.added == "t3")' '' 1 \
  "$IDENTITY_STUB
   printf %s '[{\"id\":\"t1\",\"prompt\":\"alpha\"},{\"id\":\"t3\",\"prompt\":\"gamma\"}]' > \"\$SANDBOX/live.json\"
   { echo task_id,prompt_sha256; echo t1,\$(H alpha); echo t2,\$(H beta); } > \"\$D/task-prompt-hashes.csv\""

# The acked baseline must NOT be self-healed on drift: a lost wake has to
# re-alert next week rather than silently baselining a tampered prompt as
# good. This needs to inspect FILE STATE after the run, which assert_scenario
# can't do (it only sees stdout), so it runs its own sandbox — same reason
# ledger_case below does.
identity_no_selfheal() {
  local sh="$ROOT/scripts/tasks/manager/weekly-identity-integrity-check.sh"
  local t; t=$(mktemp -d)
  local d="$t/plugin-data/community-manager"
  mkdir -p "$d" "$t/bin"
  printf '#!/bin/bash\ncat %s/live.json\n' "$t" > "$t/bin/ncl"; chmod +x "$t/bin/ncl"
  printf '%s' '[{"id":"t1","prompt":"alpha"},{"id":"t2","prompt":"beta"}]' > "$t/live.json"
  local old_hash; old_hash=$(printf %s "$(printf %s OLD-ACKED | base64)" | sha256sum | cut -d' ' -f1)
  { echo 'task_id,prompt_sha256'; echo "t1,whatever"; echo "t2,$old_hash"; } > "$d/task-prompt-hashes.csv"

  local out
  out=$(cd "$t" && PATH="$t/bin:$PATH" bash <(sed -e "s#/workspace/agent/plugin-data#$t/plugin-data#g" "$sh") 2>/dev/null | tail -1)

  if ! printf '%s' "$out" | jq -e '.data.status == "drift"' >/dev/null 2>&1; then
    fail "identity/no-selfheal: expected drift, got: ${out:0:120}"; rm -rf "$t"; return
  fi
  # The acked file must still carry the OLD hash...
  if grep -q ",$old_hash\$" "$d/task-prompt-hashes.csv"; then pass
  else fail "identity/no-selfheal: the acked baseline was overwritten on drift — a lost wake would never re-alert"; fi
  # ...and the new hashes must land in a SIDECAR, not the baseline.
  if [ -s "$d/task-prompt-hashes.csv.new" ]; then pass
  else fail "identity/no-selfheal: no .new sidecar written, so the agent has nothing to review"; fi
  rm -rf "$t"
}
identity_no_selfheal

# security-advisory-sweep: three alerts of mixed severity and scope. Asserts
# the enrichment the agent depends on — worst-first ordering, the severity
# rollup, and `scope`, which is the first input to "are we genuinely
# affected": a development-only dependency is a different risk from a runtime
# one. Before this, the gate emitted only alert numbers and the agent had to
# re-fetch each one to learn any of it.
assert_scenario "$ROOT/scripts/tasks/helper/security-advisory-sweep.sh" advisory-mixed true \
  '(.data.status == "new")
   and (.data.count == 3)
   and (.data.highest_severity == "critical")
   and (.data.advisories[0].severity == "critical")
   and (.data.advisories[0].package == "lodash")
   and (.data.advisories[0].scope == "runtime")
   and (.data.advisories[0].first_patched == "4.17.21")
   and (.data.advisories[0].ghsa_id == "GHSA-crit-0002")
   and (.data.by_severity.critical == 1)
   and (.data.by_severity.low == 1)
   and (.data.runtime_scoped == 1)
   and (.data.with_fix_pr == 2)
   and (.data.needs_fix_pr == 1)
   and (.data.major_bumps == 1)
   and ([.data.advisories[] | select(.package == "lodash") | .dependabot_pr.number] == [11])
   and ([.data.advisories[] | select(.package == "lodash") | .bump] == ["major"])
   and ([.data.advisories[] | select(.package == "chalk") | .bump] == ["minor-or-patch"])
   and ([.data.advisories[] | select(.package == "postcss") | .has_fix_pr] == [false])' \
  'COMMUNITY_REPOS="acme/crm"'
# docs-currency-watch: three merged PRs, and the assertions that matter are
# the RELEASE GATING inputs — the milestone the docs PR must be tagged with,
# and latest_release so the agent can tell "already shipped, merge it" from
# "unreleased, hold it as a draft". Docs describing an unreleased fix are wrong
# for everyone reading the site today, so this is a correctness property.
assert_scenario "$ROOT/scripts/tasks/helper/docs-currency-watch.sh" docs-merges true \
  '(.data.status == "new-merges")
   and (.data.count == 3)
   and (.data.latest_release == "v5.2.0")
   and (.data.source_repo == "acme/crm")
   and (.data.docs_repo == "acme/docs")
   and (.data.without_milestone == 1)
   and ([.data.merged[] | select(.number == 301) | .milestone] == ["v5.3.0"])
   and (.data.deferred == 0)' \
  'COMMUNITY_REPOS="acme/crm"
DOCS_REPO="acme/docs"'

# docs-currency-watch: no DOCS_REPO means the project has no docs site, and the
# task must stay silent forever rather than inventing a target.
assert_gate "$ROOT/scripts/tasks/helper/docs-currency-watch.sh" no-docs-target false \
  'COMMUNITY_REPOS="acme/crm"'

# docs-currency-watch, run 2: the same merges must not resurface.
assert_scenario "$ROOT/scripts/tasks/helper/docs-currency-watch.sh" docs-merges false \
  '.data.status == "no-new-merges"' \
  'COMMUNITY_REPOS="acme/crm"
DOCS_REPO="acme/docs"' 2

# --- 2d. project-health ledger: real git, not a mock -----------------------
# The ledger step is the only place the system WRITES to a remote, and the
# data it writes is the one thing that cannot be regenerated. A mocked git
# would prove nothing about the cases that actually matter, so this runs the
# real script against a real local bare repo and asserts on the resulting
# refs and trees:
#
#   * the default branch is never touched
#   * the metrics branch is an ORPHAN (no product history dragged along)
#   * today's row is READ BACK from the branch and matched against the local
#     file — "push returned 0" and "the row is on GitHub" are different claims
#   * a clean tree with an UNPUSHED commit still pushes — the bug that would
#     otherwise report success forever while the history never reached the
#     repo
#   * a diverged remote is NEVER force-overwritten
#   * only the curated numeric series are published, never a conversational
#     ledger that happens to sit in the same directory
#
# GitHub itself is stubbed out (a curl that always fails): the run is fully
# degraded on the metrics side, which is exactly what must NOT stop the
# ledger from publishing whatever history already exists.
ledger_case() {
  local sh="$1" label="$2"
  local t; t=$(mktemp -d)

  # HERMETIC GIT, and this is not optional hygiene — it was a real flaky
  # failure. Setting commit.gpgsign=false on the seed repo is not enough,
  # because the script creates its OWN clone internally and that one
  # inherits the HOST's global config. On a machine with commit signing on
  # (e.g. 1Password SSH signing), every commit the script made failed with
  # "the tree changed but the commit was refused" whenever the agent happened
  # to be locked — so this suite passed or failed depending on whether a
  # password manager was unlocked, and the count varied run to run.
  #
  # GIT_CONFIG_GLOBAL/SYSTEM (git >= 2.32) point every git process spawned
  # from here at a throwaway config instead, so the result depends only on
  # the code under test.
  cat > "$t/gitconfig" <<'GITCFG'
[user]
  name = ledger test
  email = ledger@test.invalid
[commit]
  gpgsign = false
[tag]
  gpgsign = false
[init]
  defaultBranch = main
GITCFG
  export GIT_CONFIG_GLOBAL="$t/gitconfig"
  export GIT_CONFIG_SYSTEM=/dev/null

  git init -q --bare "$t/remote.git"
  git init -q "$t/seed"
  git -C "$t/seed" config user.email t@t; git -C "$t/seed" config user.name t
  git -C "$t/seed" config commit.gpgsign false
  echo readme > "$t/seed/README.md"
  git -C "$t/seed" add -A; git -C "$t/seed" commit -qm init; git -C "$t/seed" branch -M main
  git -C "$t/seed" remote add origin "$t/remote.git"; git -C "$t/seed" push -q origin main

  mkdir -p "$t/data" "$t/bin"
  printf '#!/bin/bash\nexit 22\n' > "$t/bin/curl"; chmod +x "$t/bin/curl"
  printf 'COMMUNITY_REPOS="acme/demo"\nHEALTH_POST_DOW=%s\n' "$NOT_TODAY_DOW" > "$t/data/config.env"
  printf 'date,repo,stars,forks,open_issues,open_prs,new_contrib_7d,await_issues,await_oldest,rel_latest,dl_latest\n2026-01-01,acme/demo,1,2,3,4,0,5,,v1,10\n' > "$t/data/metrics-history.csv"
  # The live follower series is the CSV; the .jsonl is the frozen pre-CSV
  # archive. BOTH must publish — shipping only the current format would
  # silently orphan the older half of the one series nothing can rebuild.
  printf 'date,tw_f,fb_f,ig_f,li_f,dc_m,yt_o,yt_n,notes\n2026-01-01,190,,17,34,88,,,\n' \
    > "$t/data/social-metrics-history.csv"
  printf '{"date":"2026-01-01","x":1}\n' > "$t/data/social-metrics-history.jsonl"
  printf 'date,activeUsers,sessions,pageViews,engagementRate\n2026-01-01,10,12,30,0.5\n' > "$t/data/traffic-history-main.csv"
  # a file that must never be published, whichever agent runs
  echo 'private' > "$t/data/owner-instructions.jsonl"

  # Three seams: plugin-data → sandbox; the clone URL → the local bare repo;
  # the raw.githubusercontent read-back → `git show` on that same bare repo,
  # which is the honest local equivalent of "what is on the branch upstream".
  sed -e "s#/workspace/agent/plugin-data/community-helper#$t/data#" \
      -e "s#https://github.com/\$REPO_L.git#$t/remote.git#" \
      -e "s#curl -fsS --max-time 10 \"https://raw.githubusercontent.com/\$REPO_L/\$BRANCH/\$SUBDIR/metrics-history.csv\"#git -C \"$t/remote.git\" show \"\$BRANCH:\$SUBDIR/metrics-history.csv\"#" \
      "$sh" > "$t/run.sh"
  grep -q 'raw.githubusercontent' "$t/run.sh" \
    && fail "$label: read-back seam did not match — the raw-content URL in the script changed shape" || pass

  run_it() { (cd "$t" && PATH="$t/bin:$PATH" bash "$t/run.sh" 2>/dev/null | tail -1); }
  local out

  # LEDGER_REPO unset: the ledger step reports not-configured and nothing else breaks
  out=$(run_it)
  printf '%s' "$out" | jq -e '.data.ledger.status == "not-configured"' >/dev/null 2>&1 \
    && pass || fail "$label/unconfigured: expected ledger not-configured, got: ${out:0:200}"

  # first publish: pushed AND today's row read back from the branch
  printf 'LEDGER_REPO="acme/metrics"\n' >> "$t/data/config.env"
  out=$(run_it)
  printf '%s' "$out" | jq -e '.data.ledger.status == "published-and-verified"' >/dev/null 2>&1 \
    && pass || fail "$label/first-publish: expected published-and-verified, got: $(printf '%s' "$out" | jq -c .data.ledger 2>/dev/null)"

  # default branch untouched
  [ "$(git -C "$t/remote.git" ls-tree -r --name-only main)" = "README.md" ] \
    && pass || fail "$label: the repo's default branch was modified — it must never be"

  # orphan: the metrics branch carries exactly one commit, no product history
  [ "$(git -C "$t/remote.git" rev-list --count agent-metrics)" = "1" ] \
    && pass || fail "$label: metrics branch is not an orphan (it inherited the repo's history)"

  # every curated series published (both social formats), nothing conversational
  published=$(git -C "$t/remote.git" ls-tree -r --name-only agent-metrics)
  missing=""
  for want in metrics-history.csv social-metrics-history.csv social-metrics-history.jsonl traffic-history-main.csv; do
    printf '%s' "$published" | grep -q "$want" || missing="$missing $want"
  done
  [ -z "$missing" ] && pass || fail "$label: curated series not published:$missing"
  if printf '%s' "$published" | grep -q 'owner-instructions'; then
    fail "$label: published a conversational ledger — only numeric series may be published"
  else
    pass
  fi

  # the row on the branch IS today's local row (the read-back compared the
  # same thing the script did — assert it independently here)
  [ "$(git -C "$t/remote.git" show agent-metrics:agent-metrics/metrics-history.csv | tail -n 1)" = "$(tail -n 1 "$t/data/metrics-history.csv")" ] \
    && pass || fail "$label: last row on the branch is not the last local row"

  # THE REGRESSION: an unpushed commit with a clean tree must still publish.
  # Simulated by deleting the remote branch, leaving the local commit orphaned.
  git -C "$t/remote.git" branch -D agent-metrics >/dev/null 2>&1
  out=$(run_it)
  printf '%s' "$out" | jq -e '.data.ledger.status == "published-and-verified"' >/dev/null 2>&1 \
    && pass || fail "$label/unpushed-recovery: a clean tree with an unpushed commit must still push, got: $(printf '%s' "$out" | jq -c .data.ledger 2>/dev/null)"

  # a diverged remote must be reported, never force-overwritten
  git -C "$t/seed" fetch -q origin agent-metrics
  git -C "$t/seed" checkout -q -B agent-metrics FETCH_HEAD
  echo tampered > "$t/seed/outside-change.txt"
  git -C "$t/seed" add -A; git -C "$t/seed" commit -qm outside
  git -C "$t/seed" push -q origin agent-metrics
  printf '2026-01-02,191,,17,35,89,,,\n' >> "$t/data/social-metrics-history.csv"
  out=$(run_it)
  # Either it published on top of the outside commit (a fast-forward, fine) or
  # it reported a failure — what it must NEVER do is drop the outside commit.
  if git -C "$t/remote.git" ls-tree -r --name-only agent-metrics | grep -q 'outside-change.txt'; then
    pass
  else
    fail "$label/diverged: an outside commit was discarded — this task must never force-push"
  fi
  rm -rf "$t"
  # Scoped to this function: the throwaway config must not leak into later
  # sections, which run real git against the real repo.
  unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
}
ledger_case "$ROOT/scripts/tasks/helper/project-health.sh" "project-health/ledger"

# --- 2e. local telemetry: every gate must log its own run, on every path ---
# Every gate script mirrors its one-line JSON output to
# plugin-data/<agent>/telemetry/<task>.jsonl for weekly review (see the
# comment in github-ops-triage.sh). This is placed as EARLY as possible in
# each script, before any exit path, precisely because conversation-archive-
# prune.sh once had it placed after its first exit branch ("no-directory")
# and silently never logged that path at all. This test runs every gate
# script in its cheapest (usually unconfigured) exit path and asserts a
# valid JSON line was actually written — not just that the script itself
# didn't crash.
TELEMETRY_FAIL=0
for sh in "$ROOT"/scripts/tasks/*/*.sh; do
  group=$(basename "$(dirname "$sh")")
  agent=$(agent_of "$group")
  task=$(basename "$sh" .sh)
  sandbox=$(mktemp -d)
  mkdir -p "$sandbox/plugin-data/community-manager" "$sandbox/plugin-data/community-helper" "$sandbox/bin"
  cat > "$sandbox/bin/curl" <<'MOCK'
#!/bin/bash
for a in "$@"; do case "$a" in *%{http_code}*) printf '\n000';; esac; done
exit 22
MOCK
  chmod +x "$sandbox/bin/curl"
  ( cd "$sandbox" && PATH="$sandbox/bin:$PATH" \
    bash <(sed -e "s#/workspace/agent/plugin-data#$sandbox/plugin-data#g" "$sh") >/dev/null 2>&1 )
  sleep 0.2
  log="$sandbox/plugin-data/$agent/telemetry/$task.jsonl"
  if [ -s "$log" ] && jq -e . "$log" >/dev/null 2>&1; then
    pass
  else
    fail "telemetry: $sh did not write a valid JSON line to plugin-data/$agent/telemetry/$task.jsonl"
    TELEMETRY_FAIL=1
  fi
  rm -rf "$sandbox"
done
[ "$TELEMETRY_FAIL" -eq 0 ] || echo "  (a gate exiting before its telemetry setup is a silent-miss bug — move the setup earlier)"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
