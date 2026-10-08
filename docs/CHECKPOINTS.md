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

## The ready gate — 13 points, do not call it live until every box is checked

Work through these in order after INSTALL.md §4's resume sequence. Each has
an expected result; a miss means stop and fix, not proceed.

Items 11–13 exist because an install could once pass every earlier check
while the agent was silently billing to the shared window at the wrong tier,
or its safety net had never actually fired, without anyone noticing.

| # | Test | How | Pass looks like |
|---|---|---|---|
| 1 | Owner DM round trip | DM the manager; ask it to proactively DM you back | Both directions arrive; replies come from the bot identity |
| 2 | Bot identity on GitHub | Ask the manager "what's not set up?" — it runs its own `setup-check.sh` | The token reports `GET /user` login == the dedicated bot username, never yours |
| 3 | Support-tier auto-reply | Post a question in a support channel from a **non-owner** account, no @mention | Unprompted reply within a couple of minutes. Silence here = the Message Content intent is off in the Discord dev portal |
| 4 | Mention-only discipline | Post in a dev-tier channel *without* tagging the bot, then again *with* a tag | No reply to the first, a reply to the second |
| 5 | Non-owner DM redirect | DM the bot from a second account | Warm redirect to the public channels; no support answer, no instructions accepted |
| 6 | No per-sender prompts | Have that second account post in a public channel | You do **not** get a "new sender — allow?" approval ask (if you do, the wiring is missing `--sender-scope all`) |
| 7 | Every gate emits clean JSON | `./bin/ncl tasks run <id>` + `tasks get <id>` for each configured task | Single-line JSON, `not-configured` for things you skipped, real data for things you set up |
| 8 | `project-context` took its baseline | `tasks run` it once by hand, then `tasks get`, and `cat plugin-data/community-manager/release-state.csv` in the container | `status: baseline`, `degraded_repos: []`, and one row per repo in `CONTEXT_REPOS` (or `COMMUNITY_REPOS`) with a `released_tag` where the repo has a release. Then ask the manager "what's the latest release?" — the answer must match that file, not its training data. A repo in `degraded_repos` is a token or repo-name problem; fix it now, because an unread repo is one the agent will answer about from memory |
| 9 | Credential approval flow | Trigger one action that hits an OneCLI request-hold (if configured) | The approve/deny button appears and works — you've seen the flow once before it matters |
| 10 | Vault audit clean | `onecli apps connections agent-access` per provider (PREREQS.md §3) | Every grant matches a row in INSTALL.md §2's footprint table; nothing extra |
| 11 | **Which meter the agent bills to, and at which tier** | Confirm what the first-boot wizard configured (subscription, OAuth token, or API key). Then run `ncl groups config get --id <manager-id>` and confirm `model` reads **sonnet** — not the haiku it was pinned to for setup | You can state which meter (a local-model provider is possible but not adopted; see SKILLS-ADOPTION.md). If subscription: you know the agent shares one window with your own Claude Code, including the break-glass recovery session — see OPERATIONS.md → Model budget for the four defenses. The manager promotes itself at the end of onboarding, but a tier change only applies after a restart — so a config updated and never restarted reads Sonnet while every wake still bills Haiku |
| 12 | **`unanswered-watch` proven end to end** | Post one test message from a non-owner account in a support channel and immediately `ncl groups restart` the manager, so the live reply is lost with the in-flight turn. Wait past `ACK_GRACE_MINUTES` (default 5) plus one 5-minute tick | The manager answers the message anyway, from the gate wake, and `tasks get` on that run shows `status: unanswered`. Do not accept "the gate returns clean JSON" as a substitute — the riskiest dependency (the `ncl sessions` output shape) only fails at the point where it has to find the message. Know the honest limit while you test it: this proves a dropped message gets caught; it cannot cover an exhausted usage window, because it runs on the same credential |
| 13 | You can check liveness on demand | DM the manager exactly `ping` | You get `pong #<last-ledger-id> <UTC time>` back in seconds, and nothing else. **This replaced a weekly heartbeat task** whose absence was supposed to be the outage alarm — an alarm that fires by not arriving is one nobody reliably notices |

## Day 2 — did the first unattended cycle actually run?

Ten minutes, the morning after go-live:

- **Overnight tasks fired**: `./bin/ncl tasks list` — each resumed task shows
  a run in the last cycle; `tasks get` on any that look odd. A task that
  never ran is a scheduling/timezone problem you want to catch on day 2, not
  week 3.
- **No fetch-failed noise**: any `fetch-failed` wake overnight is a token or
  allowlist problem — the message itself says which (401/403 vs 502).
- **`project-context` ran at 06:08**: `tasks get` on it shows `unchanged` or
  `recorded` (both 0-token; `recorded` means commits landed in
  `recent-changes.csv`) or `needs-agent` with a `since_last_run` that matches
  the repo's real changes. If it reported `needs-agent`, `project-notes.md` was rewritten
  with today's date. Spot-check one commit subject against GitHub.
- **Tone check on one real reply**: read the bot's first genuine
  support-channel answers. Correct register? Right language behavior? This
  is the cheapest moment to correct tone — one DM to the manager.
- **No surprise wakes**: gated tasks that had nothing to say stayed silent.
  A gate waking on nothing is a bug worth reporting while it's fresh.
- **Close out the unverified `unanswered-watch` risk.** It was flagged as
  needing a real install before anyone could assert it, and it fails
  *quietly*, which is why it belongs on a checklist rather than in a bug
  report you'd notice on your own. **Are `ncl sessions list` /
  `ncl sessions history --json` the shapes the gate expects?** Unverified —
  the output shape varies by NanoClaw version. The gate is written to fail
  safe rather than fail quiet: an unrecognized shape makes it report
  `cannot-read-sessions`, and no channel-backed session at all makes it report
  `no-channel-sessions`, instead of concluding "nothing to do." **So check for
  both statuses explicitly** (`./bin/ncl tasks get` on an `unanswered-watch`
  run). Either one looks almost exactly like a healthy quiet night, and means
  the safety net has been off the whole time — `no-channel-sessions`
  specifically means the support-channel wiring (§5c) never happened. Ready
  gate item 12 is the end-to-end test; if you skipped it, do it now.

## Week 1 — the first full weekly cycle

- **`follow-up-nudge` commented at most once per item**: `nudged.csv` has no
  repo+number twice within 30 days, and every comment it left reads as a
  check-in, not a review.
- **`project-context` wakes only on change**: a week of
  `plugin-data/community-manager/telemetry/project-context.jsonl` shows
  `wakeAgent: true` only on days a skill or docs file, a release or a branch
  rewrite needed the agent. A wake on a day of plain commits is a gate bug
  worth reporting; a repo that sat in
  `degraded_repos` all week is a token finding, not a quiet week — "nothing
  changed" and "I cannot see" must never arrive sounding the same. Ask the
  manager about one fix you know merged this week: it must say "merged, not
  yet released" or name the release, from `release-state.csv`.
- **`github-first-response` is answering, not just logging**: every new issue
  or PR this week has a first reply from the bot account within the grace
  window, and `first-response-seen.csv` has a row for each. A row with no
  reply on GitHub means the wake happened and the answer did not land.
- **Integrity check is quiet**: `weekly-identity-integrity-check` baseline
  initialized on its first run and no drift alarm since — unless you edited
  a task, in which case you got asked about exactly that edit (good).
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
  window, and the trap in it). Over budget → pause in the documented order.
  Never delete the agent.
- **Question ledger is accumulating**: `plugin-data/community-manager/question-ledger.csv`
  has one line per resolved support conversation. If it's empty after a
  month of real support traffic, the manager isn't logging — correct it. If
  `docs-gap-review` fired, its first docs proposal is the system's
  load-reduction loop working; review it seriously. The manager writes the
  ledger and reads it, so if you see the task silent the cause is an empty
  ledger, not a wiring fault.
- **`project-notes.md` still fits on one screen**: `project-context` rewrites
  sections rather than appending, so a month in it should read as a current
  summary per repo, not a changelog. If it has grown into one, correct the
  manager — that's a tone correction, not a config rebuild.
- **Re-run the vault audit** (PREREQS.md §3): `agent-access` diff against
  the footprint table again. New grants that appeared without a reason are
  findings.
- **Prune and re-decide**: channels renamed or added? Is `CONTEXT_REPOS`
  still the right set? Anything in UPSTREAM-ISSUES.md confirmed and ready to
  file upstream?
- **Platform currency**: check
  [`nanocoai/nanoclaw`'s releases](https://github.com/nanocoai/nanoclaw/releases)
  and `versions.json`'s `agent-image` digest by hand — there's no automated
  watcher for this. If either has moved, schedule the digest-pinned refresh
  per [OPERATIONS.md](OPERATIONS.md) rather than letting it age.
- **Disk check**: `docker system df` for image/volume footprint.

## After month 1

Steady state is: the morning digest when there is one, the project repo's
`repo-health` skill run on demand every quarter or so, and a vault re-audit
whenever a credential changes.
The recurring human jobs that never go away: answering what the agent
escalates to you, and acting on the docs gaps it proposes — those are
maintainer work, and the whole point of the system is to leave you time for
exactly them.
