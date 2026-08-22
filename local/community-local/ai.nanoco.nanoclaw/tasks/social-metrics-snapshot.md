---
schedule: "23 13 * * 0"
---
Record this week's social follower counts — the one genuinely stateful asset
in this system: a time series that can't be re-scraped retroactively, unlike
everything else here (which lives on the web and can always be rebuilt). It's
a nice-to-have, not a system-critical file — if it's ever missing (a fresh
install, a skipped backup), the fix is just to start a new series from today,
not to treat it as an incident.

1. For each platform in your **project-config** (relayed at onboarding — if
   the platform list is missing, ask your lead and stop), read the **public**
   profile page (no logins, no credentials) and note the follower/subscriber
   count. An individually unreachable platform this week records `null` —
   never guess, never carry last week's number forward as if fresh.
2. **If every platform is unreachable** (all fetches blocked/502): do NOT
   append an all-null row. In a sandboxed deployment that symptom means the
   network allowlist lacks the social hosts (x.com, linkedin.com, etc. — see
   docs/INSTALL.md §5, the allowlist step). Report that to your lead instead; a
   week of nulls caused by policy is a config bug, not data.
3. Append one JSON line to your working copy,
   `plugin-data/community-local/social-metrics-history.jsonl`:
   `{"date": "<today>", "<platform>": <count|null>, ...}` — append-only.
4. **Compute deltas from the file you just appended to**, per platform:
   - **Week-over-week (WoW)**: vs. the previous line — if last week was
     `null`, skip back further to the last real reading instead of comparing
     against nothing.
   - **Month-over-month (MoM)**: vs. the line closest to 28 days earlier.
     Needs at least ~5 weeks of history to mean anything — with fewer lines
     than that, report WoW only and say plainly there's not enough history
     for MoM yet, rather than comparing against too-short a baseline.
5. **Send the exact same JSON line to your lead, plus both deltas**, per
   `report-formats.md`'s follower-report skeleton. The lead appends it to the
   durable ledger in its own workspace (which the workspace backup captures)
   and works the numbers into its next marketing update to the team-lead
   channel — so the series always has three copies: your working cache, the
   lead's backed-up ledger, and the posted channel history.
