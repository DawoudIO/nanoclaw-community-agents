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
#   2.  behavioral — each gate emits exactly ONE line of valid JSON, with the
#       expected wakeAgent, for: unconfigured (must not wake) and total fetch
#       failure (must wake — a broken fetch must never read as a quiet day).
#
# HONEST LIMITS, so nobody mistakes green for complete:
#   - scripts/test/fixtures/ does NOT exist yet. The mock `curl` below looks
#     for per-script fixture routes and, finding none, exits 22 for every
#     URL. That is exactly what makes the fetch-failure assertions real, but
#     it also means NO success-path response shape is covered: fields the
#     task prompts depend on (ready_to_merge, contribution_concentration,
#     unassigned_stale, insights[].previous_result, trigger) are never
#     validated here, nor is any gate's suppression branch. Adding fixtures
#     is the highest-value next step for this harness.
#   - The repo-mirror-sync assertion needs live network to github.com; it is
#     the one test that flips on an offline run.
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

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
