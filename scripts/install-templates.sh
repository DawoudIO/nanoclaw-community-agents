#!/bin/bash
# Copy the four agent templates into a NanoClaw checkout's templates/ folder.
#
#   bash scripts/install-templates.sh                  # target ../nanoclaw
#   bash scripts/install-templates.sh /path/to/nanoclaw
#   bash scripts/install-templates.sh --check          # report drift, change nothing
#
# WHY THIS EXISTS: NanoClaw resolves `--template <ref>` against TEMPLATES_DIR
# (`<nanoclaw>/templates`), and upstream ships that folder empty on purpose —
# the templates live here, in their own repo, and are copied in per install.
# Copying by hand went wrong twice in practice:
#
#   1. Copying this repo's ROOT into templates/ nests everything one level
#      deeper, so refs become `nanoclaw-community-agents/support/community-support`
#      instead of `support/community-support`, and templates/ fills up with
#      docs/ and scripts/ that aren't templates at all.
#   2. Copying once and forgetting means the copy silently drifts from this
#      repo. A stale copy still stamps — it just stamps the old bugs, and the
#      fixes you thought you were testing were never in play.
#
# So: run this instead of `cp -R`, and re-run it after pulling this repo.
set -uo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES=(support local engineering marketing)

CHECK=0
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --check) CHECK=1 ;;
    -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) TARGET="$arg" ;;
  esac
done

# Default: sibling checkout next to this repo, which is the layout the install
# docs assume (both repos cloned into the same parent directory).
[ -n "$TARGET" ] || TARGET="${NANOCLAW_DIR:-$SRC/../nanoclaw}"

if [ ! -d "$TARGET" ]; then
  cat >&2 <<EOF
error: no NanoClaw checkout at $TARGET

Clone both repos into the same parent directory:

  git clone https://github.com/DawoudIO/nanoclaw.git
  git clone https://github.com/DawoudIO/nanoclaw-community-agents.git
  cd nanoclaw-community-agents && bash scripts/install-templates.sh

Or pass the path: bash scripts/install-templates.sh /path/to/nanoclaw
EOF
  exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"

# Guard against pointing this at something that isn't a NanoClaw checkout —
# it would create a templates/ dir in a random directory and look like it worked.
if [ ! -f "$TARGET/nanoclaw.sh" ]; then
  echo "error: $TARGET has no nanoclaw.sh — that doesn't look like a NanoClaw checkout" >&2
  exit 1
fi

DEST="$TARGET/templates"
mkdir -p "$DEST"

# The nesting mistake from the header. Detect it, because the symptom
# (three-segment refs in the template picker) is confusing on its own.
if [ -d "$DEST/nanoclaw-community-agents" ]; then
  echo "warning: found $DEST/nanoclaw-community-agents/" >&2
  echo "         That's this repo's root copied in whole, which nests every ref one" >&2
  echo "         level deeper. Remove it so refs read 'support/community-support':" >&2
  echo "           rm -rf '$DEST/nanoclaw-community-agents'" >&2
  echo "" >&2
fi

if [ "$CHECK" = "1" ]; then
  drift=0
  for t in "${TEMPLATES[@]}"; do
    if [ ! -d "$DEST/$t" ]; then
      echo "MISSING  $t"
      drift=$((drift + 1))
      continue
    fi
    if ! diff -qr "$SRC/$t" "$DEST/$t" >/dev/null 2>&1; then
      echo "DRIFTED  $t"
      drift=$((drift + 1))
    else
      echo "ok       $t"
    fi
  done
  if [ "$drift" -gt 0 ]; then
    echo ""
    echo "$drift template(s) missing or stale in $DEST"
    echo "Run: bash scripts/install-templates.sh${TARGET:+ $TARGET}"
    exit 1
  fi
  echo ""
  echo "all templates current in $DEST"
  exit 0
fi

for t in "${TEMPLATES[@]}"; do
  [ -d "$SRC/$t" ] || { echo "error: missing source template $SRC/$t" >&2; exit 1; }
  rm -rf "${DEST:?}/$t"
  cp -R "$SRC/$t" "$DEST/$t"
done

files=0
for t in "${TEMPLATES[@]}"; do
  files=$((files + $(find "$DEST/$t" -type f | wc -l | tr -d ' ')))
done
echo "Installed ${#TEMPLATES[@]} templates ($files files) into $DEST"
echo ""
echo "Stamp refs (what the template picker will show, and what --template takes):"
for t in "${TEMPLATES[@]}"; do
  for d in "$SRC/$t"/*/; do
    [ -d "$d" ] && echo "  $t/$(basename "$d")"
  done
done
echo ""
echo "Next: cd $TARGET && ./nanoclaw.sh"
echo "Re-run this script after pulling this repo, or the copy goes stale."
