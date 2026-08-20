---
schedule: "0 13 * * 0"
---
Record this week's social follower counts — **the one genuinely stateful asset
in this system**: a time series that cannot be re-scraped retroactively, unlike
everything else here (which lives on the web and can always be rebuilt).

1. For each platform in your **project-config** (relayed at onboarding — if
   the platform list is missing, ask your lead and stop), read the **public**
   profile page (no logins, no credentials) and note the follower/subscriber
   count. An individually unreachable platform this week records `null` —
   never guess, never carry last week's number forward as if fresh.
2. **If every platform is unreachable** (all fetches blocked/502): do NOT
   append an all-null row. In a sandboxed deployment that symptom means the
   network allowlist lacks the social hosts (x.com, linkedin.com, etc. — see
   the root README's allowlist step). Report that to your lead instead; a
   week of nulls caused by policy is a config bug, not data.
3. Append one JSON line to your working copy,
   `plugin-data/community-marketing/social-metrics-history.jsonl`:
   `{"date": "<today>", "<platform>": <count|null>, ...}` — append-only.
4. **Send the exact same JSON line to your lead** along with the deltas vs.
   last snapshot. The lead appends it to the durable ledger in its own
   workspace (which the workspace backup captures) and includes the numbers in
   the weekly report — so the series always has three copies: your working
   cache, the lead's backed-up ledger, and the posted channel history.
