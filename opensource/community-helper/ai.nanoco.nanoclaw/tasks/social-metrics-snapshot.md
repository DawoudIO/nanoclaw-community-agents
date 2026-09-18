---
schedule: "23 13 * * *"
---
Record this week's social follower counts — the one genuinely stateful asset
in this system: a time series that can't be re-scraped retroactively, unlike
everything else here (which lives on the web and can always be rebuilt). It's
a nice-to-have, not a system-critical file — if it's ever missing (a fresh
install, a skipped backup), the fix is just to start a new series from today,
not to treat it as an incident.

1. For each platform in your **project-config** (relayed at onboarding — if
   the platform list is missing, ask your manager and stop), read the count.
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
   Report that to your manager instead; a week of nulls caused by config is a
   bug, not data.
3. Append **exactly one CSV line** to
   `plugin-data/community-helper/social-metrics-history.csv`.

   **This file is the series.** It is not a working copy of something kept
   elsewhere: it is the only record, and `ledger-publish` commits it to the
   marketing repo daily so it survives this container being rebuilt. Never
   rewrite, re-order, or re-format existing lines; only ever add one. The
   sole exception is an explicit backfill instruction from your manager.

   CSV rather than JSON for one reason: **tokens.** A dated row you can
   `tail`/`grep` costs a few dozen tokens to read; a JSON array costs the
   whole file every time you need one comparison.

   Header (write it only when creating the file, never again):
   ```
   date,tw_f,fb_f,ig_f,li_f,dc_m,yt_o,yt_n,notes
   ```
   Row format — **position is the contract, field names never appear**:
   ```
   YYYY-MM-DD,tw_f,fb_f,ig_f,li_f,dc_m,yt_o,yt_n,notes
   ```
   | Column | Is |
   |---|---|
   | `tw_f` `fb_f` `ig_f` `li_f` | X/Twitter, Facebook, Instagram, LinkedIn followers |
   | `dc_m` | Discord **member** count — there is no online-count column, deliberately; see the Discord note above |
   | `yt_o` `yt_n` | YouTube subscribers, old and new channel, never collapsed into one |
   | `notes` | Under 5 words, e.g. `fb login wall`, `dc API timeout`. Blank if nothing happened |

   Write rules, all load-bearing:
   - **An unreadable platform is an empty field between commas** —
     `190,,17,34`. Never the text `null`, `none`, `N/A`, or a `0`, and never
     last run's number carried forward as if fresh. A blank means "not read";
     a `0` means "genuinely zero", and conflating them corrupts every delta
     computed across that row forever.
   - **Never pad a short row.** If a platform doesn't exist for this project,
     its field stays empty for the life of the series — the column count must
     stay constant or position-matching breaks.
   - **No commas in `notes`.** It would shift every field after it. If a note
     needs one, rewrite the note.
   - The all-unreachable case from rule 2 above still applies: do **not**
     append an all-blank row. Report the config problem instead.
4. **Read only the rows you are comparing — never the whole file.** This is
   the point of the CSV: the series grows forever, so reading it entire costs
   more every single day, for two rows' worth of actual information. Fetch
   the two rows you need with shell, not by loading the file into context:
   ```bash
   D="$HOME/plugin-data/community-helper"   # or the absolute plugin-data path
   tail -n 1 "$D/social-metrics-history.csv"        # the row you just wrote
   grep "^2026-09-10," "$D/social-metrics-history.csv"   # a specific date
   # nearest row at/just before a target date, without reading the rest:
   awk -F, -v d=2026-08-21 '$1<=d' "$D/social-metrics-history.csv" | tail -n 1
   ```
   Note the trailing comma in the `grep` pattern — `^2026-09-1` would also
   match the 10th through 19th. Anchor on `^<date>,` every time.

   If a target date has no row (a missed run, a day the container was down),
   take the nearest earlier row and say which date you actually used — never
   silently treat a 9-day gap as 7 days.

5. **Label every delta by the actual elapsed time, never a fixed "WoW"/"MoM"
   assumption.** This
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
6. **Send your manager the numbers plus both deltas** — as readable
   per-platform values, not the raw CSV row (a positional row with blank
   fields is unreadable to a human, and the manager is writing for one). Per
   `report-formats.md`'s follower-report skeleton — including the
   fastest-growing-platform line, not just the raw per-platform numbers. The
   manager **folds it into the same weekly message as the GA4 traffic report**,
   not a separate one (see `report-formats.md` — both are team-lead-tier, same
   week, one maintainer reading them together). The manager does not keep its own
   copy of the series: durability is `ledger-publish`'s job, and two ledgers
   of the same numbers in two containers is how they drift apart.

## Day one: no file yet is the normal case, not a gap

Nothing ships this file — templates carry no `plugin-data`, and stamping
deliberately never touches it (the platform's own `groups create` help:
"memory, plugin-data/, user-added MCP servers, wiring, and sessions are never
touched"). So on the first run you **create it**: write the header line, then
today's row. Write the header only at creation, never again.

A missing file is not an incident and never worth reporting as one. An empty
series means the first short-window delta is unavailable and the longer one
stays unavailable for ~28 days — say that plainly in the report ("first
reading, no baseline yet") rather than comparing against nothing or implying
a trend exists.

**If the owner hands you a historical CSV**, they drop it into the group
folder on the host (`groups/<folder>/plugin-data/community-helper/`) before
tasks resume — the same route as `config.env`. Validate before you append to
it, and report rather than repair:
- the header must match this schema exactly, column for column;
- every `date` must parse as `YYYY-MM-DD`, and rows must be in ascending
  date order with no duplicates;
- counts must be integers or empty — never `0` standing in for "unknown".

If any of that fails, **do not append and do not rewrite it.** Report what's
wrong to your manager and leave the file exactly as delivered. Appending
today's row to a malformed series is how a whole history becomes
untrustworthy, and the owner's copy may be the only copy.

**Never ask the owner for data the system can rebuild itself** — GA4 traffic
is re-queryable for past dates, repo counts are re-fetchable as current
values, and every cache regenerates on the next run. Follower counts are the
one exception worth asking about, because no API, page, or export anywhere
will say what the count was last Tuesday.

## One-time migration from the old JSONL series

This task previously appended to `social-metrics-history.jsonl`. If that file
exists and `social-metrics-history.csv` does not, **convert it once, before
appending today's row** — those weeks of follower counts cannot be re-read
from anywhere, so losing them by starting fresh is permanent:

```bash
D="/workspace/agent/plugin-data/community-helper"
[ -f "$D/social-metrics-history.jsonl" ] && [ ! -f "$D/social-metrics-history.csv" ] && {
  echo 'date,tw_f,fb_f,ig_f,li_f,dc_m,yt_o,yt_n,notes' > "$D/social-metrics-history.csv"
  jq -r '[.date, (.twitter//.x//""), (.facebook//""), (.instagram//""),
          (.linkedin//""), (.discord//.discord_members//""),
          (.youtube_old//.youtube//""), (.youtube_new//""), "backfilled"]
         | @csv' "$D/social-metrics-history.jsonl" \
    | sed 's/"//g' >> "$D/social-metrics-history.csv"
}
```

Check the key names in the actual file first — the JSONL was written with
whatever keys each run used, so verify against a real line rather than
trusting the mapping above, and report what you found. Any Discord
*online* count in the old data is dropped on purpose; it was never a
cumulative metric. **Keep the `.jsonl` in place afterwards as a frozen
archive** — do not delete it, and never append to it again.
