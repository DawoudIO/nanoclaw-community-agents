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
     already in the server) — not a public invite-page scrape. **Track
     member count only, never "currently online" count.** Online headcount
     is a point-in-time snapshot that swings with who happens to be active
     right now — it's noise, not a growth signal, and doesn't belong next
     to real cumulative counts like followers/members/subscribers. A real
     install tracked it, reported a "WoW +2" on it, and the owner correctly
     called it worthless — it was dropped from the report afterward. Don't
     re-add it.
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
3. Append one JSON line to
   `plugin-data/community-marketing/social-metrics-history.jsonl`:
   `{"date": "<today>", "<platform>": <count|null>, ...}` — append-only.
   **This file is the series.** It is not a working copy of something kept
   elsewhere: it is the only record, and `ledger-publish` commits it to the
   marketing repo daily so it survives this container being rebuilt. Never
   rewrite or reorder existing lines; only ever add one.
4. **Compute deltas from the file you just appended to, and label them by
   the actual elapsed time, never a fixed "WoW"/"MoM" assumption.** This
   task's schedule isn't necessarily weekly — the owner may have it running
   daily, and "WoW" printed on a 1-day delta is a real, observed mislabeling
   bug (the numbers were fine, the label was a lie about the window). Look
   at the actual date on the comparison line you pick and say what it
   really is:
   - **Short-window delta**: vs. the previous line, whatever that gap
     actually is — report it as "vs N days ago", not "WoW", unless the gap
     genuinely is ~7 days.
   - **Longer-window delta**: vs. the line closest to 28 days earlier,
     reported as "vs ~N days ago" (or "MoM" only when that line is genuinely
     ~28-30 days back). Needs enough history to mean anything — with too few
     lines, say plainly there's not enough history yet rather than comparing
     against a too-short baseline.
   The rule is the same one the weekly-analytics-report uses: state the
   real window, never a label that assumes a cadence this task might not
   actually be running on.
5. **Send the exact same JSON line to your lead, plus both deltas**, per
   `report-formats.md`'s follower-report skeleton — including the
   fastest-growing-platform line, not just the raw per-platform numbers. The
   lead **folds it into the same weekly message as the GA4 traffic report**,
   not a separate one (see `report-formats.md` — both are team-lead-tier, same
   week, one maintainer reading them together). The lead does not keep its own
   copy of the series: durability is `ledger-publish`'s job, and two ledgers
   of the same numbers in two containers is how they drift apart.
