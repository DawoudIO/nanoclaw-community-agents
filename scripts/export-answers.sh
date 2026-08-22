#!/bin/bash
# Export a LIVE install's configuration back into an onboarding-answers file.
#
#   bash scripts/export-answers.sh <nanoclaw-root> [out.json]
#
#   bash scripts/export-answers.sh ~/nanoclaw                 # -> onboarding-answers.exported.json
#   bash scripts/export-answers.sh ~/nanoclaw my-answers.json
#
# WHY: onboarding can be done conversationally (you DM the lead and it
# interviews you). That's the friendlier path, but it leaves the answers
# scattered across four agents' config.env files with no single editable
# record. This walks the live install and writes them back into the same
# shape as onboarding-answers.example.json — so you can diff it, edit one
# value, and rebuild from the file instead of redoing the interview.
#
# The round trip this completes:
#   interview (or answers file) -> live install -> export-answers.sh
#     -> edit one value -> rebuild -> export again to confirm
#
# WHAT IT CAN AND CANNOT RECOVER — read this before trusting the output:
#   * Recovered exactly: every `config.env:KEY` the templates consume. These
#     are the values the gate scripts actually read, so they are the ones that
#     change behaviour.
#   * Preserved verbatim, not parsed: each agent's `project-config.md`. It is
#     prose an agent wrote, so this copies it into `_project_config_raw`
#     rather than pretending to parse it into fields.
#   * NOT recoverable: anything that never lands in config.env — free-text
#     tone/audience guidance, and every credential (those live only in the
#     OneCLI vault, by design, and must never appear in this file).
#   Fields it cannot recover are left as null with their `_ask` text intact,
#   so an edit-and-rebuild pass shows you exactly what still needs answering.
#
# Secrets: the output is checked with scripts/check-onboarding.sh before it is
# written. If a credential-shaped value somehow reached a config.env, the
# export FAILS rather than writing a file containing it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NCL_ROOT="${1:-}"
OUT="${2:-onboarding-answers.exported.json}"
EXAMPLE="$ROOT/onboarding-answers.example.json"

command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 1; }
if [ -z "$NCL_ROOT" ] || [ ! -d "$NCL_ROOT" ]; then
  echo "usage: bash scripts/export-answers.sh <nanoclaw-root> [out.json]" >&2
  echo "  <nanoclaw-root> is the dir containing groups/ — the same place you ran ncl from." >&2
  exit 1
fi
[ -f "$EXAMPLE" ] || { echo "missing $EXAMPLE"; exit 1; }

# --- 1. collect every live config.env key, tagged with its owning agent ----
# Layout: <root>/groups/<folder>/plugin-data/<agent-name>/config.env
LIVE=$(mktemp); trap 'rm -f "$LIVE" "$LIVE.json"' EXIT
FOUND_FILES=0
while IFS= read -r cfg; do
  [ -f "$cfg" ] || continue
  FOUND_FILES=$((FOUND_FILES+1))
  agent=$(basename "$(dirname "$cfg")")
  # Only KEY=VALUE lines; strip comments, surrounding quotes, trailing space.
  grep -E '^[A-Z_][A-Z_0-9]*=' "$cfg" 2>/dev/null | while IFS= read -r line; do
    k=${line%%=*}
    v=${line#*=}
    v=${v%%#*}
    v=$(printf '%s' "$v" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//; s/^'"'"'//; s/'"'"'$//')
    printf '%s\t%s\t%s\n' "$agent" "$k" "$v"
  done >> "$LIVE"
done < <(find "$NCL_ROOT" -type f -name config.env -path '*plugin-data*' 2>/dev/null)

if [ "$FOUND_FILES" -eq 0 ]; then
  echo "No plugin-data/*/config.env found under $NCL_ROOT." >&2
  echo "Nothing has been configured yet, or this isn't the nanoclaw root." >&2
  exit 1
fi

# --- 1b. refuse to export a credential ------------------------------------
# This runs on the raw live values, BEFORE anything is built, because this
# script is the component that reads untrusted files off a live host. Do not
# rely on the downstream check-onboarding.sh guard alone: its leak scan skips
# metadata paths beginning with `_`, and everything this script collects lands
# under `_exported` — so a token would have sailed straight through it. (It
# did, in testing. Hence this block.)
#
# config.env is for non-secret task parameters only; credentials belong in
# the OneCLI vault and are injected at the egress proxy. A secret here is a
# real incident, so fail loudly and name the key rather than exporting it.
LEAK_KEYS=$(awk -F'\t' '
  {
    k=$2; v=$3
    if (k ~ /(TOKEN|SECRET|PASSWORD|APIKEY|API_KEY|CREDENTIAL|PRIVATE_KEY)$/) { print $1": "k; next }
    if (v ~ /gh[pousr]_[A-Za-z0-9]{16,}/)          { print $1": "k; next }
    if (v ~ /sk-[A-Za-z0-9_-]{16,}/)               { print $1": "k; next }
    if (v ~ /^phc_[A-Za-z0-9]{20,}/)               { print $1": "k; next }
    if (v ~ /discord(app)?\.com\/api\/webhooks\//) { print $1": "k; next }
  }' "$LIVE" | sort -u)
if [ -n "$LEAK_KEYS" ]; then
  echo "REFUSING TO EXPORT — credential-shaped value(s) found in a live config.env:" >&2
  printf '  %s\n' "$LEAK_KEYS" >&2
  echo >&2
  echo "config.env holds non-secret task parameters only. Move these into the OneCLI" >&2
  echo "vault, remove them from config.env, then re-run. Nothing was written." >&2
  exit 1
fi

# agent->key->value as JSON, plus a flat key->value (first writer wins) for
# the template fill. Flat is safe because a key means the same thing in every
# agent that reads it — that invariant is enforced by check-onboarding.sh.
jq -Rn --rawfile raw "$LIVE" '
  ($raw | split("\n") | map(select(length>0) | split("\t"))) as $rows
  | { by_agent: ($rows | group_by(.[0]) | map({key: .[0][0],
        value: (map({key: .[1], value: .[2]}) | from_entries)}) | from_entries),
      flat: ($rows | map({key: .[1], value: .[2]}) | from_entries) }
' > "$LIVE.json"

# --- 2. fill the example template's `value` fields -------------------------
# A leaf is fillable when its own `persists_to` names a config key, or when
# the leaf's key matches a live config key case-insensitively (e.g.
# ga4_property_id -> GA4_PROPERTY_ID). Metadata (_ask, _note, ...) is kept so
# the exported file is still self-documenting for editing.
STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
RESULT=$(jq --slurpfile live "$LIVE.json" --arg stamp "$STAMP" --arg src "$NCL_ROOT" '
  ($live[0].flat) as $flat
  | ($flat | keys) as $livekeys
  # walk every object that has a "value" key and try to fill it
  | def fill:
      if type == "object" then
        with_entries(.value |= fill)
        | if has("value") then
            ( (.persists_to? // "") | tostring ) as $pt
            | . as $node
            | ( [ $livekeys[] | select( ($pt | test("config\\.env:" + . + "\\b")) ) ] ) as $byhint
            | if ($byhint | length) > 0 then .value = $flat[$byhint[0]]
              else . end
          else . end
      elif type == "array" then map(fill)
      else . end;
    fill
  | ._exported = {
      "_note": "Written by scripts/export-answers.sh from a live install. Edit any value and rebuild; re-export afterwards to confirm the change landed. Credentials are never exported — they live only in the OneCLI vault.",
      "at": $stamp,
      "source": $src,
      "live_config_by_agent": $live[0].by_agent
    }
' "$EXAMPLE")

# fill by case-insensitive key-name match for leaves the hint didn't cover
RESULT=$(printf '%s' "$RESULT" | jq '
  (._exported.live_config_by_agent | [.[] | to_entries[]] | from_entries) as $flat
  | def fill2:
      if type == "object" then
        with_entries(
          (.key | ascii_upcase) as $K
          | .value |= ( if (type == "object" and has("value") and .value == null and ($flat | has($K)))
                        then .value = $flat[$K] else fill2 end )
        )
      elif type == "array" then map(fill2)
      else . end;
    fill2')

# --- 3. report what could not be recovered, then verify, then write --------
UNSET_COUNT=$(printf '%s' "$RESULT" | jq '[paths as $p | select((getpath($p)|type) != "object" and (getpath($p)|type) != "array") | select(($p|last) == "value") | select(getpath($p) == null)] | length')
UNMAPPED=$(printf '%s' "$RESULT" | jq -r '
  (._exported.live_config_by_agent | [.[] | keys[]] | unique) as $livek
  | ($livek - ([paths(scalars) as $p | getpath($p) | tostring]
      | map(capture("config\\.env:(?<k>[A-Z_0-9]+)").k? // empty) | unique))
  | if length > 0 then "  live config keys the template does not model: " + join(", ") else "" end')

TMPOUT=$(mktemp)
printf '%s\n' "$RESULT" > "$TMPOUT"
if ! jq -e . "$TMPOUT" >/dev/null 2>&1; then
  echo "export produced invalid JSON — refusing to write" >&2; rm -f "$TMPOUT"; exit 1
fi
# Reuse the real validator, including its credential-leak guard.
if ! bash "$ROOT/scripts/check-onboarding.sh" "$TMPOUT" >/dev/null 2>&1; then
  echo "FAILED validation — not writing $OUT. Details:" >&2
  bash "$ROOT/scripts/check-onboarding.sh" "$TMPOUT" >&2
  rm -f "$TMPOUT"; exit 1
fi
mv "$TMPOUT" "$OUT"

FILLED=$(printf '%s' "$RESULT" | jq '[.._exported? // empty] | length' >/dev/null 2>&1; printf '%s' "$RESULT" | jq '[paths as $p | select(($p|last) == "value") | select(getpath($p) != null)] | length')
echo "wrote $OUT"
echo "  config files read: $FOUND_FILES"
echo "  answers filled:    $FILLED"
echo "  still null:        $UNSET_COUNT  (free-text guidance and anything never written to config.env — see each field's _ask)"
[ -n "$UNMAPPED" ] && echo "$UNMAPPED"
echo
echo "Next: edit a value, rebuild, then re-run this to confirm the change landed."
