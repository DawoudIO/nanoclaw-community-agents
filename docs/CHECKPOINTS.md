# Checkpoints: when is it ready, and what to verify after

Install steps are in [INSTALL.md](INSTALL.md); this is the **acceptance
side** — what a human tests before calling the system live, and what to
check at day 2, week 1, and month 1. Every item here is verifiable by
looking at something specific; none is "seems fine."

## The ready gate — do not call it live until every box is checked

Work through these in order after INSTALL.md §7's resume sequence. Each has
an expected result; a miss means stop and fix, not proceed.

| # | Test | How | Pass looks like |
|---|---|---|---|
| 1 | Owner DM round trip | DM the lead; ask it to proactively DM you back | Both directions arrive; replies come from the bot identity |
| 2 | Bot identity on GitHub | Ask the lead "what's not set up?" — it runs its own `setup-check.sh` and has each sub-agent relay theirs | All three tokens report `GET /user` login == the dedicated bot username — never yours |
| 3 | Support-tier auto-reply | Post a question in a support channel from a **non-owner** account, no @mention | Unprompted reply within a couple of minutes. Silence here = the Message Content intent is off in the Discord dev portal |
| 4 | Mention-only discipline | Post in a dev-tier channel *without* tagging the bot, then again *with* a tag | No reply to the first, a reply to the second |
| 5 | Non-owner DM redirect | DM the bot from a second account | Warm redirect to the public channels; no support answer, no instructions accepted |
| 6 | No per-sender prompts | Have that second account post in a public channel | You do **not** get a "new sender — allow?" approval ask (if you do, the wiring is missing `--sender-scope all`) |
| 7 | Sub-agent relay | DM the lead: "ping both sub-agents and relay their answers" | Both answer through the lead; neither ever posts anywhere itself |
| 8 | Every gate emits clean JSON | `./bin/ncl tasks run <id>` + `tasks get <id>` for each configured task | Single-line JSON, `not-configured` for things you skipped, real data for things you set up |
| 9 | Backup actually pushed | Check the backup repo on GitHub after the first `workspace-backup` run | A commit from the bot exists; `tasks get` shows `pushed` |
| 10 | Credential approval flow | Trigger one action that hits an OneCLI request-hold (if configured) | The approve/deny button appears and works — you've seen the flow once before it matters |
| 11 | Vault audit clean | `onecli apps connections agent-access` per provider (PREREQS.md §3) | Every grant matches a row in INSTALL.md §4's per-agent footprint table; nothing extra |
| 12 | Human backstop recorded | Ask the lead who the escalation backstop is | It names the person from the welcome interview — or plainly states the recorded open risk |
| 13 | You know the death signal | No action — confirm you understand it | The lead DMs a one-line heartbeat at least weekly; **more than ~8 days of silence means the sandbox died and needs a host-side restart.** Silence is the alarm |

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

## Week 1 — the first full weekly cycle

- **Heartbeat received**: the proof-of-life line arrived. If it didn't,
  investigate now — this is your outage detector and it must be known-good.
- **Weekly reports landed and read sane**: dev report (with the
  ready-to-merge section present, even if empty), follower snapshot appended
  to the lead's ledger, GA4/PostHog if enabled. Numbers carry deltas and
  windows; `null`s are explained, never silently zero.
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
  expectations ([OPERATIONS.md](OPERATIONS.md) → models and token budget).
  Over budget → pause in the documented order; never delete agents.
- **Question ledger is accumulating**: `plugin-data/community-support/question-ledger.jsonl`
  has one line per resolved support conversation. If it's empty after a
  month of real support traffic, the lead isn't logging — correct it. If
  `docs-gap-review` fired, its first docs proposal is the system's
  load-reduction loop working; review it seriously.
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
  (PostHog, GA4, inbox) worth enabling now? Anything in UPSTREAM-ISSUES.md
  confirmed and ready to file upstream?
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
