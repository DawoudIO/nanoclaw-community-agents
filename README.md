# Community Agent Set for NanoClaw

Four templates that run an open-source project as a team with **one public
voice** — covering the four jobs that keep a project alive: people know about
it (awareness), reported issues get handled (response), problems get found
before users report them (proactive detection), and it stays secure.

**North star: community support at low cost and high engagement, before people
give up on GitHub or Discord.** Every design choice below follows from that
sentence, and the agents are split by **model tier** to serve it — capable
models where judgment is needed, a free local model where reliability matters
more than capability.

| Template | Role | Model | Public voice |
|---|---|---|---|
| [`support/community-support`](support/community-support/) | Lead — replies, escalation, relays the sub-agents | Claude Sonnet | **Yes — the primary one** |
| [`local/community-local`](local/community-local/) | Narrates script-computed data, keeps mirrors fresh, acknowledges messages when the lead is rate-limited | **Local** (Ollama) | Holding replies only |
| [`engineering/community-coding`](engineering/community-coding/) | Reviewer — issue/PR triage, duplicates, security advisories, docs gaps. Read-only | Claude Haiku | No |
| [`marketing/community-marketing`](marketing/community-marketing/) | Content drafts via PR, in the project's audience's language | Claude | No |

The lead works standalone; add sub-agents when you want that work done without
granting a second identity. Each template's README has per-agent detail.

**Why a local agent is in this set.** The cloud-backed groups share one usage
window. When it closes, the lead stops replying — and silence is the failure
mode the north star is about, since response delay is the strongest predictor
of whether a first-time contributor comes back. The local agent has no window
to exhaust, so it keeps working: it holds the line with a templated
acknowledgment (never an answer) and logs the message for the lead to pick up.
It is deliberately restricted — see its
[never-do list](local/community-local/ai.nanoco.nanoclaw/context/instructions.md),
which is the load-bearing part of that template.

## Design principles

- **Scripts do the work; agents do the judgment.** 20 of 22 recurring tasks
  are script-gated: deterministic fetching, diffing, and thresholds run as
  bash with no model involved, and the agent wakes only when there's
  something to judge. Run `bash scripts/gen-task-table.sh` for the current
  task/agent/schedule table — it is generated from the task files, so it
  can't drift from what actually ships. The gates live as testable code in
  [`scripts/tasks/`](scripts/tasks/) — run [`scripts/test/run.sh`](scripts/test/run.sh)
  to exercise all of them without any agent, and
  `bash scripts/sync-tasks.sh --check` to verify the templates match their
  sources. Anything with *zero* judgment (label→channel notifications,
  secret scanning) belongs even further out, in CI — see
  [`examples/github-discord-notify.yml`](examples/github-discord-notify.yml).
- **Single public voice, enforced structurally.** The Reviewer and Marketing
  sub-agents have no channel wiring at all — they cannot post publicly even
  if instructed to. The local agent is the one deliberate exception: it needs
  one channel to deliver holding acknowledgments, so its restriction is
  enforced by *scope* instead — one channel, read-only credentials, no write
  access anywhere, and a template-only reply it is forbidden to compose
  freely. It is a receipt, never a resolution.
- **Statelessness by design.** Agents rebuild context from the project's
  repos on cold start; memory is a disposable cache of the web. The
  exceptions are a handful of append-only ledgers that can't be
  reconstructed (follower counts over time, the support-question ledger, the
  owner-instruction acks, the public-action log) — all captured by the
  workspace backup, all restored wholesale on a refresh. Nothing else is
  worth protecting, which is what makes recreate-don't-repair viable.
- **Agents never hold keys — everything goes through OneCLI.** Every
  credential lives only in the OneCLI vault and is injected into outbound
  requests at the egress proxy, *outside* the agent containers. No token
  ever appears in a template file, an env var, a chat message, or a script
  (the test harness enforces that last one). Never paste a key to an agent;
  an agent that asks for one is broken or compromised — refuse and
  investigate.
- **Least privilege, verified mechanically.** Each agent gets its own
  narrowly-scoped credential, and bot identity is checked with a real
  `GET /user` call against configured expectations — never assumed.
- **Setup is a conversation, not a form.** You DM the stamped lead and its
  `welcome` skill interviews you; configuration persists as runtime data,
  not template edits.

## Install and operate

1. **[PREREQS.md](PREREQS.md)** — create/audit/rotate every credential
   (exact URLs, real `onecli` commands). Read first.
2. **[docs/INSTALL.md](docs/INSTALL.md)** — the full runbook: prerequisites →
   sandbox → stamp/wire → credentials → configuration → go-live. Includes
   the complete question prep-sheet, the least-privilege scope tables, and
   the break-glass admin doctrine.
3. **[docs/CHECKPOINTS.md](docs/CHECKPOINTS.md)** — the acceptance side:
   the 17-point ready gate to pass before calling it live, then the day-2,
   week-1, and month-1 verification checkpoints.
4. **[docs/OPERATIONS.md](docs/OPERATIONS.md)** — day 2 and beyond: models
   and token budget, the full task reference, the **update policy** (SHA-
   pinned image pulls only — see below), and resource budget.
5. **[docs/REPORTING-STANDARD.md](docs/REPORTING-STANDARD.md)** — the shape
   every report follows, and why. A maintainer who starts skimming has
   silently turned the system off, so this is a correctness concern rather
   than a style guide: verdict line first, at most three exceptions, one
   rolled-up line for everything that didn't change.

**What runs when** is generated, never hand-written — so it can't drift from
what actually ships:

```bash
bash scripts/gen-task-table.sh          # task, agent, cadence, exact UTC time
bash scripts/gen-task-table.sh --state  # what each task persists: cache vs ledger
bash scripts/gen-task-table.sh --check  # fails the harness if a doc contradicts it
```

## Update policy: SHA-pinned packages only — never `git pull`

The running system is treated as a **sealed, versioned package**, not a
checkout:

- **Never `git pull` (or otherwise update in place) the NanoClaw source
  inside a running sandbox.** The runtime, its database schema, its task
  table, and its adapters version together; pulling newer source under a
  live install desynchronizes them and corrupts the deployment. There is no
  supported in-place upgrade path.
- **All upgrades are image pulls pinned by digest.**
  [`platform-baseline.json`](platform-baseline.json) records the exact
  `sha256` digest this template set was last verified against. Upgrading
  means: pull the new image *by digest*, recreate the sandbox, restamp the
  templates, restore from backup — the full procedure is in
  [docs/OPERATIONS.md](docs/OPERATIONS.md) → "Staying up to date."
- **A floating tag (`:latest`) is for discovering that an update exists, not
  for running one.** The weekly [`platform-watch`](.github/workflows/platform-watch.yml)
  Action compares the tag's current digest against the baseline and opens an
  issue when it moves; a human reads the release notes and decides. What you
  run is always the digest you verified.

Why: a digest is content-addressed — the same `sha256` is byte-for-byte the
same tested package everywhere, forever. A branch or floating tag is whatever
it happens to point at today.

## Companion documents (staging repo only)

- **[UPSTREAM-ISSUES.md](UPSTREAM-ISSUES.md)** — platform issues observed on
  a previous install, each with repro-on-clean-install steps; confirm on a
  clean install, then file against `nanocoai/nanoclaw`.

There's deliberately no migration runbook: this is a fresh install every
time, driven entirely by the welcome wizard's conversational interview. An
existing deployment's old credentials simply get revoked once the new one is
verified live — [docs/INSTALL.md](docs/INSTALL.md)'s least-privilege section
has the exact scopes to create fresh.

**Provenance**: this template set was extracted from a real production
deployment (the ChurchCRM open-source project's community agent) and
generalized; the worked example in the lead template's
`additional_context/example-mapping.md` comes from that deployment.

> This root README, docs/, and UPSTREAM-ISSUES.md are for the staging repo. A
> PR to `nanocoai/nanoclaw-templates` submits only the three template
> directories; the catalog has its own root README.
