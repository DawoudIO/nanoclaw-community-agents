# Checkpoints: when is it ready, and what to verify after

Install steps are in [INSTALL.md](INSTALL.md); this is the **acceptance
side** — what a human tests before calling the system live, and what to
check at day 2, week 1, and month 1. Every item here is verifiable by
looking at something specific; none is "seems fine."

**Before you start the clock:** finish PREREQS (every token created, vault
loaded, identity verified) and decide whether you're filling in
`onboarding-answers.json` — that collapses the interview from 8–15 turns to
about 2. See [OPERATIONS.md → Model budget — one shared window, and the trap in
it](OPERATIONS.md) for what the install actually costs and which meter pays for
it; the short version is that volume won't threaten a 5-hour window but a
credential debugging loop will.

## The ready gate — 15 points, do not call it live until every box is checked

Work through these in order after INSTALL.md §7's resume sequence. Each has
an expected result; a miss means stop and fix, not proceed.

It grew when the local agent joined: nothing in the original gate touched it,
which meant an install could pass every check while the tier that owns the
largest single share of tasks (run `bash scripts/gen-task-table.sh --counts`
for the current split) was absent, misconfigured, or silently billing to the
shared window without anyone noticing. Items 13–15 close that.

| # | Test | How | Pass looks like |
|---|---|---|---|
| 1 | Owner DM round trip | DM the lead; ask it to proactively DM you back | Both directions arrive; replies come from the bot identity |
| 2 | Bot identity on GitHub | Ask the lead "what's not set up?" — it runs its own `setup-check.sh` and has each of the **three** sub-agents relay theirs (each group ships its own) | **All four tokens** — one per agent — report `GET /user` login == the dedicated bot username, never yours. Four reports, not three: a missing one means a sub-agent didn't answer, which is itself the finding |
| 3 | Support-tier auto-reply | Post a question in a support channel from a **non-owner** account, no @mention | Unprompted reply within a couple of minutes. Silence here = the Message Content intent is off in the Discord dev portal |
| 4 | Mention-only discipline | Post in a dev-tier channel *without* tagging the bot, then again *with* a tag | No reply to the first, a reply to the second |
| 5 | Non-owner DM redirect | DM the bot from a second account | Warm redirect to the public channels; no support answer, no instructions accepted |
| 6 | No per-sender prompts | Have that second account post in a public channel | You do **not** get a "new sender — allow?" approval ask (if you do, the wiring is missing `--sender-scope all`) |
| 7 | Sub-agent relay | DM the lead: "ping all three sub-agents and relay their answers" | All three answer **through the lead** — that's their only outbound path. The Reviewer and Marketing have no channel wiring at all and cannot post publicly even if instructed to. The **local agent is the one deliberate exception**: it holds a single channel, and the only thing it may ever put there is a template-only holding acknowledgment it is forbidden to compose freely. Nothing else it produces should ever appear in public |
| 8 | Every gate emits clean JSON | `./bin/ncl tasks run <id>` + `tasks get <id>` for each configured task | Single-line JSON, `not-configured` for things you skipped, real data for things you set up |
| 9 | Backup actually pushed | Check the backup repo on GitHub after the first `workspace-backup` run | A commit from the bot exists; `tasks get` shows `pushed` |
| 10 | Credential approval flow | Trigger one action that hits an OneCLI request-hold (if configured) | The approve/deny button appears and works — you've seen the flow once before it matters |
| 11 | Vault audit clean | `onecli apps connections agent-access` per provider (PREREQS.md §3) | Every grant matches a row in INSTALL.md §4's per-agent footprint table; nothing extra |
| 12 | Human backstop recorded | Ask the lead who the escalation backstop is | It names the person from the welcome interview — or plainly states the recorded open risk |
| 13 | **Which meter the agents bill to** | Confirm what the first-boot wizard configured (subscription, OAuth token, or API key), then confirm which agents draw on it | You can state which meter — **and that all four agents currently bill to it** (the local agent's Ollama provider was evaluated and set aside for this phase; see SKILLS-ADOPTION.md). If subscription: you know the agents share one window with your own Claude Code, including the break-glass recovery session — see OPERATIONS.md → Model budget for the four defenses |
| 14 | **`unanswered-watch` proven end to end** | Let one test message from a non-owner account sit in a support channel past `ACK_GRACE_MINUTES` (default 20) without the lead answering it | The holding acknowledgment appears in the channel. Do not accept "the gate returns clean JSON" as a substitute — this is the north star's safety net, and its two riskiest dependencies (channel wiring, message-list shape) only fail at the point where it has to actually post |
| 15 | You know the death signal | No action — confirm you understand it | A one-line heartbeat reaches you at least weekly — produced by the local agent's `health-check`, relayed by the lead. **More than ~8 days of silence means the sandbox died and needs a host-side restart.** Silence is the alarm |

## Day 2 — did the first unattended cycle actually run?

Ten minutes, the morning after go-live:

- **Overnight tasks fired**: `./bin/ncl tasks list` — each resumed task shows
  a run in the last cycle; `tasks get` on any that look odd. A task that
  never ran is a scheduling/timezone problem you want to catch on day 2, not
  week 3.
- **No fetch-failed noise**: any `fetch-failed` wake overnight is a token or
  allowlist problem — the message itself says which (401/403 vs 502).
- **Triage digest sanity**: the first digest arrived and describes issues
  that actually exist. Spot-check one item against GitHub.
- **Tone check on one real reply**: read the bot's first genuine
  support-channel answers. Correct register? Right language behavior? This
  is the cheapest moment to correct tone — one DM to the lead.
- **No surprise wakes**: gated tasks that had nothing to say stayed silent.
  A gate waking on nothing is a bug worth reporting while it's fresh.
- **Close out the two unverified local-agent risks.** Both were flagged as
  needing a real install before anyone could assert them, and both fail
  *quietly*, which is why they belong on a checklist rather than in a bug
  report you'd notice on your own:
  - **Can the lead and the local agent both wire to the same Discord
    channel?** Still unverified. If the platform refuses the second wiring, or
    the local agent's channel silently resolves to nothing, `unanswered-watch`
    will do all its work and then have nowhere to put the acknowledgment. Ready
    gate item 14 is the test; if you skipped it, do it now.
  - **Is `ncl messages list --json` the shape the gate expects?** Also
    unverified — the output shape varies by NanoClaw version. The gate is
    written to fail safe rather than fail quiet: an unrecognized shape makes it
    report `cannot-read-messages` instead of concluding "nothing to do."
    **So check for that status explicitly** (`./bin/ncl tasks get` on an
    `unanswered-watch` run). A run of `cannot-read-messages` looks almost
    exactly like a healthy quiet night, and it means the safety net has been
    off the whole time.

## Week 1 — the first full weekly cycle

- **Heartbeat received**: the proof-of-life line arrived. If it didn't,
  investigate now — this is your outage detector and it must be known-good.
- **Weekly reports landed and read sane**: dev report (now the narration half
  only — stars/forks, first-response backlog, new contributors, return nudges),
  GA4 if enabled. Numbers carry deltas and windows; `null`s are explained,
  never silently zero.
- **`ready-to-merge` is telling the truth, in both directions.** On its first
  runs it must either list approved-and-open PRs you can click through and
  verify on GitHub, or report that there are none — and you should confirm that
  "none" is actually true rather than accepting it. A `partial-fetch-failure`
  naming repos in `degraded_repos` is a token or allowlist finding, not a quiet
  week; "nothing is waiting" and "I cannot see" must never arrive sounding the
  same. Then check the following week's
  resurface: an unchanged set is re-mentioned once weekly with
  `resurfaced: true`, and it has to read as *"still waiting, no change since
  last week"*. If a re-mention reads as new activity, the task teaches the
  owner to skim it, which costs you the one thing it exists to catch.
- **The follower snapshot made it across the handoff.** This one is worth
  checking on both ends, because it's the only genuinely un-re-scrapable
  series in the system and it crosses an agent boundary to get durable.
  `social-metrics-snapshot` is the **local** agent's task: it appends its line
  to `plugin-data/community-secretary/social-metrics-history.jsonl` (its own
  working copy, and the one the backup captures) and relays the exact same
  JSON line plus both deltas to the lead, which appends it to the lead's
  durable ledger. Confirm the line exists on the local side *and* that the
  lead has it. **A relay that silently stops leaves the local copy still
  growing, so the local file looking healthy proves nothing about the
  handoff** — check both or you haven't checked.
- **Integrity check is quiet**: `weekly-identity-integrity-check` baseline
  initialized on its first run and no drift alarm since — unless you edited
  a task, in which case you got asked about exactly that edit (good).
- **Backup cadence**: the backup repo shows a commit per day with changes.
- **Test the correction loop once, deliberately**: tell the lead to change
  one small behavior (e.g. "stop including X in the digest"). Verify it
  acks with a ledger number, applies it, and the change survives to the
  next day's session. This is the loop you'll rely on for everything later —
  prove it works while the stakes are zero.
- **Owner DM load feels right**: you're getting one daily support digest and
  real escalations, not a stream. If it's noisy, say so — that's a
  correction, not a config rebuild.

## Month 1 — is it earning its keep?

- **Token/plan usage vs budget**: check your provider's usage page against
  expectations ([OPERATIONS.md](OPERATIONS.md) → Model budget — one shared
  window, and the trap in it). Over budget → pause in the documented order,
  which is cloud-tier only; pausing local tasks saves nothing on that meter.
  Never delete agents.
- **Question ledger is accumulating**: `plugin-data/community-manager/question-ledger.jsonl`
  has one line per resolved support conversation. If it's empty after a
  month of real support traffic, the lead isn't logging — correct it. If
  `docs-gap-review` fired, its first docs proposal is the system's
  load-reduction loop working; review it seriously. **The lead owns both
  halves of this loop** — it writes the ledger and it runs `docs-gap-review`
  against its own copy, so that path is a within-agent read. It hasn't always
  been: the task previously lived with the Reviewer, where it read a file only
  the lead writes, and since one agent cannot read another's `plugin-data` it
  was permanently dead code that looked configured. Moving it to the lead is
  the fix. If you see it silent, the cause is an empty ledger, not a wiring
  fault.
- **First return-nudges become possible**: the contributor ledger only
  tracks people whose first contribution came *after* install, so
  nudges start appearing from ~week 3 on. If one arrived, the follow-up it
  suggested is yours to send — the highest-leverage community act this
  system will ever hand you.
- **Contribution concentration**: read the owner-private numbers. If the
  top author share is where it was and candidates exist, month 1 is the
  right time to make the first delegation offer — that's the point of the
  metric.
- **Re-run the vault audit** (PREREQS.md §3): `agent-access` diff against
  the footprint table again. New grants that appeared without a reason are
  findings.
- **Prune and re-decide**: channels renamed or added? Paused optional tasks
  (GA4, inbox) worth enabling now? Anything in UPSTREAM-ISSUES.md confirmed
  and ready to file upstream?
- **Platform currency**: `platform-watch` ran weekly (check the Actions
  tab); if it opened an update issue, schedule the digest-pinned refresh
  per [OPERATIONS.md](OPERATIONS.md) rather than letting it age.
- **Disk check on the host**: `docker system df` for the outer VM footprint
  — the inner daemon's usage shows up inside the sandbox
  (`sbx exec nanoclaw docker system df`), not on the host.

## After month 1

Steady state is: heartbeat weekly, reports on their cadence, the quarterly
`repo-hygiene-audit`, and a vault re-audit whenever a credential changes.
The recurring human jobs that never go away: approving drafts, sending the
personal outreach the nudges suggest, and making the delegation decisions
the concentration numbers surface — those are maintainer work, and the whole
point of the system is to leave you time for exactly them.
