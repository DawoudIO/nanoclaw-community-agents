---
schedule: "29 */6 * * *"
script: |
  #!/bin/bash
  set -uo pipefail
  # Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
  #
  # Every PR merged into the product repo, checked for "does the documentation
  # still tell the truth?" — and if not, the agent drafts a docs PR.
  #
  # WHY A SEPARATE TASK FROM docs-gap-review. Both are about documentation and
  # they must not overlap, because three agents claiming docs-currency with
  # different triggers is how the same page gets proposed twice:
  #   docs-gap-review (the LEAD)  — trigger: USERS keep asking the same thing.
  #                                 A gap in what's documented at all.
  #   docs-currency-watch (HERE)  — trigger: CODE CHANGED. What is documented is
  #                                 now wrong. Reachable only from the diff.
  # Different signals, different owners, no shared state.
  DATA="/workspace/agent/plugin-data/community-coding"
  mkdir -p "$DATA"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi

  # The docs target is what makes this task possible at all. Unset = the project
  # has no docs site configured, and this stays silent forever rather than
  # inventing somewhere to put a PR.
  DOCS_REPO="${DOCS_REPO:-}"
  if [ -z "$DOCS_REPO" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set DOCS_REPO (and optionally DOCS_PATH) in plugin-data/community-coding/config.env — the project has no docs target, so there is nowhere to send a docs PR"}}'
    exit 0
  fi
  # Which repo's merges we watch. PRODUCT_REPO if set, else the first entry of
  # COMMUNITY_REPOS — "the main repo" in the owner's words.
  SRC="${PRODUCT_REPO:-}"
  [ -z "$SRC" ] && SRC=$(printf '%s' "${COMMUNITY_REPOS:-}" | awk '{print $1}')
  if [ -z "$SRC" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set PRODUCT_REPO or COMMUNITY_REPOS in plugin-data/community-coding/config.env"}}'
    exit 0
  fi
  DOCS_PATH="${DOCS_PATH:-}"
  # Cap per run. A merge queue that lands 40 PRs overnight must not turn into 40
  # file-listing calls and one enormous wake; the ledger means the rest are
  # picked up next run.
  MAX_PER_RUN="${DOCS_WATCH_MAX:-6}"
  case "$MAX_PER_RUN" in ''|*[!0-9]*) MAX_PER_RUN=6;; esac

  NOW=$(date +%s)
  SINCE=$(date -u -d "@$((NOW - 604800))" +%Y-%m-%d 2>/dev/null \
       || date -u -r "$((NOW - 604800))" +%Y-%m-%d 2>/dev/null || echo "")
  if [ -z "$SINCE" ]; then
    echo '{"wakeAgent": true, "data": {"status": "date-unavailable", "hint": "neither GNU nor BSD date worked in this image"}}'
    exit 0
  fi
  SEEN="$DATA/docs-currency-seen.txt"
  touch "$SEEN"

  # The release the docs change belongs to. Docs must land AFTER the code ships,
  # never before — a docs site describing an unreleased fix is actively wrong for
  # everyone reading it today. So every docs PR carries a version, and the
  # version comes from the source PR's milestone where the project uses them.
  # `latest_release` is here so the agent can tell "already shipped" (merge-able
  # now) from "still unreleased" (hold the docs PR).
  LATEST_REL=$(curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$SRC/releases/latest" 2>/dev/null \
    | jq -r '.tag_name // empty' 2>/dev/null || echo "")
  [ -z "$LATEST_REL" ] && LATEST_REL="none"

  RESP=$(curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
    "https://api.github.com/search/issues?q=repo:$SRC+is:pr+is:merged+merged:%3E%3D$SINCE&sort=updated&order=desc&per_page=50" 2>/dev/null || echo "")
  if [ -z "$RESP" ] || ! printf '%s' "$RESP" | jq -e '.items' >/dev/null 2>&1; then
    echo '{"wakeAgent": true, "data": {"status": "fetch-failed", "hint": "could not list merged PRs — 403 usually means the token lacks Issues/PR read on the product repo"}}'
    exit 0
  fi

  SEEN_JSON=$(jq -R -s -c 'split("\n") | map(select(length > 0))' < "$SEEN" 2>/dev/null || echo '[]')
  CANDIDATES=$(printf '%s' "$RESP" | jq -c --argjson seen "$SEEN_JSON" '
    [ .items[]
      | select(((.number|tostring) | IN($seen[])) | not)
      | {number, title: (.title[0:160]), url: .html_url, author: .user.login,
         merged_at: (.closed_at // null), labels: [.labels[]?.name],
         milestone: (.milestone.title // null)} ]' 2>/dev/null || echo '[]')
  TOTAL_NEW=$(printf '%s' "$CANDIDATES" | jq 'length')
  BATCH=$(printf '%s' "$CANDIDATES" | jq -c --argjson n "$MAX_PER_RUN" '.[0:$n]')
  DEFERRED=$(( TOTAL_NEW - $(printf '%s' "$BATCH" | jq 'length') ))
  [ "$DEFERRED" -lt 0 ] && DEFERRED=0

  if [ "$(printf '%s' "$BATCH" | jq 'length')" -eq 0 ]; then
    echo '{"wakeAgent": false, "data": {"status": "no-new-merges"}}'
    exit 0
  fi

  # Per PR, the changed-file list — this is what makes the docs judgment
  # possible, and it is why the batch is capped.
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  i=0
  for N in $(printf '%s' "$BATCH" | jq -r '.[].number'); do
    (
      FILES=$(curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$SRC/pulls/$N/files?per_page=100" 2>/dev/null || echo "")
      if [ -z "$FILES" ] || ! printf '%s' "$FILES" | jq -e 'type=="array"' >/dev/null 2>&1; then
        printf '{"number": %s, "files": null, "touched_docs": null}\n' "$N" > "$TMP/$i.json"
      else
        # touched_docs: did this PR already update the docs itself? If the docs
        # live in this same repo under DOCS_PATH, a PR that changed files there
        # has probably already handled it — a strong signal, not a certainty, so
        # it is reported rather than used to silently drop the PR.
        printf '%s' "$FILES" | jq -c --arg n "$N" --arg dp "$DOCS_PATH" '
          {number: ($n|tonumber),
           files: [.[] | {path: .filename, status, changes}] | .[0:40],
           file_count: length,
           touched_docs: (if ($dp | length) > 0
                          then ([.[] | select(.filename | startswith($dp))] | length > 0)
                          else ([.[] | select(.filename | test("(^|/)(docs?|documentation)/"; "i"))] | length > 0) end)}' \
          > "$TMP/$i.json" 2>/dev/null \
          || printf '{"number": %s, "files": null, "touched_docs": null}\n' "$N" > "$TMP/$i.json"
      fi
    ) &
    i=$((i+1))
  done
  wait

  DETAIL=$(cat "$TMP"/*.json 2>/dev/null | jq -c -s '.' 2>/dev/null || echo '[]')
  MERGED=$(jq -c -n --argjson b "$BATCH" --argjson d "$DETAIL" '
    [ $b[] as $pr | ($d[] | select(.number == $pr.number)) as $det
      | $pr + {files: $det.files, file_count: $det.file_count, touched_docs: $det.touched_docs} ]' 2>/dev/null || echo "$BATCH")

  # Ack now. At this cadence a re-wake on the same PR every run is worse than
  # missing one: the agent writes its own follow-up state when it opens a PR.
  printf '%s' "$BATCH" | jq -r '.[].number' >> "$SEEN" 2>/dev/null || true
  tail -n 400 "$SEEN" > "$SEEN.t" 2>/dev/null && mv "$SEEN.t" "$SEEN"

  MISSING_MS=$(printf '%s' "$MERGED" | jq '[.[] | select(.milestone == null)] | length')
  printf '{"wakeAgent": true, "data": {"status": "new-merges", "source_repo": "%s", "docs_repo": "%s", "docs_path": "%s", "latest_release": "%s", "count": %s, "deferred": %s, "without_milestone": %s, "merged": %s}}\n' \
    "$SRC" "$DOCS_REPO" "$DOCS_PATH" "$LATEST_REL" "$(printf '%s' "$MERGED" | jq 'length')" "$DEFERRED" "$MISSING_MS" "$MERGED"
---

Merged PRs, checked against the documentation. When code changed what the docs
describe, you draft the docs PR.

**If `status` is `not-configured`**, the project has no `DOCS_REPO` — nothing
to do, and nothing to report.

**If `status` is `fetch-failed`**: report it. A `403` means the token lacks
read on the product repo.

**If `deferred` is non-zero**, more PRs merged than the per-run cap. They are
not lost — they surface next run. Mention the number so a merge-queue burst is
visible rather than looking like a quiet period.

## 1. Does this merge actually change the docs?

For each entry in `merged` you get title, labels, `files` (path/status/changes),
`file_count`, and `touched_docs`.

**Most merges need nothing.** A refactor, a test, a dependency bump, an
internal rename: no docs consequence. Say so in one line and move on. The
failure mode here is opening a docs PR for every merge, which trains
maintainers to ignore docs PRs.

It needs a docs change when the merge altered something a *reader* can
observe: a CLI flag, a config key, an API response, a default, a setup step, a
supported version, an error message someone would search for, or behaviour a
documented walkthrough depends on.

**`touched_docs: true`** means the PR already changed files under the docs
path. That's a strong signal the author handled it — check whether their change
is complete, and if it is, record it and move on. Don't open a second PR to
redo someone's work.

## 2. Draft the docs PR — but hold it for the release

**This is the rule that matters: docs land AFTER the code ships, never before.**
A docs site describing a fix that isn't released yet is wrong for every person
reading it today, and worse than being briefly out of date, because it is
confidently wrong rather than merely stale.

So every docs PR you open carries the version it belongs to:

- **Use the source PR's `milestone`** as the version. That is the project's own
  answer to "which release is this in", so prefer it over any inference.
- **No milestone?** `without_milestone` counts these. Use `latest_release` to
  reason: work merged after the latest release belongs to the *next* one. Put
  the docs PR up labelled `docs-pending-release` and say in the body that the
  target version is unconfirmed — then ask your lead to get the version from
  the owner. Do not guess a version number into a title.
- **Title**: `docs: <what changed> (<version>)` so a human scanning open PRs
  sees the version without opening anything.
- **Open it as a DRAFT**, and say in the body: which merged PR it documents,
  what a reader will now see, and that it must not merge until `<version>` is
  released.
- Apply the same milestone on the docs PR where the docs repo has one.

**When the release ships, these get merged** — that is the whole point of the
version tag: at release time someone filters open docs PRs by milestone and
merges the set. The lead's `release-announcement-watch` surfaces them on a new
release. You do not merge them yourself.

**If the version is already released** (the merge predates or matches
`latest_release`), the docs are simply late — mark the PR ready for review
rather than draft, and say it is safe to merge now. Being late is fine; being
early is not.

A docs PR that misses its release is not a failure either. It gets merged on
approval, or the next release cycle sweeps it up. Nothing is lost by waiting.

## Scope

Docs prose only — the docs repo, nothing else. Never edit the product repo
here, never mark your own PR ready when it is version-gated, and never merge
anything. Write for a reader who does not know the code: if you cannot explain
what changed without describing the diff, say so and hand it to your lead,
which has the better voice for user-facing text.

Report to your lead: what you drafted with links, what needed nothing, and any
version you could not determine.
