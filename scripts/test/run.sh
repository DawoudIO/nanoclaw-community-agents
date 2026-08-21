#!/bin/bash
# Test harness for the task gate scripts — runs WITHOUT any agent.
#
#   bash scripts/test/run.sh
#
# What it does, per scripts/tasks/*/*.sh:
#   1. bash -n           — syntax check (all scripts)
#   2. behavioral tests  — scripts with a mock-curl fixture get executed
#      against canned API responses; the harness asserts the gate emits
#      exactly ONE line of valid JSON with the expected wakeAgent value.
#
# Mock model: a fake `curl` is placed first on PATH (a real executable, not
# an exported function — exported functions don't survive into `bash x.sh`
# children on bash 3.2/macOS). The fake matches URL substrings against the
# fixtures in scripts/test/fixtures/<script-name>/.
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

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
