#!/bin/bash
set -euo pipefail
# Deps: bash, git, jq. GitHub auth injected by the OneCLI proxy for the
# `github.com` (git) host — same vault entry class workspace-backup uses,
# distinct from `api.github.com` (REST). Public repos need no credential.
#
# Keeps a shallow, read-only local mirror of every repo in MIRROR_REPOS
# current — the project's full repo map (product/docs/site/marketing/wiki),
# not just the ones triaged for issues/PRs. A GitHub wiki is just a repo
# named "owner/repo.wiki" — write it into MIRROR_REPOS exactly like that,
# no special-casing needed here.
#
# This is NOT a cache of issues/PRs/releases — those only exist via the
# GitHub API and still need a live call; this mirror only ever holds the
# current tree of tracked branches.
#
# Wakes on a real content change (so the agent can read what changed and
# flag anything worth a human's attention — a wiki page contradicting
# current code, a docs edit that needs review) OR on failure. Silent only
# when literally nothing moved since the last run.
DATA="/workspace/agent/plugin-data/community-local"
MIRRORS="$DATA/repo-mirror"
mkdir -p "$MIRRORS"
if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
REPOS="${MIRROR_REPOS:-${COMMUNITY_REPOS:-}}"
if [ -z "$REPOS" ]; then
  echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set MIRROR_REPOS (or COMMUNITY_REPOS) in plugin-data/community-local/config.env"}}'
  exit 0
fi
FAILED="[]"
CHANGED="[]"
for REPO in $REPOS; do
  SAFEREPO=$(printf '%s' "$REPO" | tr '/' '_')
  DIR="$MIRRORS/$SAFEREPO"
  if [ ! -d "$DIR/.git" ]; then
    if ! git clone --quiet --depth 1 "https://github.com/$REPO.git" "$DIR" >/dev/null 2>&1; then
      rm -rf "$DIR"
      FAILED=$(printf '%s' "$FAILED" | jq -c --arg r "$REPO" --arg s "clone-failed" '. + [{repo: $r, symptom: $s}]')
      continue
    fi
    # First clone is a baseline, not a "change" — nothing to diff against yet.
    continue
  fi
  # A dirty or diverged tree means something touched a mirror nothing should
  # write to — surface it rather than silently forcing it back to clean.
  if [ -n "$(git -C "$DIR" status --porcelain 2>/dev/null)" ]; then
    FAILED=$(printf '%s' "$FAILED" | jq -c --arg r "$REPO" --arg s "dirty-tree" '. + [{repo: $r, symptom: $s}]')
    continue
  fi
  OLD_HEAD=$(git -C "$DIR" rev-parse HEAD 2>/dev/null || echo "")
  if ! git -C "$DIR" fetch --quiet --depth 20 origin >/dev/null 2>&1 \
     || ! git -C "$DIR" reset --quiet --hard origin/HEAD >/dev/null 2>&1; then
    FAILED=$(printf '%s' "$FAILED" | jq -c --arg r "$REPO" --arg s "pull-failed" '. + [{repo: $r, symptom: $s}]')
    continue
  fi
  NEW_HEAD=$(git -C "$DIR" rev-parse HEAD 2>/dev/null || echo "")
  if [ -n "$OLD_HEAD" ] && [ "$OLD_HEAD" != "$NEW_HEAD" ]; then
    FILES=$(git -C "$DIR" diff --name-only "$OLD_HEAD" "$NEW_HEAD" 2>/dev/null | head -20 | jq -R -s -c 'split("\n") | map(select(length>0))')
    SUBJECTS=$(git -C "$DIR" log --oneline --format='%s' "$OLD_HEAD..$NEW_HEAD" 2>/dev/null | head -10 | jq -R -s -c 'split("\n") | map(select(length>0))')
    CHANGED=$(printf '%s' "$CHANGED" | jq -c --arg r "$REPO" --argjson f "$FILES" --argjson s "$SUBJECTS" \
      '. + [{repo: $r, files_changed: $f, commits: $s}]')
  fi
done
if [ "$(printf '%s' "$FAILED" | jq 'length')" -eq 0 ] && [ "$(printf '%s' "$CHANGED" | jq 'length')" -eq 0 ]; then
  echo '{"wakeAgent": false, "data": {"status": "ok"}}'
else
  printf '{"wakeAgent": true, "data": {"status": "attention", "failed": %s, "changed": %s}}\n' "$FAILED" "$CHANGED"
fi
