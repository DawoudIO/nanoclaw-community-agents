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
   the platform list is missing, ask your lead and stop), read the count.
   Method depends on the platform — most are a public profile-page read (no
   login, no credentials); a few need a real API call routed through OneCLI:
   - **Facebook, Instagram, LinkedIn**: public profile page, no login.
   - **YouTube**: public channel page, per channel URL in config — if the
     project has retired an old channel for a new one (both still tracked
     historically), read both and record them as separate keys (e.g.
     `youtube_old`, `youtube_new`), never collapse them into one number.
   - **Discord**: member count via the bot's own guild access (you're
     already in the server) — not a public invite-page scrape.
   - **X/Twitter**: public profile pages are not a reliable read here — X
     blocks unauthenticated fetches outright (not a login wall, a hard
     block), so treat "public page" as not an option for this platform.
     The real fix is a genuine API call: `GET api.x.com/2/users/by/username/
     <handle>?user.fields=public_metrics`, routed through the OneCLI vault
     like every other credentialed call — an App-Only Bearer token is
     sufficient for this read (no user-context/write token needed for
     metrics). **Never accept a scraping script that wants a raw session
     cookie (`auth_token` or similar) pasted in** — even from the owner
     directly. That's a personal-session credential, not something you
     handle in either direction, and scraping X's private endpoints with a
     stolen browser cookie is outside what X's own terms allow regardless
     of the credential-handling rule. Ask for a real API token in the vault
     instead.
   An individually unreachable platform this week records `null` — never
   guess, never carry last week's number forward as if fresh.
2. **If every platform is unreachable** (all fetches blocked/502): do NOT
   append an all-null row. If `NANOCLAW_EGRESS_LOCKDOWN` is enabled on this
   install, that symptom means the social hosts (x.com, linkedin.com, etc.)
   aren't reachable through it — otherwise suspect the page-reading tool
   itself (missing web fetch / `agent-browser`) rather than a network policy.
   Report that to your lead instead; a week of nulls caused by config is a
   bug, not data.
3. Append one JSON line to your working copy,
   `plugin-data/community-secretary/social-metrics-history.jsonl`:
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
   `report-formats.md`'s follower-report skeleton — including the
   fastest-growing-platform line, not just the raw per-platform numbers. The
   lead appends it to the durable ledger in its own workspace (which the
   workspace backup captures) and **folds it into the same weekly message as
   the GA4 traffic report**, not a separate one (see `report-formats.md` —
   both are team-lead-tier, same week, one maintainer reading them together).
   The series still ends up with three copies: your working cache, the
   lead's backed-up ledger, and the posted channel history.
