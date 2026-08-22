---
schedule: "38 13 * * 1-5"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
  # Event-driven gate: content drafting was previously an every-weekday wake —
  # a daily marketing draft for a project with no daily news is just a review
  # queue pointed at the owner. Now the cron still runs on weekdays but the
  # agent wakes only on a real trigger: a new stable release on the watched
  # repo (releases are the strongest content hook there is), or a 7-day floor
  # so evergreen/pipeline content still gets a weekly slot.
  DATA="/workspace/agent/plugin-data/community-marketing"
  mkdir -p "$DATA"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  CONTENT_REPO="${CONTENT_REPO:-}"
  if [ -z "$CONTENT_REPO" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set CONTENT_REPO in plugin-data/community-marketing/config.env"}}'
    exit 0
  fi
  TRIGGER=""
  RELEASE_JSON=null
  WATCH="${RELEASE_WATCH_REPO:-}"
  if [ -n "$WATCH" ]; then
    RESP=$(curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$WATCH/releases/latest" 2>/dev/null) || RESP=""
    TAG=$(printf '%s' "$RESP" | jq -r '.tag_name // empty' 2>/dev/null || echo "")
    if [ -n "$TAG" ]; then
      BASE_F="$DATA/content-last-release.txt"
      OLD=$(cat "$BASE_F" 2>/dev/null || echo "")
      printf '%s' "$TAG" > "$BASE_F"
      # A release trigger missed here is caught by the weekly floor, so
      # advancing the baseline in-script is acceptable for content (unlike
      # announcements, where a lost release announcement is a real loss).
      if [ -n "$OLD" ] && [ "$TAG" != "$OLD" ]; then
        TRIGGER="release"
        RELEASE_JSON=$(printf '%s' "$RESP" | jq -c '{tag: .tag_name, name: (.name // .tag_name), url: .html_url}' 2>/dev/null || echo null)
      fi
    fi
  fi
  LASTWAKE_F="$DATA/content-last-draft-wake"
  DAYS=999
  if [ -f "$LASTWAKE_F" ]; then
    NOW_EPOCH=$(date +%s)
    LW=$(date -u -d "$(cat "$LASTWAKE_F")" +%s 2>/dev/null || date -u -j -f %Y-%m-%d "$(cat "$LASTWAKE_F")" +%s 2>/dev/null || echo 0)
    DAYS=$(( (NOW_EPOCH - LW) / 86400 ))
  fi
  if [ -z "$TRIGGER" ] && [ "$DAYS" -ge 7 ]; then TRIGGER="weekly"; fi
  if [ -z "$TRIGGER" ]; then
    echo '{"wakeAgent": false, "data": {"status": "no-trigger"}}'
  else
    date -u +%Y-%m-%d > "$LASTWAKE_F"
    printf '{"wakeAgent": true, "data": {"status": "draft", "trigger": "%s", "release": %s}}\n' "$TRIGGER" "$RELEASE_JSON"
  fi
---
Only invoked on a real content trigger — `scriptOutput.trigger` says which:

- **`release`**: a new stable release shipped on the watched repo
  (`scriptOutput.release` has tag/name/url). Releases are the strongest
  content hook a project gets — draft around it: what shipped, why a user
  cares, in the project's voice.
- **`weekly`**: the 7-day floor — no event fired, but the pipeline gets one
  evergreen slot a week (a how-to, a community highlight, something from the
  content calendar). If there's genuinely nothing worth drafting, say so in
  one line rather than manufacturing filler — a thin post is worse than no
  post, and next week's slot comes regardless.

Draft per `skills/marketing-ops/references/content-workflow.md` and the
project's own brand/strategy source of truth. One draft per wake, committed
to a branch and opened as a pull request — never posted anywhere directly.
Reference the strategy doc you drew on, and say which content pillar or
campaign it belongs to so a reviewer can judge fit quickly.

Hand the PR link to your lead.
