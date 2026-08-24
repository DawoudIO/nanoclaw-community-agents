---
schedule: "5 */3 * * *"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
  # /releases/latest already excludes drafts and prereleases — only stable
  # releases reach here. Bootstrap seeds the baseline without announcing
  # (a fresh install shouldn't retroactively announce whatever's already
  # shipped); only a genuinely new release after that wakes the agent.
  # The script does NOT advance the baseline on a new release — the AGENT
  # writes the tag to the baseline file after actually posting, so a lost
  # wake or failed post re-surfaces the release next run instead of it
  # vanishing unannounced. Duplicates beat losses (same design as the
  # security-advisory sweep's ack-after-handoff).
  DATA="/workspace/agent/plugin-data/community-support"
  mkdir -p "$DATA"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  # RELEASE_WATCH_REPOS is an OPTIONAL narrower override, falling back to
  # COMMUNITY_REPOS. Announcing every merge-worthy repo's releases is often
  # wrong: a docs site or a content repo never cuts a GitHub Release, and
  # without this override they wake this gate every 3h for nothing (fixed
  # separately, see the 404-handling note below) — but the *right* fix for a
  # project that genuinely only wants its main product repo announced is to
  # not watch the others in the first place. Set it to a subset of
  # COMMUNITY_REPOS, e.g. just the primary product repo.
  REPOS="${RELEASE_WATCH_REPOS:-${COMMUNITY_REPOS:-}}"
  if [ -z "$REPOS" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set RELEASE_WATCH_REPOS (or COMMUNITY_REPOS) in plugin-data/community-support/config.env"}}'
    exit 0
  fi
  TMP=$(mktemp -d)
  i=0
  for REPO in $REPOS; do
    (
      SAFEREPO=$(printf '%s' "$REPO" | tr '/' '_')
      BASE_F="$DATA/last-announced-release-$SAFEREPO.txt"
      # No -f: it discards the response body on ANY HTTP error status, which
      # made a legitimate 404 (repo has never published a release — normal for
      # a docs site or content repo) indistinguishable from a real auth/network
      # failure. Capture the status code alongside the body instead, so 404
      # reaches "no-releases" and everything else still reaches "fetch-failed".
      RAW=$(curl -sS --max-time 8 -w '\n%{http_code}' -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null) || RAW=""
      HTTP_CODE=$(printf '%s' "$RAW" | tail -n1)
      RESP=$(printf '%s' "$RAW" | sed '$d')
      if [ "$HTTP_CODE" = "404" ]; then
        # No releases yet - not a failure, just nothing to announce.
        printf '{"repo": "%s", "status": "no-releases"}\n' "$REPO" > "$TMP/$i.json"
        exit 0
      fi
      if [ "$HTTP_CODE" != "200" ] || [ -z "$RESP" ]; then
        printf '{"repo": "%s", "status": "fetch-failed"}\n' "$REPO" > "$TMP/$i.json"
        exit 0
      fi
      TAG=$(printf '%s' "$RESP" | jq -r '.tag_name // empty' 2>/dev/null)
      if [ -z "$TAG" ]; then
        printf '{"repo": "%s", "status": "fetch-failed"}\n' "$REPO" > "$TMP/$i.json"
        exit 0
      fi
      OLD=$(cat "$BASE_F" 2>/dev/null || echo "")
      if [ -z "$OLD" ]; then
        printf '%s' "$TAG" > "$BASE_F"
        printf '{"repo": "%s", "status": "baseline-initialized", "tag": "%s"}\n' "$REPO" "$TAG" > "$TMP/$i.json"
        exit 0
      fi
      if [ "$TAG" = "$OLD" ]; then
        printf '{"repo": "%s", "status": "no-new-release"}\n' "$REPO" > "$TMP/$i.json"
        exit 0
      fi
      RELEASE=$(printf '%s' "$RESP" | jq -c '{tag: .tag_name, name: (.name // .tag_name), url: .html_url, published_at: .published_at, author: (.author.login // "unknown"), body: (.body // "")}' 2>/dev/null || echo null)
      printf '{"repo": "%s", "status": "new-release", "baseline_file": "plugin-data/community-support/last-announced-release-%s.txt", "release": %s}\n' "$REPO" "$SAFEREPO" "$RELEASE" > "$TMP/$i.json"
    ) &
    i=$((i+1))
  done
  wait
  ALL=$(cat "$TMP"/*.json | jq -c -s '.')
  rm -rf "$TMP"
  FAILED=$(printf '%s' "$ALL" | jq -c '[.[] | select(.status=="fetch-failed") | .repo]')
  NEW=$(printf '%s' "$ALL" | jq -c '[.[] | select(.status=="new-release")]')
  if [ "$(printf '%s' "$FAILED" | jq 'length')" -gt 0 ] && [ "$(printf '%s' "$NEW" | jq 'length')" -eq 0 ]; then
    printf '{"wakeAgent": true, "data": {"status": "fetch-failed", "failed_repos": %s}}\n' "$FAILED"
  elif [ "$(printf '%s' "$NEW" | jq 'length')" -eq 0 ]; then
    echo '{"wakeAgent": false, "data": {"status": "quiet"}}'
  else
    printf '{"wakeAgent": true, "data": {"status": "new-release", "releases": %s, "failed_repos": %s}}\n' "$NEW" "$FAILED"
  fi
---
Only invoked when a genuinely new stable release was published (or a fetch
failed with nothing new to report instead — surface that plainly and stop;
`401/403` = token wiring, `502` = sandbox network policy).

For each entry in `scriptOutput.releases`: draft one Discord announcement for
the team-lead tier's announcements channel — release name/version, 2–4 real
highlights pulled from the actual release notes (summarize, don't dump the
full changelog), and a card button linking to `url`. If the project's growth
goals include developers/contributors, credit contributors by name if the
notes list them (see the marketing agent's growth-playbook — this is the
cheapest developer-growth lever there is). If `body` is long, attach the full
notes as a downloadable `.md` per the 2,000-character rule and keep the
message itself to the highlights.

This is already-public information (the release is live on GitHub before you
ever see it) — **post directly, no approval needed**, same as any other
already-shipped, publicly-disclosed content. No owner DM required either; the
owner already knows they shipped it.

**Then ack**: after the announcement is actually posted, write the release's
tag (just the tag string, nothing else) to the file named in that entry's
`baseline_file`. The script deliberately does not advance this baseline
itself — your write after posting is the acknowledgment, so a lost wake or a
failed post re-surfaces the same release next run instead of it vanishing
unannounced. If you see the same release twice, check the channel before
posting again — a duplicate check is cheap, a silently skipped announcement
isn't. Duplicates beat losses.

Never announce a prerelease or draft — the script only ever sees stable
releases, so if something looks unfinished, don't post it; flag it to your
owner instead as a likely fetch anomaly.

## The docs PRs waiting on this release

A release is the trigger for merging the documentation that describes it. The
Reviewer's `docs-currency-watch` drafts a docs PR for every merge that changed
observable behaviour and **holds it as a draft**, tagged with the version,
because docs describing an unreleased fix are wrong for everyone reading them
today.

So on a new stable release, before you announce anything: list the open docs
PRs whose milestone or `docs-pending-release` label matches this version, and
hand the owner that list with the release note. They are ready to merge now —
the hold existed only until the code shipped.

Say plainly if the list is empty (nothing needed documenting, which is common
for a patch release) and if any docs PR has no version at all, since that is
the one case that silently never gets swept up. Do not merge them yourself.
