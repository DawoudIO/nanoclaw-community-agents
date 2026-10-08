#!/bin/bash
set -uo pipefail
# Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
#
# PROJECT CONTEXT — daily. The repos change every day; the agent's picture of
# them must not be whatever it remembered at stamp time. This gate reads, for
# every repo in CONTEXT_REPOS (default COMMUNITY_REPOS):
#   - what landed on the default branch since the last run (commits + files),
#   - what is RELEASED (latest release tag) versus what is MERGED BUT NOT
#     RELEASED (default branch ahead of that tag), and the open milestones —
#     so "is X available?" is answered from facts, not from training data,
#   - which agent skills (.agents/skills/**) and docs changed, so the agent
#     re-reads exactly those files and nothing else.
# It writes release-state.csv and recent-changes.csv every run (the agent
# reads them with cat when asked — no fetch, no wake) and wakes the model
# ONLY for what it must act on: a changed skill or docs file to re-read, a
# release that shipped, a rewritten branch, or a repo it could not read.
# Ordinary code commits are recorded, never a wake — the repos commit daily
# and a daily Sonnet wake to read a diff would break the 0-token design.
DATA="/workspace/agent/plugin-data/community-manager"
mkdir -p "$DATA"

# --- local telemetry (best-effort; never blocks the gate) -------------------
mkdir -p "$DATA/telemetry" 2>/dev/null || true
exec > >(tee >(sed -u "s/^{/{\"_ts\":\"$(date -u +%FT%TZ)\",/" >> "$DATA/telemetry/project-context.jsonl" 2>/dev/null) 2>/dev/null)
# config.env is parsed, never sourced: the model writes into this same
# directory, so a line planted here must stay a string, never become code.
if [ -f "$DATA/config.env" ]; then
  while IFS='=' read -r k v; do
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    export "$k=$v"
  done < <(grep -E '^[A-Z][A-Z0-9_]*=' "$DATA/config.env")
fi
REPOS="${CONTEXT_REPOS:-${COMMUNITY_REPOS:-}}"
if [ -z "$REPOS" ]; then
  echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set CONTEXT_REPOS (or COMMUNITY_REPOS) in plugin-data/community-manager/config.env"}}'
  exit 0
fi

TODAY_D=$(date -u +%Y-%m-%d)
STATE="$DATA/context-heads.csv"          # repo,head_sha,release_tag,checked_at
RELEASE_STATE="$DATA/release-state.csv"  # rewritten every run; what the agent cats
CHANGES="$DATA/recent-changes.csv"       # date,repo,sha,author,subject — appended daily, trimmed to ~400 rows
[ -s "$CHANGES" ] || echo 'date,repo,sha,author,subject' > "$CHANGES"
[ -s "$STATE" ] || echo 'repo,head_sha,release_tag,checked_at' > "$STATE"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
API="https://api.github.com/repos"
api() { curl -fsS --max-time 10 -H "Accept: application/vnd.github+json" "$1" 2>/dev/null; }

i=0
PIDS=()
for REPO in $REPOS; do
  if ! [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    jq -nc --arg r "$REPO" '{repo:$r, status:"bad-config"}' > "$TMP/$i.json"; i=$((i+1)); continue
  fi
  (
    PREV_SHA=$(awk -F, -v r="$REPO" '$1==r {print $2}' "$STATE" | tail -n 1)
    PREV_TAG=$(awk -F, -v r="$REPO" '$1==r {print $3}' "$STATE" | tail -n 1)

    api "$API/$REPO/commits?per_page=1" > "$TMP/$i.head" &
    api "$API/$REPO/releases/latest" > "$TMP/$i.rel" &
    api "$API/$REPO/milestones?state=open&sort=due_on&direction=asc&per_page=10" > "$TMP/$i.ms" &
    wait

    HEAD_SHA=$(jq -r '.[0].sha // empty' < "$TMP/$i.head" 2>/dev/null)
    if [ -z "$HEAD_SHA" ]; then
      jq -nc --arg r "$REPO" '{repo:$r, status:"fetch-failed"}' > "$TMP/$i.json"; exit 0
    fi
    # No release yet is a real state (404), not a failure: tag stays null.
    REL=$(jq -c 'if .tag_name then {tag:.tag_name, published_at:.published_at, url:.html_url} else null end' < "$TMP/$i.rel" 2>/dev/null || echo null)
    [ -n "$REL" ] || REL=null
    TAG=$(printf '%s' "$REL" | jq -r '.tag // empty')
    MILESTONES=$(jq -c 'if type=="array" then [.[] | {title, open: .open_issues, closed: .closed_issues, due_on}] else [] end' < "$TMP/$i.ms" 2>/dev/null || echo '[]')

    # Released vs not: everything on the default branch past the release tag.
    UNRELEASED=null
    if [ -n "$TAG" ]; then
      if api "$API/$REPO/compare/$TAG...$HEAD_SHA" > "$TMP/$i.unrel"; then
        UNRELEASED=$(jq -c '{ahead_by, commits: [.commits[-50:][] | {sha: .sha[0:7], subject: (.commit.message | split("\n")[0] | .[0:120]), date: .commit.committer.date[0:10]}]}' < "$TMP/$i.unrel" 2>/dev/null || echo null)
      else
        UNRELEASED='{"status":"fetch-failed"}'
      fi
    fi

    # Delta since last run. First sight of a repo is a baseline, not a change.
    STATUS=unchanged; DELTA=null
    if [ -z "$PREV_SHA" ]; then
      STATUS=baseline
    elif [ "$PREV_SHA" != "$HEAD_SHA" ]; then
      STATUS=changed
      if api "$API/$REPO/compare/$PREV_SHA...$HEAD_SHA" > "$TMP/$i.delta"; then
        DELTA=$(jq -c '{
          total_commits,
          commits: [.commits[-50:][] | {sha: .sha[0:7], subject: (.commit.message | split("\n")[0] | .[0:120]), author: (.author.login // .commit.author.name), date: .commit.committer.date[0:10]}],
          files_changed: (.files | length),
          skills_changed: [.files[] | select(.filename | test("^\\.agents/skills/|^\\.claude/skills/")) | .filename],
          docs_changed: [.files[] | select((.filename | test("^docs/|\\.mdx?$")) and (.filename | test("^\\.agents/skills/|^\\.claude/skills/") | not)) | .filename] | .[0:40],
          changelog_changed: ([.files[] | select(.filename | test("^CHANGELOG"))] | length > 0)
        }' < "$TMP/$i.delta" 2>/dev/null || echo null)
      fi
      # compare fails when PREV_SHA left history (force push, branch rewrite):
      # say so rather than pretend nothing happened.
      [ "$DELTA" = "null" ] && DELTA='{"status":"history-rewritten","hint":"previous head is gone; re-read the repo"}'
    fi
    RELEASE_CHANGED=false
    [ -n "$PREV_SHA" ] && [ "$TAG" != "${PREV_TAG:-}" ] && RELEASE_CHANGED=true

    jq -nc --arg r "$REPO" --arg s "$STATUS" --arg h "$HEAD_SHA" --argjson rel "$REL" --argjson rc "$RELEASE_CHANGED" \
      --argjson un "$UNRELEASED" --argjson ms "$MILESTONES" --argjson d "$DELTA" \
      '{repo:$r, status:$s, head: $h[0:7], release: $rel, release_changed: $rc, unreleased: $un, milestones: $ms, since_last_run: $d}' > "$TMP/$i.json"
    printf '%s,%s,%s,%s\n' "$REPO" "$HEAD_SHA" "$(printf '%s' "$TAG" | tr -d ',\r\n')" "$TODAY_D" > "$TMP/$i.state"
  ) &
  PIDS+=("$!")
  i=$((i+1))
done
wait "${PIDS[@]}"

REPOS_JSON=$(cat "$TMP"/*.json 2>/dev/null | jq -c -s '.' 2>/dev/null || echo '[]')
if [ "$(printf '%s' "$REPOS_JSON" | jq 'length' 2>/dev/null || echo 0)" -eq 0 ]; then
  echo '{"wakeAgent": true, "data": {"status": "fetch-failed", "hint": "no repo produced a result — check the token and the sandbox network policy"}}'
  exit 0
fi

# State: replace each successfully read repo's row, keep failed repos' old
# rows so the next good run still diffs from the last known head.
{ head -n 1 "$STATE"
  for f in "$TMP"/*.state; do [ -f "$f" ] || continue; r=$(cut -d, -f1 "$f"); grep -v "^$r," "$STATE" | grep -v '^repo,'; done | sort -u
  cat "$TMP"/*.state 2>/dev/null; } > "$STATE.tmp" 2>/dev/null && mv "$STATE.tmp" "$STATE"
# recent-changes.csv: every commit since the last run, one row each, so the
# agent answers "what changed this week?" from a file. Subjects are
# sanitised like every other API string that lands in a CSV.
printf '%s' "$REPOS_JSON" | jq -r --arg d "$TODAY_D" '.[] | select(.status == "changed") | .repo as $r
  | (.since_last_run.commits // [])[] | [$d, $r, .sha, (.author // ""), .subject]
  | map(tostring | gsub("[,\"\r\n]"; "_") | if test("^[=+@]") then "_" + . else . end) | join(",")' >> "$CHANGES" 2>/dev/null || true
{ head -n 1 "$CHANGES"; tail -n 400 "$CHANGES" | grep -v '^date,'; } > "$CHANGES.tmp" 2>/dev/null && mv "$CHANGES.tmp" "$CHANGES"
# release-state.csv: the answer to "what is released, what is coming" with
# no model and no fetch — the agent cats this when someone asks.
{ echo 'date,repo,released_tag,released_at,unreleased_commits,next_milestone,milestone_closed,milestone_open,milestone_due'
  printf '%s' "$REPOS_JSON" | jq -r --arg d "$TODAY_D" '.[] | select(.status != "bad-config" and .status != "fetch-failed")
    | [$d, .repo, (.release.tag // ""), (.release.published_at // "" | .[0:10]), (.unreleased.ahead_by // ""),
       (.milestones[0].title // ""), (.milestones[0].closed // ""), (.milestones[0].open // ""), (.milestones[0].due_on // "" | .[0:10])]
    | map(tostring | gsub("[,\"\r\n]"; "_")) | join(",")'; } > "$RELEASE_STATE.tmp" 2>/dev/null && mv "$RELEASE_STATE.tmp" "$RELEASE_STATE"

DEGRADED=$(printf '%s' "$REPOS_JSON" | jq -c '[.[] | select(.status == "fetch-failed" or .status == "bad-config") | .repo]')
CHANGED=$(printf '%s' "$REPOS_JSON" | jq -c '[.[] | select(.status == "changed") | .repo]')
# What actually needs the model: a skill or docs file to re-read, a release
# that shipped, a rewritten branch, the first run. Code commits alone do not.
NEEDS_AGENT=$(printf '%s' "$REPOS_JSON" | jq -c '[.[] | select(
    .status == "baseline" or .release_changed == true
    or ((.since_last_run.skills_changed // []) | length > 0)
    or ((.since_last_run.docs_changed // []) | length > 0)
    or (.since_last_run.changelog_changed == true)
    or (.since_last_run.status == "history-rewritten")) | .repo]')
WAKE=false
[ "$(printf '%s' "$NEEDS_AGENT" | jq 'length')" -gt 0 ] && WAKE=true
[ "$(printf '%s' "$DEGRADED" | jq 'length')" -gt 0 ] && WAKE=true   # a broken fetch must never read as a quiet day
STATUS=unchanged
[ "$(printf '%s' "$CHANGED" | jq 'length')" -gt 0 ] && STATUS=recorded     # commits stored, nothing to re-read
[ "$WAKE" = "true" ] && STATUS=needs-agent
[ "$(printf '%s' "$REPOS_JSON" | jq '[.[] | select(.status == "baseline")] | length')" -eq "$(printf '%s' "$REPOS_JSON" | jq 'length')" ] && STATUS=baseline

jq -nc --argjson w "$WAKE" --arg s "$STATUS" --arg d "$TODAY_D" --argjson r "$REPOS_JSON" --argjson c "$CHANGED" --argjson na "$NEEDS_AGENT" --argjson dg "$DEGRADED" \
  '{wakeAgent:$w, data:{status:$s, date:$d, changed_repos:$c, needs_agent:$na, degraded_repos:$dg, repos:$r}}'
