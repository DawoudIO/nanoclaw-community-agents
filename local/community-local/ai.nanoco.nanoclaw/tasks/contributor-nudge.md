---
schedule: "18 9 * * *"
script: |
  #!/bin/bash
  set -uo pipefail
  # Deps: bash, curl, jq. GitHub auth injected by the OneCLI proxy.
  #
  # First-time contributors sitting in the re-engagement window: their first
  # contribution landed 20-30 days ago and there hasn't been a second one.
  #
  # WHY THIS IS ITS OWN TASK. It was part of dev-metrics-report, and being there
  # was wrong on three counts:
  #   1. Different deliverable. Everything else in that report is a NUMBER to
  #      read. This is a list of PEOPLE for a maintainer to personally follow up
  #      with — an action, not information, and it needs a different audience.
  #   2. It was the one serial network path in an otherwise parallel script, so a
  #      slow run here killed the metrics report with it: both were printed by the
  #      same statement, and a timeout lost the lot.
  #   3. It is a window. Research puts the steepest contributor drop-off in the
  #      first 30 days with re-engagement rare after 90, so missing the window
  #      loses the chance entirely — which deserves its own schedule rather than
  #      riding one shared with cosmetic star counts.
  #
  # The contributor ledger it reads (`known-contributors-<repo>.txt`) is written
  # by dev-metrics-report. Same agent, same plugin-data, so this is a legitimate
  # read — but it does mean this task reports nothing until that one has run at
  # least twice (once to seed, once to record a real first contribution).
  DATA="/workspace/agent/plugin-data/community-local"
  mkdir -p "$DATA"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  REPOS="${COMMUNITY_REPOS:-}"
  if [ -z "$REPOS" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set COMMUNITY_REPOS in plugin-data/community-local/config.env"}}'
    exit 0
  fi
  # Serial API calls, so this is capped. Whoever is skipped today is still inside
  # the window tomorrow — the ledger makes the cap safe.
  MAX_CHECKS="${NUDGE_MAX_CHECKS:-4}"
  case "$MAX_CHECKS" in ''|*[!0-9]*) MAX_CHECKS=4;; esac

  NOW=$(date +%s)
  NUDGES="[]"; DEFERRED=0; NO_LEDGER=""
  for REPO in $REPOS; do
    SAFEREPO=$(printf '%s' "$REPO" | tr '/' '_')
    KNOWN="$DATA/known-contributors-$SAFEREPO.txt"
    if [ ! -f "$KNOWN" ]; then
      NO_LEDGER="$NO_LEDGER $REPO"
      continue
    fi
    SEEN="$DATA/nudge-sent-$SAFEREPO.txt"
    touch "$SEEN"
    CHECKS=0
    while IFS=, read -r UNAME UDATE; do
      [ -z "$UNAME" ] && continue
      [ -z "$UDATE" ] && continue
      # Bootstrap-seeded names have no real first-contribution date, so they must
      # never enter the window — otherwise install day would dump the entire
      # historical contributor list into it at once.
      [ "$UDATE" = "seeded" ] && continue
      grep -qxF "$UNAME" "$SEEN" 2>/dev/null && continue
      UEPOCH=$(date -u -d "$UDATE" +%s 2>/dev/null || date -u -j -f %Y-%m-%d "$UDATE" +%s 2>/dev/null || echo "")
      case "$UEPOCH" in ''|*[!0-9]*) continue;; esac
      AGE_D=$(( (NOW - UEPOCH) / 86400 ))
      [ "$AGE_D" -lt 20 ] && continue
      [ "$AGE_D" -gt 30 ] && continue
      if [ "$CHECKS" -ge "$MAX_CHECKS" ]; then
        DEFERRED=$((DEFERRED+1))
        continue
      fi
      CHECKS=$((CHECKS+1))
      CNT=$(curl -fsS --max-time 8 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:$REPO+is:pr+is:merged+author:$UNAME&per_page=1" 2>/dev/null \
        | jq '.total_count // "e"' 2>/dev/null || echo e)
      case "$CNT" in ''|*e*) continue;; esac   # fetch failed: retry next run, don't ack
      echo "$UNAME" >> "$SEEN"
      if [ "$CNT" -le 1 ]; then
        NUDGES=$(jq -c -n --argjson a "$NUDGES" --arg r "$REPO" --arg u "$UNAME" \
          --arg d "$UDATE" --argjson ad "$AGE_D" \
          '$a + [{repo: $r, username: $u, first_contribution: $d, days_ago: $ad,
                  days_left_in_window: (30 - $ad)}]')
      fi
    done < "$KNOWN"
  done

  COUNT=$(printf '%s' "$NUDGES" | jq 'length')
  WAKE=false
  [ "$COUNT" -gt 0 ] && WAKE=true
  printf '{"wakeAgent": %s, "data": {"status": "%s", "count": %s, "deferred": %s, "repos_without_ledger": "%s", "nudges": %s}}\n' \
    "$WAKE" \
    "$([ "$COUNT" -gt 0 ] && echo in-window || echo nobody-in-window)" \
    "$COUNT" "$DEFERRED" "${NO_LEDGER# }" "$NUDGES"
---

People whose first contribution landed 20–30 days ago and who haven't come
back. This is the highest-leverage window a maintainer has: the drop-off is
steepest in the first 30 days and re-engagement is rare after 90.

**If `status` is `nobody-in-window`** you were not woken. Nothing to do.

**If `repos_without_ledger` is non-empty**, those repos have no contributor
ledger yet — `dev-metrics-report` builds it, and it needs to have run at least
twice (once to seed the existing contributor list, once to record a real first
contribution). Say so plainly rather than reporting those repos as quiet;
"nobody is in the window" and "we aren't tracking yet" look identical
otherwise.

## What to hand over

One line per person in `nudges`: username, what they contributed, how long ago,
and `days_left_in_window`. That last number is why this is worth reading today
rather than next week.

**Name the contribution.** Look up their merged PR and say what it was — "fixed
the CSV delimiter bug" is a reason for a maintainer to reach out; "made a
contribution 24 days ago" is not, and a generic nudge is worse than none.

**Do not write the message and do not contact anybody.** You are surfacing a
list; a maintainer reaching out personally is the entire value, and a templated
bot follow-up would destroy it. Hand it to your lead.

**Don't rank or editorialise.** No "promising contributor", no guesses about why
they haven't returned. Facts and the window.

If `deferred` is non-zero, more people were in the window than the per-run
check cap. Mention the number — they are not lost, they surface tomorrow while
still inside the window.
