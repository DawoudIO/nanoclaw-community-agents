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
    manager)     echo "opensource/community-manager";;
    engineering) echo "opensource/community-coding";;
    marketing)   echo "opensource/community-marketing";;
    *)           echo "";;
  esac
}

# Reverse of group_dir: template directory name -> scripts/tasks/<group> key.
# All three templates share the opensource/ category, so the category dir no
# longer identifies the group — the template name does.
group_key() {
  case "$1" in
    community-manager)   echo "manager";;
    community-coding)    echo "engineering";;
    community-marketing) echo "marketing";;
    *)                   echo "";;
  esac
}

# Print the embedded script from a task .md (2-space indent stripped).
# Empty output if the file has no script block.
#
# IMPORTANT: the block runs from `script: |` to the CLOSING `---`, not to the
# first non-indented line. Stopping at a non-indented line is what let a
# previous bug hide corrupted frontmatter from --check: stale fragments below
# that point were invisible to the extractor and preserved by the injector,
# so the files were broken while the check passed. `script:` is required to
# be the last frontmatter key (verified for every task file); a key after it
# would be swallowed by this rule.
extract_script() {
  awk '
    BEGIN { fm=0; inblock=0 }
    /^---$/ { fm++; if (fm==2) exit; next }
    fm==1 && /^script: \|$/ { inblock=1; next }
    fm==1 && inblock { sub(/^  /, ""); print; next }
  ' "$1"
}

# Rewrite a task .md with the script block replaced by the given .sh file.
# Everything from `script: |` to the closing `---` is discarded and replaced,
# so a re-sync repairs a corrupted block instead of layering on top of it.
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
    fm==1 && skipping { next }
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
  tdir=$(basename "$(dirname "$(dirname "$(dirname "$md")")")")
  name=$(basename "$md" .md)
  key=$(group_key "$tdir")
  if [ -n "$key" ]; then sh="$ROOT/scripts/tasks/$key/$name.sh"; else sh=""; fi
  if [ -z "$sh" ] || [ ! -f "$sh" ]; then
    echo "ORPHAN embedded script (no .sh source): ${md#"$ROOT"/}"
    FAIL=$((FAIL+1))
  fi
done

if $CHECK && [ "$FAIL" -eq 0 ]; then
  echo "check OK: all task scripts match their .sh sources"
fi
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
