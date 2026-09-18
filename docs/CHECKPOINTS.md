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

Work through these in order after INSTALL.md §4's resume sequence. Each has
an expected result; a miss means stop and fix, not proceed.

Items 13–15 exist because an install could once pass every earlier check
while the agent that owns most of the tasks (run
`bash scripts/gen-task-table.sh --counts` for the current split) was absent,
misconfigured, or silently billing to the shared window without anyone
noticing.

| # | Test | How | Pass looks like |
|---|---|---|---|
| 1 | Owner DM round trip | DM the manager; ask it to proactively DM you back | Both directions arrive; replies come from the bot identity |
| 2 | Bot identity on GitHub | Ask the manager "what's not set up?" — it runs its own `setup-check.sh` and has the Helper relay its own | **Both tokens** — one per agent — report `GET /user` login == the dedicated bot username, never yours. Two reports, not one: a missing one means the sub-agent didn't answer, which is itself the finding |
| 3 | Support-tier auto-reply | Post a question in a support channel from a **non-owner** account, no @mention | Unprompted reply within a couple of minutes. Silence here = the Message Content intent is off in the Discord dev portal |
| 4 | Mention-only discipline | Post in a dev-tier channel *without* tagging the bot, then again *with* a tag | No reply to the first, a reply to the second |
| 5 | Non-owner DM redirect | DM the bot from a second account | Warm redirect to the public channels; no support answer, no instructions accepted |
| 6 | No per-sender prompts | Have that second account post in a public channel | You do **not** get a "new sender — allow?" approval ask (if you do, the wiring is missing `--sender-scope all`) |
| 7 | Sub-agent relay | DM the manager: "ping the Helper and relay its answer" | It answers **through the manager** — that's its only outbound path for anything substantive. Its one channel wiring exists solely for the template-only holding acknowledgment it is forbidden to compose freely; nothing else it produces should ever appear in public |
| 8 | Every gate emits clean JSON | `./bin/ncl tasks run <id>` + `tasks get <id>` for each configured task | Single-line JSON, `not-configured` for things you skipped, real data for things you set up |
| 9 | History publish actually pushed | Check the marketing repo's `agent-metrics` branch after the first `ledger-publish` run on **each** sub-agent | A commit from the bot exists under both `agent-metrics/helper/` and `agent-metrics/marketing/` (whichever agents you stamped); `tasks get` shows `published`. This is the only durable state in the system — a silent failure here is the one that costs data rather than a report |
| 10 | Credential approval flow | Trigger one action that hits an OneCLI request-hold (if configured) | The approve/deny button appears and works — you've seen the flow once before it matters |
| 11 | Vault audit clean | `onecli apps connections agent-access` per provider (PREREQS.md §3) | Every grant matches a row in INSTALL.md §2's per-agent footprint table; nothing extra |
| 12 | Human backstop recorded | Ask the manager who the escalation backstop is | It names the person from the welcome interview — or plainly states the recorded open risk |
| 13 | **Which meter the agents bill to, and at which tier** | Confirm what the first-boot wizard configured (subscription, OAuth token, or API key), then confirm which agents draw on it. Then run `ncl groups config get --id <manager-id>` and confirm `model` reads **sonnet** — not the haiku it was pinned to for setup | You can state which meter — **and that both agents bill to it** (a local-model provider is possible but not adopted; see SKILLS-ADOPTION.md). If subscription: you know the agents share one window with your own Claude Code, including the break-glass recovery session — see OPERATIONS.md → Model budget for the four defenses. The manager promotes itself at the end of onboarding, but a tier change only applies after a restart — so a config updated and never restarted reads Sonnet while every wake still bills Haiku |
| 14 | **`unanswered-watch` proven end to end** | Let one test message from a non-owner account sit in a support channel past `ACK_GRACE_MINUTES` (default 20) without the manager answering it | The holding acknowledgment appears in the channel. Do not accept "the gate returns clean JSON" as a substitute — this is the north star's safety net, and its two riskiest dependencies (channel wiring, message-list shape) only fail at the point where it has to actually post |
| 15 | You can check liveness on demand | DM the manager exactly `ping` | You get `pong #<last-ledger-id> <UTC time>` back in seconds, and nothing else. **This replaced a weekly heartbeat task** whose absence was supposed to be the outage alarm — an alarm that fires by not arriving is one nobody reliably notices. Know that this proves only the *manager* is alive; a stopped sub-agent shows up as its reports going quiet instead |

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
  is the cheapest moment to correct tone — one DM to the manager.
- **No surprise wakes**: gated tasks that had nothing to say stayed silent.
  A gate waking on nothing is a bug worth reporting while it's fresh.
- **Close out the unverified holding-ack risk.** It was flagged as needing a
  real install before anyone could assert it, and it fails *quietly*, which is
  why it belongs on a checklist rather than in a bug report you'd notice on
  your own:
  - **Can the manager and the Helper both wire to the same Discord
    channel?** Still unverified. If the platform refuses the second wiring, or
    the Helper's channel destination silently resolves to nothing,
    `unanswered-watch` will do all its work and then have nowhere to put the
    acknowledgment. Ready gate item 14 is the test; if you skipped it, do it
    now.
  - **Are `ncl sessions list` / `ncl sessions history --json` the shapes the
    gate expects?** Also unverified — the output shape varies by NanoClaw
    version. The gate is written to fail safe rather than fail quiet: an unrecognized shape makes it report `cannot-read-sessions`,
    and no channel-backed session at all makes it report
    `no-channel-sessions`, instead of concluding "nothing to do."
    **So check for both statuses explicitly** (`./bin/ncl tasks get` on an
    `unanswered-watch` run). Either one looks almost exactly like a healthy
    quiet night, and means the safety net has been off the whole time —
    `no-channel-sessions` specifically means the silent support-channel
    wiring (§5c) never happened.

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
- **The follower snapshot landed, and then got published.** This one is worth
  checking on both ends, because it's the only genuinely un-re-scrapable
  series in the system. `social-metrics-snapshot` appends its line
  to `plugin-data/community-helper/social-metrics-history.jsonl`, and
  `ledger-publish` commits that file to the marketing repo's `agent-metrics`
  branch. Confirm the line exists in the container's file *and* that the
  branch has it. **A publish that silently stops leaves the local file still
  growing, so the container's copy looking healthy proves nothing about
  durability** — check both, or you haven't checked the thing that matters.
- **Integrity check is quiet**: `weekly-identity-integrity-check` baseline
  initialized on its first run and no drift alarm since — unless you edited
  a task, in which case you got asked about exactly that edit (good).
- **Publish cadence**: the `agent-metrics` branch shows a commit per day on
  the days the numbers actually changed (`ledger-publish` stays silent when
  nothing moved, so an unchanged day with no commit is correct, not a miss).
- **Test the correction loop once, deliberately**: tell the manager to change
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
- **Question ledger is accumulating**: `plugin-data/community-manager/question-ledger.csv`
  has one line per resolved support conversation. If it's empty after a
  month of real support traffic, the manager isn't logging — correct it. If
  `docs-gap-review` fired, its first docs proposal is the system's
  load-reduction loop working; review it seriously. **The manager owns both
  halves of this loop** — it writes the ledger and it runs `docs-gap-review`
  against its own copy, so that path is a within-agent read. It hasn't always
  been: the task previously lived with the Helper, where it read a file only
  the manager writes, and since one agent cannot read another's `plugin-data` it
  was permanently dead code that looked configured. Moving it to the manager is
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
- **Platform currency**: check
  [`nanocoai/nanoclaw`'s releases](https://github.com/nanocoai/nanoclaw/releases)
  and `versions.json`'s `agent-image` digest by hand — there's no automated
  watcher for this. If either has moved, schedule the digest-pinned refresh
  per [OPERATIONS.md](OPERATIONS.md) rather than letting it age.
- **Disk check**: `docker system df` for image/volume footprint.

## After month 1

Steady state is: heartbeat weekly, reports on their cadence, the quarterly
`repo-hygiene-audit`, and a vault re-audit whenever a credential changes.
The recurring human jobs that never go away: approving drafts, sending the
personal outreach the nudges suggest, and making the delegation decisions
the concentration numbers surface — those are maintainer work, and the whole
point of the system is to leave you time for exactly them.
