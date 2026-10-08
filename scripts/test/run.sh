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
#     success path: conversation-archive-prune (only its telemetry line is
#     asserted, in 2e).
#   - Fixtures are hand-written, so they encode what we BELIEVE each API
#     returns. They catch our own logic errors, not upstream API changes —
#     only a real install does that.
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

# --- 1g. no task may reference a plugin-data dir that is not its own -------
# The agent sees only /workspace/agent/plugin-data/community-manager/. A path
# naming any other agent's dir is not a slow failure, it is a permanently
# dead task: the file is simply never there.
#
# This is worth a hard gate because it has shipped repeatedly, and once with
# the test fixture seeding the same wrong path, so the suite agreed with the
# bug. Two of those cases were append-only ledgers, where a silent miss is
# unrecoverable data loss rather than a late report.
#
# The template is single-agent now, so any `plugin-data/<name>` other than
# community-manager — anywhere under opensource/ or scripts/tasks — is a stale
# leftover of the retired sub-agent and must fail.
CROSS=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  echo "  stale plugin-data path: ${hit#"$ROOT"/}"
  CROSS=1
done < <(grep -rnoE 'plugin-data/[A-Za-z0-9_-]+' "$ROOT/opensource" "$ROOT/scripts/tasks" 2>/dev/null \
         | grep -v 'plugin-data/community-manager' | grep -v 'plugin-data/<')
[ "$CROSS" -eq 0 ] && pass || fail "file(s) reference a plugin-data dir other than community-manager — that path is never readable"

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
#   __D30__         — 30 days ago as YYYY-MM-DD, for fixtures whose dates
#                     must sit a fixed distance in the past (project-context's
#                     release.json)
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
  mkdir -p "$sandbox/bin" "$sandbox/plugin-data/community-manager"
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
  [ -n "$cfg" ] && printf '%s\n' "$cfg" > "$sandbox/plugin-data/community-manager/config.env"
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
  mkdir -p "$sandbox/bin" "$sandbox/plugin-data/community-manager"
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
  [ -n "$cfg" ] && printf '%s\n' "$cfg" > "$sandbox/plugin-data/community-manager/config.env"
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

# Unconfigured: a gate that watches external state must exit clean without
# waking when no repos are configured.
assert_gate "$ROOT/scripts/tasks/manager/github-first-response.sh" "unconfigured" "false" ""
assert_gate "$ROOT/scripts/tasks/manager/project-context.sh" "unconfigured" "false" ""

# Fetch failure with config set: gates that watch external state must WAKE
# (a broken fetch must never read as a quiet day). The mock curl exits 22
# for every URL because no fixtures matched.
assert_gate "$ROOT/scripts/tasks/manager/github-first-response.sh" \
  "fetch-fails-must-wake" "true" 'COMMUNITY_REPOS="acme/demo"'
assert_gate "$ROOT/scripts/tasks/manager/project-context.sh" \
  "fetch-fails-must-wake" "true" 'CONTEXT_REPOS="acme/demo"'

# --- 2c. success-path assertions -------------------------------------------
# These check the SHAPE the task prompts actually read. A renamed or dropped
# field here is a broken task even though the gate still emits valid JSON and
# the right wakeAgent — which is exactly what the failure-only tests miss.

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

# --- project-context: the agent's picture of the repos must be today's ----
# Run 1 is a baseline: it stores heads and wakes once so the agent builds its
# notes. released-vs-unreleased comes from compare(tag...head); milestones are
# the shape of the next release. No daily delta yet (nothing to diff against).
assert_scenario "$ROOT/scripts/tasks/manager/project-context.sh" project-context true \
  '(.data.status == "baseline")
   and (.data.changed_repos == ["acme/demo"])
   and (.data.repos[0].release.tag == "v1.2.0")
   and (.data.repos[0].unreleased.ahead_by == 3)
   and (.data.repos[0].unreleased.commits | length == 3)
   and (.data.repos[0].milestones[0].title == "1.3.0")
   and (.data.repos[0].milestones[0].open == 4)
   and (.data.repos[0].since_last_run == null)' \
  'CONTEXT_REPOS="acme/demo"'

# Run 2, same head: nothing changed, no wake — the daily run is 0-token on a
# quiet day, and release-state.csv is still rewritten for the agent to cat.
assert_scenario "$ROOT/scripts/tasks/manager/project-context.sh" project-context false \
  '(.data.status == "unchanged") and (.data.repos[0].status == "unchanged") and (.data.changed_repos == [])' \
  'CONTEXT_REPOS="acme/demo"' 2

# A stored head that differs from the live one: the delta is fetched and the
# agent is told exactly which skill and docs files to re-read. Seeded state
# stands in for "yesterday's run".
assert_scenario "$ROOT/scripts/tasks/manager/project-context.sh" project-context true \
  '(.data.status == "changed")
   and (.data.repos[0].status == "changed")
   and (.data.repos[0].since_last_run.total_commits == 2)
   and (.data.repos[0].since_last_run.skills_changed == [".agents/skills/acme/repo-health.md"])
   and (.data.repos[0].since_last_run.docs_changed == ["docs/settings.md","CHANGELOG.md"])
   and (.data.repos[0].since_last_run.changelog_changed == true)
   and (.data.repos[0].release_changed == false)' \
  'CONTEXT_REPOS="acme/demo"' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   printf "repo,head_sha,release_tag,checked_at\nacme/demo,0000000000000000000000000000000000000000,v1.2.0,2026-01-01\n" > "$D/context-heads.csv"'

# A stored tag that differs from the live one is a release that shipped since
# yesterday: wake even if the head is unchanged.
assert_scenario "$ROOT/scripts/tasks/manager/project-context.sh" project-context true \
  '(.data.repos[0].status == "unchanged") and (.data.repos[0].release_changed == true) and (.data.changed_repos == ["acme/demo"])' \
  'CONTEXT_REPOS="acme/demo"' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   printf "repo,head_sha,release_tag,checked_at\nacme/demo,bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,v1.1.0,2026-01-01\n" > "$D/context-heads.csv"'

# release-state.csv is the file the agent reads when asked "is X released":
# written on every run, one row per repo, with the tag, the unreleased count
# and the next milestone's progress.
assert_scenario "$ROOT/scripts/tasks/manager/project-context.sh" project-context any '-' \
  'CONTEXT_REPOS="acme/demo"' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D"'
t=$(mktemp -d); mkdir -p "$t/plugin-data/community-manager" "$t/bin"; mkdir -p "$t/.fixtures"
render_fixtures "$ROOT/scripts/test/fixtures/project-context" "$t/.fixtures"
cat > "$t/bin/curl" <<MOCK
#!/bin/bash
url=""; for a in "\$@"; do case "\$a" in https://*) url="\$a";; esac; done
while IFS='|' read -r pat file code; do [ -z "\$pat" ] && continue; case "\$url" in *"\$pat"*) cat "$t/.fixtures/\$file"; exit 0;; esac; done < "$t/.fixtures/routes.txt"
exit 22
MOCK
chmod +x "$t/bin/curl"
printf 'CONTEXT_REPOS="acme/demo"\n' > "$t/plugin-data/community-manager/config.env"
( cd "$t" && PATH="$t/bin:$PATH" bash <(sed -e "s#/workspace/agent/plugin-data#$t/plugin-data#g" "$ROOT/scripts/tasks/manager/project-context.sh") >/dev/null 2>&1 )
RS="$t/plugin-data/community-manager/release-state.csv"
if [ -s "$RS" ] && [ "$(head -n 1 "$RS")" = "date,repo,released_tag,released_at,unreleased_commits,next_milestone,milestone_closed,milestone_open,milestone_due" ] \
   && [ "$(tail -n 1 "$RS" | cut -d, -f2,3,5,6,7,8)" = "acme/demo,v1.2.0,3,1.3.0,9,4" ]; then
  pass
else
  fail "project-context: release-state.csv missing or wrong — got: $(tail -n 2 "$RS" 2>/dev/null | tr '\n' ' ')"
fi
rm -rf "$t"

# A malformed repo string never reaches a URL: bad-config, degraded, wake.
assert_scenario "$ROOT/scripts/tasks/manager/project-context.sh" project-context true \
  '(.data.degraded_repos == ["acme/demo?x=1"]) and ([.data.repos[] | select(.status == "bad-config")] | length == 1)' \
  'CONTEXT_REPOS="acme/demo acme/demo?x=1"'

# --- follow-up-nudge: silence after a contribution, one check-in per item ---
# Stale PRs: maintainers' own and bots' PRs are filtered out; the one outsider
# PR carries first_time and changes_requested. Issues: #501 (we posted a
# workaround, silence since) is due; #502 is skipped because the reporter
# replied after our post — that is github-first-response's thread now.
FUN_SEED='D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   OLD=$(date -u -v-12d +%Y-%m-%d 2>/dev/null || date -u -d "12 days ago" +%Y-%m-%d);
   printf "repo,number,posted_on,kind\nacme/demo,501,$OLD,workaround\nacme/demo,502,$OLD,workaround\n" > "$D/issue-followups.csv"'
assert_scenario "$ROOT/scripts/tasks/manager/follow-up-nudge.sh" follow-up-nudge true \
  '(.data.status == "follow-ups")
   and (.data.prs | length == 1) and (.data.prs[0].number == 412) and (.data.prs[0].first_time == true)
   and (.data.prs[0].changes_requested == true) and (.data.prs[0].days_idle >= 100)
   and (.data.issues | length == 1) and (.data.issues[0].number == 501) and (.data.issues[0].kind == "workaround")
   and (.data.chat_invite == "https://chat.example/invite") and (.data.degraded == [])' \
  'COMMUNITY_REPOS="acme/demo"
CHAT_INVITE_URL="https://chat.example/invite"
GITHUB_BOT_USERNAME="demo-bot"' 1 "$FUN_SEED"
# Once the agent has logged a nudge, the same item stays quiet for renudge_days.
assert_scenario "$ROOT/scripts/tasks/manager/follow-up-nudge.sh" follow-up-nudge false \
  '(.data.status == "quiet") and (.data.prs == []) and (.data.issues == [])' \
  'COMMUNITY_REPOS="acme/demo"
GITHUB_BOT_USERNAME="demo-bot"' 1 "$FUN_SEED"'; TODAY=$(date -u +%Y-%m-%d); printf "repo,number,nudged_on\nacme/demo,412,$TODAY\nacme/demo,501,$TODAY\n" > "$D/nudged.csv"'
# No chat invite configured: the field is null, never an empty string the
# agent might paste into a comment.
assert_scenario "$ROOT/scripts/tasks/manager/follow-up-nudge.sh" follow-up-nudge true \
  '.data.chat_invite == null' 'COMMUNITY_REPOS="acme/demo"'
assert_gate "$ROOT/scripts/tasks/manager/follow-up-nudge.sh" "unconfigured" "false" ""
assert_gate "$ROOT/scripts/tasks/manager/follow-up-nudge.sh" "fetch-fails-must-wake" "true" 'COMMUNITY_REPOS="acme/demo"'

# --- unanswered-watch: now on the Manager, reads its own sessions via ncl ----
# A channel session whose newest message is inbound and older than the grace
# period wakes the agent with the message; an acked key never re-wakes it.
UW_SEED='D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D" "$SANDBOX/bin";
   OLD=$(date -u -v-45M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "45 minutes ago" +%Y-%m-%dT%H:%M:%SZ);
   cat > "$SANDBOX/bin/ncl" <<NCL
#!/bin/bash
case "\$*" in
  *"sessions list"*) echo "[{\"id\":\"s1\",\"status\":\"active\",\"messaging_group_id\":\"g1\"},{\"id\":\"s2\",\"status\":\"active\",\"messaging_group_id\":null}]";;
  *"sessions history"*"s1"*) echo "[{\"direction\":\"out\",\"timestamp\":\"$OLD\",\"text\":\"hi\"},{\"direction\":\"in\",\"timestamp\":\"$OLD\",\"sender\":\"pat\",\"text\":\"how do I export families?\"}]";;
  *) echo "[]";;
esac
NCL
   chmod +x "$SANDBOX/bin/ncl"'
assert_scenario "$ROOT/scripts/tasks/manager/unanswered-watch.sh" no-fixtures true \
  '(.data.status == "unanswered") and (.data.messages | length == 1) and (.data.messages[0].messaging_group_id == "g1") and (.data.messages[0].sender == "pat") and (.data.messages[0].key | startswith("s1:"))' \
  'ACK_GRACE_MINUTES="20"' 1 "$UW_SEED"
assert_scenario "$ROOT/scripts/tasks/manager/unanswered-watch.sh" no-fixtures false \
  '.data.status == "all-answered"' \
  'ACK_GRACE_MINUTES="20"' 1 "$UW_SEED"'; OLD=$(date -u -v-45M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "45 minutes ago" +%Y-%m-%dT%H:%M:%SZ); echo "s1:$OLD" > "$D/acknowledged.txt"'
# A message inside the grace window is not unanswered yet.
assert_scenario "$ROOT/scripts/tasks/manager/unanswered-watch.sh" no-fixtures false \
  '.data.status == "all-answered"' \
  'ACK_GRACE_MINUTES="120"' 1 "$UW_SEED"

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
   and ([.data.by_source[].source] | sort == ["github","manager"])' '' 1 \
  'D="$SANDBOX/plugin-data/community-manager"; mkdir -p "$D";
   printf "OWNER_TZ=\"UTC\"\nTLDR_LOCAL_HOUR=\"%s\"\n" "$(date -u +%-H)" > "$D/config.env";
   NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ);
   echo "{\"at\":\"$NOW\",\"source\":\"github\",\"severity\":\"info\",\"line\":\"metrics history published\"}" >> "$D/digest-queue.jsonl";
   echo "{\"at\":\"$NOW\",\"source\":\"manager\",\"severity\":\"info\",\"line\":\"release announced\"}" >> "$D/digest-queue.jsonl";
   echo "{\"at\":\"$NOW\",\"source\":\"github\",\"severity\":\"attention\",\"line\":\"advisory needs a look\"}" >> "$D/digest-queue.jsonl"'

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
   echo "{\"at\":\"$NOW\",\"source\":\"github\",\"severity\":\"attention\",\"line\":\"arrived while rate-limited\"}" >> "$D/digest-queue.jsonl"'

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
# github-first-response: grace is 0 by default (reply as soon as the poll sees
# it), so the one real new item surfaces at once. The future-dated item (clock
# skew or a bad timestamp) has negative age and must NOT surface — never
# reply to something that "hasn't happened yet". A third item opened by the
# OWNER is present and must never surface:
# maintainers' own issues are not waiting for a first reply. Asserts the
# filter, not just the fetch.
assert_scenario "$ROOT/scripts/tasks/manager/github-first-response.sh" first-response-new true \
  '(.data.status == "needs-first-response")
   and (.data.count == 1)
   and (.data.items[0].number == 501)
   and (.data.items[0].type == "issue")
   and (.data.grace_minutes == 0)
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
# can't do (it only sees stdout), so it runs its own sandbox, like the
# project-context release-state.csv check above.
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

# --- 2e. local telemetry: every gate must log its own run, on every path ---
# Every gate script mirrors its one-line JSON output to
# plugin-data/<agent>/telemetry/<task>.jsonl for weekly review. This is placed as EARLY as possible in
# each script, before any exit path, precisely because conversation-archive-
# prune.sh once had it placed after its first exit branch ("no-directory")
# and silently never logged that path at all. This test runs every gate
# script in its cheapest (usually unconfigured) exit path and asserts a
# valid JSON line was actually written — not just that the script itself
# didn't crash.
TELEMETRY_FAIL=0
for sh in "$ROOT"/scripts/tasks/*/*.sh; do
  agent=community-manager
  task=$(basename "$sh" .sh)
  sandbox=$(mktemp -d)
  mkdir -p "$sandbox/plugin-data/$agent" "$sandbox/bin"
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
