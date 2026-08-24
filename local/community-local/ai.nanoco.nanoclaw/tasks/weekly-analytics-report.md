---
schedule: "19 14 * * 0"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, curl, jq. The GA4 OAuth bearer is injected by the OneCLI proxy
  # for analyticsdata.googleapis.com — no credential belongs in this file.
  #
  # WHY THIS IS A POST, AND WHY IT IS STILL READ-ONLY.
  # This is the only POST anywhere in the task scripts, so it deserves an
  # explanation rather than a raised eyebrow during an egress or scope audit.
  # GA4's Data API takes its query as a JSON request body (date range + which
  # metrics), which is far too structured for a query string — so Google made
  # `properties/{id}:runReport` a POST. It is a QUERY verb, not a write: it
  # returns rows and changes nothing on the property.
  #   - Host `analyticsdata.googleapis.com` = read/report only.
  #   - Writes/management live on `analyticsadmin.googleapis.com`, which this
  #     system never calls and which you should NOT enable in the Cloud project.
  #   - The required GA4 role is therefore Viewer. If a Viewer-scoped token can
  #     run this call, that alone proves it isn't mutating anything.
  # Consequence for OneCLI: a request-hold rule that gates on HTTP method would
  # flag this harmless report. Match on host+path if you gate anything here.
  DATA="/workspace/agent/plugin-data/community-local"
  mkdir -p "$DATA"
  if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi
  PROPERTY_ID="${GA4_PROPERTY_ID:-}"
  if [ -z "$PROPERTY_ID" ]; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set GA4_PROPERTY_ID in plugin-data/community-local/config.env"}}'
    exit 0
  fi
  HIST="$DATA/traffic-history.json"
  if [ ! -f "$HIST" ]; then echo '[]' > "$HIST"; fi
  RESP=$(curl -sS --max-time 25 -X POST \
    "https://analyticsdata.googleapis.com/v1beta/properties/$PROPERTY_ID:runReport" \
    -H 'Content-Type: application/json' \
    -d '{"dateRanges":[{"startDate":"7daysAgo","endDate":"yesterday"}],"metrics":[{"name":"activeUsers"},{"name":"sessions"},{"name":"screenPageViews"}]}' \
    2>/dev/null || echo '')
  # Guard on the exact field we are about to read, not just `.rows`. `jq -e
  # '.rows'` treats an empty array as truthy, so a valid-but-empty GA4 response
  # ({"rows":[]} — a property with no data in the window) passed this check and
  # then died on `null | tonumber`, aborting under `set -e` with NO JSON at all.
  # A gate that emits nothing is worse than one that reports a failure.
  if [ -z "$RESP" ] || ! printf '%s' "$RESP" | jq -e '.rows[0].metricValues[2].value' >/dev/null 2>&1; then
    echo '{"wakeAgent": true, "data": {"status": "fetch-failed"}}'
    exit 0
  fi
  WEEK=$(printf '%s' "$RESP" | jq -c '{activeUsers: (.rows[0].metricValues[0].value|tonumber), sessions: (.rows[0].metricValues[1].value|tonumber), pageViews: (.rows[0].metricValues[2].value|tonumber)}' 2>/dev/null || echo '')
  if [ -z "$WEEK" ]; then
    echo '{"wakeAgent": true, "data": {"status": "fetch-failed", "hint": "GA4 responded but the metric values were not parseable as numbers"}}'
    exit 0
  fi
  PREV=$(jq -c '.[-1].metrics // {}' "$HIST")
  jq -c --argjson m "$WEEK" --arg d "$(date -u +%Y-%m-%d)" \
    '. + [{date: $d, metrics: $m}] | .[-26:]' "$HIST" > "$HIST.tmp" && mv "$HIST.tmp" "$HIST"
  printf '{"wakeAgent": true, "data": {"status": "ok", "week": %s, "previous": %s}}\n' "$WEEK" "$PREV"
---
Write the weekly traffic report from `scriptOutput.week` and
`scriptOutput.previous` (the prior week — already fetched, don't re-query). If
`status` is `fetch-failed`, report that plainly and stop.

**If `previous` is `{}` (empty)**: this is the first week ever recorded —
there is no prior week to compare against. Report this week's numbers as a
baseline and say plainly "first week tracked, no week-over-week comparison
yet." **Never report a 0% (or any) delta from an empty `previous`** — a real
install had this default to "0% change" on three metrics simultaneously right
after a run of failures, which read as suspicious/fabricated data rather than
what it actually was (nothing to compare against yet).

Every number carries its window and its week-over-week delta. Explain a sharp
move only if you actually verified the cause; otherwise report the move and mark
the cause unverified.

Hand it to your lead — you don't post it to a channel yourself.
