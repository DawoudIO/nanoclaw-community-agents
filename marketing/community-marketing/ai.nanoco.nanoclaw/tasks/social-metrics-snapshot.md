---
schedule: "0 13 * * 0"
---
Record this week's social follower counts — **the one genuinely stateful asset
in this system**: a time series that cannot be re-scraped retroactively, unlike
everything else here (which lives on the web and can always be rebuilt).

1. For each platform listed in your standing brief's "Your project" block,
   read the **public** profile page (no logins, no credentials) and note the
   follower/subscriber count. If a platform can't be read this week, record
   `null` for it — never guess or carry forward last week's number as if fresh.
2. Append one JSON line to
   `plugin-data/community-marketing/social-metrics-history.jsonl`:
   `{"date": "<today>", "<platform>": <count|null>, ...}` — append-only, never
   rewrite or "clean up" earlier lines.
3. Hand your lead a one-liner with the counts and their deltas vs. the last
   snapshot, for inclusion in the weekly report — the posted report doubles as
   the durable off-box copy of the series, so always include the raw numbers.
