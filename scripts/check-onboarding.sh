#!/bin/bash
# Keep onboarding-answers.example.json honest against the code.
#
#   bash scripts/check-onboarding.sh                 # validate the example template
#   bash scripts/check-onboarding.sh my-answers.json # also validate a filled-in copy
#
# Three checks, all mechanical:
#   1. Valid JSON.
#   2. Key coverage, BOTH directions — every config.env key a gate script or a
#      setup-check reads must be named in the answers file, and every key the
#      answers file claims to persist must actually be read by something.
#      A drift in either direction is how "I answered that but nothing
#      happened" gets born.
#   3. No secrets. This file is config and is safe to commit; a token in it
#      is a real incident, so anything credential-shaped fails the check.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLE="$ROOT/onboarding-answers.example.json"
EXTRA="${1:-}"
FAIL=0
note() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 1; }

for f in "$EXAMPLE" ${EXTRA:+"$EXTRA"}; do
  [ -f "$f" ] || { note "missing file: $f"; continue; }

  # --- 1. valid JSON -------------------------------------------------------
  if ! jq -e . "$f" >/dev/null 2>&1; then
    note "invalid JSON: $f"; continue
  fi

  # --- 3. no secrets (run early; a leak matters more than a coverage gap) --
  # Credential-shaped values, not key names — `_ask` text legitimately says
  # the word "token", so match on VALUE shape only.
  LEAKS=$(jq -r '
    [ paths(scalars) as $p | { k: ($p|map(tostring)|join(".")), v: (getpath($p)|tostring) } ]
    | map(select(
        (.k | test("^_|_README|_note|_ask|_format|_mechanisms|_options|_tasks")) == false
        and (
             (.v | test("gh[pousr]_[A-Za-z0-9]{16,}"))          # GitHub tokens
          or (.v | test("sk-[A-Za-z0-9_-]{16,}"))                # OpenAI/Anthropic-style
          or (.v | test("^phc_[A-Za-z0-9]{20,}"))                # PostHog project key
          or (.v | test("discord(app)?\\.com/api/webhooks/"))    # Discord webhook
          or (.v | test("^[A-Za-z0-9+/]{40,}={0,2}$"))           # long base64 blob
        )))
    | .[].k' "$f" 2>/dev/null)
  if [ -n "$LEAKS" ]; then
    while IFS= read -r k; do
      [ -n "$k" ] && note "credential-shaped value at '$k' in $f — secrets belong ONLY in the OneCLI vault"
    done <<< "$LEAKS"
  fi
done

# --- 2. key coverage, both directions -------------------------------------
# Keys the code actually reads from config.env, excluding internal shell vars.
CODE_KEYS=$(
  { grep -rhoE '\$\{[A-Z_]+' "$ROOT"/scripts/tasks/*/*.sh "$ROOT"/*/*/setup-check.sh 2>/dev/null \
      | tr -d '${'
    # GA4_PROPERTY_ID appears as ${GA4_PROPERTY_ID:-} but the regex above
    # truncates at the digit; catch it (and any other digit-bearing key)
    # by name instead.
    grep -rhoE '\b(GA4_PROPERTY_ID)\b' "$ROOT"/scripts/tasks/*/*.sh "$ROOT"/*/*/setup-check.sh 2>/dev/null
  } | sort -u | grep -vE '^(FAILED|SINCE|TRUNC|ISSUES|STUCK|GA|DATA|REPOS|TMP|HIST|OLD|NEW|ALL|DIGEST|CHANGED|WAKE|PREV|TODAY|LEAKS|CODE|FILE|EXTRA|EXAMPLE|ROOT|FAIL)$'
)

ANSWER_KEYS=$(jq -r '[paths(scalars) as $p | getpath($p) | tostring]
  | map(select(test("config\\.env:")))
  | map(capture("config\\.env:(?<k>[A-Z_0-9]+)").k) | .[]' "$EXAMPLE" 2>/dev/null | sort -u)
# plus the all-agents form used for the identity key
grep -q 'config.env:GITHUB_BOT_USERNAME' "$EXAMPLE" && ANSWER_KEYS=$(printf '%s\nGITHUB_BOT_USERNAME\n' "$ANSWER_KEYS" | sort -u)

while IFS= read -r k; do
  [ -z "$k" ] && continue
  grep -q "^$k$" <<< "$ANSWER_KEYS" || note "config key '$k' is read by code but never collected in onboarding-answers.example.json"
done <<< "$CODE_KEYS"

while IFS= read -r k; do
  [ -z "$k" ] && continue
  grep -q "^$k$" <<< "$CODE_KEYS" || note "onboarding-answers.example.json promises to persist '$k' but no script reads it"
done <<< "$ANSWER_KEYS"

# --- the four project-config keys setup-check greps literally --------------
for k in $(grep -ohE 'for k in [a-z_ ]+' "$ROOT"/*/*/setup-check.sh 2>/dev/null | sed 's/for k in //'); do
  grep -q "project_config:$k\|project_config\b.*$k\|\"$k\"" "$EXAMPLE" \
    || note "setup-check.sh greps project-config key '$k' but onboarding-answers.example.json never names it"
done

if [ "$FAIL" -eq 0 ]; then
  echo "onboarding check OK: JSON valid, no secrets, config keys match the code both ways"
fi
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
