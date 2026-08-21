#!/bin/bash
# Sync task gate scripts between scripts/tasks/*.sh and the task .md files.
#
# The .sh files under scripts/tasks/ are the CANONICAL source — edit and test
# them there (see scripts/test/run.sh). The NanoClaw template format requires
# the script inline in each task's frontmatter (`script: |`), so this tool
# injects each .sh into its matching .md.
#
#   bash scripts/sync-tasks.sh           # inject .sh -> .md (write)
#   bash scripts/sync-tasks.sh --check   # verify .md matches .sh (CI mode)
#
# Mapping: scripts/tasks/<group>/<name>.sh
#       -> <group-dir>/ai.nanoco.nanoclaw/tasks/<name>.md
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK=false
[ "${1:-}" = "--check" ] && CHECK=true
FAIL=0

group_dir() {
  case "$1" in
    support)     echo "support/community-support";;
    engineering) echo "engineering/community-coding";;
    marketing)   echo "marketing/community-marketing";;
    *)           echo "";;
  esac
}

# Print the embedded script from a task .md (2-space indent stripped),
# exactly as extract; empty output if the file has no script block.
extract_script() {
  awk '
    BEGIN { fm=0; inblock=0 }
    /^---$/ { fm++; if (fm==2) exit; next }
    fm==1 && /^script: \|$/ { inblock=1; next }
    fm==1 && inblock {
      if ($0 ~ /^  / || $0 == "") { sub(/^  /, ""); print; next }
      inblock=0
    }
  ' "$1"
}

# Rewrite a task .md with the script block replaced by the given .sh file.
inject_script() {
  local md="$1" sh="$2" tmp
  tmp=$(mktemp)
  awk -v shfile="$sh" '
    BEGIN { fm=0; skipping=0 }
    /^---$/ {
      fm++
      if (fm==2) skipping=0
      print; next
    }
    fm==1 && /^script: \|$/ {
      print "script: |"
      while ((getline line < shfile) > 0) {
        if (line == "") print ""
        else print "  " line
      }
      close(shfile)
      skipping=1; next
    }
    fm==1 && skipping {
      if ($0 ~ /^  / || $0 == "") next
      skipping=0
    }
    { print }
  ' "$md" > "$tmp"
  mv "$tmp" "$md"
}

for sh in "$ROOT"/scripts/tasks/*/*.sh; do
  group=$(basename "$(dirname "$sh")")
  name=$(basename "$sh" .sh)
  gdir=$(group_dir "$group")
  if [ -z "$gdir" ]; then
    echo "UNKNOWN group dir for $sh"; FAIL=$((FAIL+1)); continue
  fi
  md="$ROOT/$gdir/ai.nanoco.nanoclaw/tasks/$name.md"
  if [ ! -f "$md" ]; then
    echo "MISSING task file for scripts/tasks/$group/$name.sh: ${md#"$ROOT"/}"
    FAIL=$((FAIL+1)); continue
  fi
  if $CHECK; then
    if ! diff -q <(extract_script "$md") "$sh" >/dev/null 2>&1; then
      echo "DRIFT: ${md#"$ROOT"/} does not match scripts/tasks/$group/$name.sh"
      FAIL=$((FAIL+1))
    fi
  else
    inject_script "$md" "$sh"
    echo "synced ${md#"$ROOT"/}"
  fi
done

# Flag any task .md with an embedded script but no canonical .sh source.
for md in "$ROOT"/*/*/ai.nanoco.nanoclaw/tasks/*.md; do
  grep -q '^script: |$' "$md" || continue
  tdir=$(basename "$(dirname "$(dirname "$(dirname "$(dirname "$md")")")")")
  name=$(basename "$md" .md)
  case "$tdir" in
    support|engineering|marketing) sh="$ROOT/scripts/tasks/$tdir/$name.sh";;
    *) sh="";;
  esac
  if [ -z "$sh" ] || [ ! -f "$sh" ]; then
    echo "ORPHAN embedded script (no .sh source): ${md#"$ROOT"/}"
    FAIL=$((FAIL+1))
  fi
done

if $CHECK && [ "$FAIL" -eq 0 ]; then
  echo "check OK: all task scripts match their .sh sources"
fi
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
