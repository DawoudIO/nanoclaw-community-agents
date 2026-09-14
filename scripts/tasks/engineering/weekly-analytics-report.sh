#!/bin/bash
set -euo pipefail
# Deps: bash, curl, jq. The GA4 OAuth bearer is injected by the OneCLI proxy
# for analyticsdata.googleapis.com — no credential belongs in this file.
#
# WHY THESE ARE POSTS, AND WHY THEY ARE STILL READ-ONLY.
# These are the only POSTs anywhere in the task scripts, so they deserve an
# explanation rather than a raised eyebrow during an egress or scope audit.
# GA4's Data API takes its query as a JSON request body (date ranges + which
# dimensions/metrics), which is far too structured for a query string — so
# Google made `properties/{id}:runReport` a POST. It is a QUERY verb, not a
# write: it returns rows and changes nothing on the property.
#   - Host `analyticsdata.googleapis.com` = read/report only.
#   - Writes/management live on `analyticsadmin.googleapis.com`, which this
#     system never calls and which you should NOT enable in the Cloud project.
#   - The required GA4 role is therefore Viewer. If a Viewer-scoped token can
#     run these calls, that alone proves neither is mutating anything.
# Consequence for OneCLI: a request-hold rule that gates on HTTP method would
# flag both harmless reports. Match on host+path if you gate anything here.
DATA="/workspace/agent/plugin-data/community-coding"
mkdir -p "$DATA"
if [ -f "$DATA/config.env" ]; then . "$DATA/config.env"; fi

# GA4_PROPERTIES: comma-separated properties, each either a bare id
# ("253632751") or a "label:id" pair ("demo:362323228") when a readable
# name is worth carrying into the report. One task run covers every
# property listed here — never create a second task file per property.
# GA4_PROPERTY_ID (a single bare id) still works as a one-property
# fallback for configs written before GA4_PROPERTIES existed.
PROPS="${GA4_PROPERTIES:-}"
if [ -z "$PROPS" ] && [ -n "${GA4_PROPERTY_ID:-}" ]; then
  PROPS="${GA4_PROPERTY_ID}"
fi
if [ -z "$PROPS" ]; then
  echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "set GA4_PROPERTIES (id[,label:id...]) or GA4_PROPERTY_ID in plugin-data/community-coding/config.env"}}'
  exit 0
fi

RESULTS='[]'
IFS=',' read -ra PAIRS <<< "$PROPS"
for PAIR in "${PAIRS[@]}"; do
  if [[ "$PAIR" == *:* ]]; then
    LABEL="${PAIR%%:*}"
    PROPERTY_ID="${PAIR#*:}"
  else
    PROPERTY_ID="$PAIR"
    LABEL="property-${PROPERTY_ID}"
  fi
  HIST="$DATA/traffic-history-${LABEL}.json"
  if [ ! -f "$HIST" ]; then echo '[]' > "$HIST"; fi

  # --- Query 1: current vs. prior-week AND prior-month windows, compared
  # directly by GA4 itself (three named dateRanges in one request,
  # distinguished by the dateRange dimension) rather than diffed against
  # our own local ledger. A same-day rerun no longer produces a fake
  # same-day "previous" — every comparison spans a real calendar gap
  # regardless of when this task last ran. YoY still comes from the
  # ledger below (a comparable window a year back needs real history GA4's
  # own date-range comparison can't shortcut its way into on a fresh
  # install) — the ledger's whole job now is YoY plus a longer trend line,
  # not WoW/MoM — a fixed label on a variable window is a lie. ---
  RESP=$(curl -sS --max-time 25 -X POST \
    "https://analyticsdata.googleapis.com/v1beta/properties/$PROPERTY_ID:runReport" \
    -H 'Content-Type: application/json' \
    -d '{
      "dateRanges":[
        {"startDate":"7daysAgo","endDate":"yesterday","name":"current"},
        {"startDate":"14daysAgo","endDate":"8daysAgo","name":"previous_week"},
        {"startDate":"35daysAgo","endDate":"29daysAgo","name":"previous_month"}
      ],
      "dimensions":[{"name":"dateRange"}],
      "metrics":[{"name":"activeUsers"},{"name":"sessions"},{"name":"screenPageViews"},{"name":"engagementRate"}]
    }' 2>/dev/null || echo '')
  # Guard on the exact field we are about to read, not just `.rows`. `jq -e
  # '.rows'` treats an empty array as truthy, so a valid-but-empty GA4
  # response ({"rows":[]}) passed this check and then died on
  # `null | tonumber` under `set -e` with NO JSON at all — worse than
  # reporting a failure.
  CURROW=$(printf '%s' "$RESP" | jq -c '[.rows[]? | select(.dimensionValues[0].value=="current")][0] // empty' 2>/dev/null || echo '')
  if [ -z "$RESP" ] || [ -z "$CURROW" ]; then
    RESULTS=$(jq -c --arg l "$LABEL" --arg id "$PROPERTY_ID" '. + [{label:$l, property_id:$id, status:"fetch-failed"}]' <<< "$RESULTS")
    continue
  fi
  WEEK=$(jq -c '{activeUsers:(.metricValues[0].value|tonumber), sessions:(.metricValues[1].value|tonumber), pageViews:(.metricValues[2].value|tonumber), engagementRate:(.metricValues[3].value|tonumber)}' <<< "$CURROW" 2>/dev/null || echo '')
  if [ -z "$WEEK" ]; then
    RESULTS=$(jq -c --arg l "$LABEL" --arg id "$PROPERTY_ID" '. + [{label:$l, property_id:$id, status:"fetch-failed", hint:"metric values not parseable"}]' <<< "$RESULTS")
    continue
  fi
  extract_row() {
    local name="$1"
    local row
    row=$(printf '%s' "$RESP" | jq -c --arg n "$name" '[.rows[]? | select(.dimensionValues[0].value==$n)][0] // empty' 2>/dev/null || echo '')
    if [ -n "$row" ]; then
      jq -c '{activeUsers:(.metricValues[0].value|tonumber), sessions:(.metricValues[1].value|tonumber), pageViews:(.metricValues[2].value|tonumber), engagementRate:(.metricValues[3].value|tonumber)}' <<< "$row" 2>/dev/null || echo '{}'
    else
      echo '{}'
    fi
  }
  PREV_WEEK=$(extract_row "previous_week")
  PREV_MONTH=$(extract_row "previous_month")

  # YoY from the ledger: nearest dated entry within ±10 days of 364 days ago.
  # A brand-new install has no such entry — that's "not enough history yet",
  # not a failure.
  PREV_YEAR=$(jq -c --arg d "$(date -u +%Y-%m-%d)" '
    (($d | strptime("%Y-%m-%d") | mktime) - (364*86400)) as $target
    | [ .[] | . as $e | ($e.date | strptime("%Y-%m-%d") | mktime) as $t
        | select(($t - $target | fabs) <= (10*86400)) | $e ]
    | sort_by(($target - (.date | strptime("%Y-%m-%d") | mktime)) | fabs)
    | (.[0].metrics // {})' "$HIST" 2>/dev/null || echo '{}')

  jq -c --argjson m "$WEEK" --arg d "$(date -u +%Y-%m-%d)" \
    '. + [{date: $d, metrics: $m}] | .[-370:]' "$HIST" > "$HIST.tmp" && mv "$HIST.tmp" "$HIST"

  # --- Query 2: dimensional breakdown — geography, language, browser, AI
  # referral, and social-media attribution, all from one query; jq buckets
  # rows below rather than a GA4 dimensionFilter, so a parse failure here
  # degrades to "dimensional data unavailable" without invalidating the
  # totals above. ---
  DIM_RESP=$(curl -sS --max-time 25 -X POST \
    "https://analyticsdata.googleapis.com/v1beta/properties/$PROPERTY_ID:runReport" \
    -H 'Content-Type: application/json' \
    -d '{
      "dateRanges":[{"startDate":"7daysAgo","endDate":"yesterday"}],
      "dimensions":[
        {"name":"sessionDefaultChannelGroup"},
        {"name":"sessionSourceMedium"},
        {"name":"sessionSource"},
        {"name":"landingPagePlusQueryString"},
        {"name":"deviceCategory"},
        {"name":"country"},
        {"name":"language"},
        {"name":"browser"}
      ],
      "metrics":[
        {"name":"sessions"},
        {"name":"activeUsers"},
        {"name":"engagedSessions"},
        {"name":"engagementRate"},
        {"name":"averageSessionDuration"},
        {"name":"screenPageViews"}
      ],
      "orderBys":[{"metric":{"metricName":"sessions"},"desc":true}],
      "limit": 500
    }' 2>/dev/null || echo '')

  AI_TRAFFIC='[]'; SOCIAL_TRAFFIC='[]'; TOP_PAGES='[]'; TOP_COUNTRIES='[]'; TOP_LANGUAGES='[]'; LIKELY_AUTOMATED='[]'; DIM_STATUS='ok'
  if [ -z "$DIM_RESP" ] || ! printf '%s' "$DIM_RESP" | jq -e 'type=="object"' >/dev/null 2>&1; then
    DIM_STATUS='fetch-failed'
  else
    ROWS=$(printf '%s' "$DIM_RESP" | jq -c '
      [.rows // [] | .[] | {
        channelGroup: .dimensionValues[0].value,
        sourceMedium: .dimensionValues[1].value,
        source: .dimensionValues[2].value,
        landingPage: .dimensionValues[3].value,
        device: .dimensionValues[4].value,
        country: .dimensionValues[5].value,
        language: .dimensionValues[6].value,
        browser: .dimensionValues[7].value,
        sessions: (.metricValues[0].value|tonumber),
        activeUsers: (.metricValues[1].value|tonumber),
        engagedSessions: (.metricValues[2].value|tonumber),
        engagementRate: (.metricValues[3].value|tonumber),
        avgSessionDuration: (.metricValues[4].value|tonumber),
        pageViews: (.metricValues[5].value|tonumber)
      }]' 2>/dev/null || echo '')
    if [ -z "$ROWS" ]; then
      DIM_STATUS='fetch-failed'
    else
      # Case-insensitive; catches direct AI/LLM referrers and GA4's own
      # native "AI Assistant" channel/medium classification where present.
      AI_TRAFFIC=$(printf '%s' "$ROWS" | jq -c '
        [.[] | select(
          (.source | test("chatgpt|openai|perplexity|claude|gemini|copilot|deepseek|grok|poe|you\\.com|phind"; "i"))
          or (.sourceMedium | test("ai-assistant"; "i"))
          or (.channelGroup | test("^AI Assistant$"; "i"))
        )] | sort_by(-.sessions) | .[0:20]')
      SOCIAL_TRAFFIC=$(printf '%s' "$ROWS" | jq -c '
        [.[] | select(
          (.channelGroup | test("Organic Social|Paid Social"; "i"))
          or (.source | test("linkedin|twitter|x\\.com|t\\.co|facebook|reddit|instagram|youtube|github"; "i"))
        )] | sort_by(-.sessions) | .[0:20]')
      TOP_PAGES=$(printf '%s' "$ROWS" | jq -c '
        group_by(.landingPage)
        | map({page: .[0].landingPage, sessions: (map(.sessions)|add), engagedSessions: (map(.engagedSessions)|add)})
        | sort_by(-.sessions) | .[0:5]')
      TOP_COUNTRIES=$(printf '%s' "$ROWS" | jq -c '
        group_by(.country)
        | map({country: .[0].country, sessions: (map(.sessions)|add)})
        | sort_by(-.sessions) | .[0:5]')
      TOP_LANGUAGES=$(printf '%s' "$ROWS" | jq -c '
        group_by(.language)
        | map({language: .[0].language, sessions: (map(.sessions)|add)})
        | sort_by(-.sessions) | .[0:5]')
      # Heuristic only, not a confirmed bot/human split (GA4 already
      # silently excludes its own "known spiders & bots" list before any
      # of this data ever reaches us, and most real crawlers never
      # execute the JS tag at all — so this can only ever flag what GA4
      # itself still recorded). Flags a browser string that names itself
      # a bot/crawler/headless client, OR a row with near-zero engagement,
      # near-zero session duration, and one page view per session — the
      # shape of a script hitting a URL and leaving, not a person reading.
      LIKELY_AUTOMATED=$(printf '%s' "$ROWS" | jq -c '
        [.[] | select(
          (.browser | test("bot|spider|crawl|headless|compatible agent"; "i"))
          or ((.engagementRate < 0.01) and (.avgSessionDuration < 1) and ((.pageViews / (if .sessions > 0 then .sessions else 1 end)) <= 1))
        )] | sort_by(-.sessions) | .[0:20]')
    fi
  fi

  ENTRY=$(jq -c -n --arg l "$LABEL" --arg id "$PROPERTY_ID" --argjson week "$WEEK" \
    --argjson prevweek "$PREV_WEEK" --argjson prevmonth "$PREV_MONTH" --argjson prevyear "$PREV_YEAR" \
    --argjson ai "$AI_TRAFFIC" --argjson social "$SOCIAL_TRAFFIC" --argjson pages "$TOP_PAGES" \
    --argjson countries "$TOP_COUNTRIES" --argjson languages "$TOP_LANGUAGES" --argjson automated "$LIKELY_AUTOMATED" \
    --arg dimstatus "$DIM_STATUS" \
    '{label:$l, property_id:$id, status:"ok", week:$week,
      previous_week:$prevweek, previous_month:$prevmonth, previous_year:$prevyear,
      ai_traffic:$ai, social_traffic:$social,
      top_landing_pages:$pages, top_countries:$countries, top_languages:$languages,
      likely_automated:$automated, dimensional_status:$dimstatus}')
  RESULTS=$(jq -c --argjson e "$ENTRY" '. + [$e]' <<< "$RESULTS")
done

printf '{"wakeAgent": true, "data": {"properties": %s}}\n' "$RESULTS"
