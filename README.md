# Community Agent Set for NanoClaw

Three templates that run an open-source project as a team with **one public
voice** — covering the four jobs that keep a project alive: people know about
it (awareness), reported issues get handled (response), problems get found
before users report them (proactive detection), and it stays secure. A support
lead talks to users on Discord and GitHub; two headless sub-agents (coding
ops, marketing ops) draft and hand off but never post.

| Template | Role | Public voice |
|---|---|---|
| [`support/community-support`](support/community-support/) | Lead — replies, triage, escalation, relays the sub-agents | **Yes — the only one** |
| [`engineering/community-coding`](engineering/community-coding/) | Issue/PR triage, security sweeps, dev metrics, telemetry | No |
| [`marketing/community-marketing`](marketing/community-marketing/) | Content drafts via PR, inbox triage, traffic analytics | No |

The lead works standalone; add sub-agents when you want that work done
without granting a second identity. Each template's README has per-agent
detail.

## Design principles

- **Scripts do the work; agents do the judgment.** 12 of 15 recurring tasks
  are script-gated: deterministic fetching, diffing, and thresholds run as
  bash with no model involved, and the agent wakes only when there's
  something to judge. The gates live as testable code in
  [`scripts/tasks/`](scripts/tasks/) — run [`scripts/test/run.sh`](scripts/test/run.sh)
  to exercise all of them without any agent, and
  `python3 scripts/sync-tasks.py --check` to verify the templates match their
  sources. Anything with *zero* judgment (label→channel notifications,
  secret scanning) belongs even further out, in CI — see
  [`examples/github-discord-notify.yml`](examples/github-discord-notify.yml).
- **Single public voice, enforced structurally.** Sub-agents have no channel
  wiring at all — they can't post publicly even if instructed to.
- **Statelessness by design.** Agents rebuild context from the project's
  repos on cold start; memory is a disposable cache of the web. The single
  durable asset is the social follower-count time series — and even that is
  documented as nice-to-have.
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
3. **[docs/OPERATIONS.md](docs/OPERATIONS.md)** — day 2 and beyond: models
   and token budget, the full task reference, the **update policy** (SHA-
   pinned image pulls only — see below), and resource budget.

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
