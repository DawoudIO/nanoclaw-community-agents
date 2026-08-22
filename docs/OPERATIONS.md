# Operations — day 2 and beyond

Everything after go-live: token budget, the full task reference, keeping the
system alive, and the update policy. Install steps are in
[INSTALL.md](INSTALL.md); the ready gate and the day-2/week-1/month-1
verification checkpoints are in [CHECKPOINTS.md](CHECKPOINTS.md).

## Keeping it running — the session IS the system

`sbx run` is a foreground process: **NanoClaw stops when its terminal
session closes.** A laptop reboot, an SSH drop, or a closed tab takes the
whole system down — and a stopped system cannot report its own death, so the
symptom is pure silence. Two defenses:

- Run `sbx run` somewhere durable — a `tmux`/`screen` session on an
  always-on machine, not a laptop tab. After any host reboot, restarting it
  is a manual step: same `sbx run` command; the sandbox's state volume
  persists, so agents, config, and ledgers come back as they were.
- **Watch for the weekly heartbeat.** The lead's `health-check` task DMs a
  one-line "all checks passed" proof-of-life at least every 7 days even when
  everything is fine. If more than ~8 days pass without it, the system is
  down — restart the sandbox on the host. Silence is the alarm.

## Model budget — one shared window, and the trap in it

The kit's first-boot wizard accepts **a subscription, an OAuth token, or an
Anthropic API key** for Claude. That choice is the single most consequential
operational decision in this install, because it decides whether the agents
bill to their own meter or eat yours.

| Choice | Who pays | Consequence |
|---|---|---|
| **Subscription** (recommended: no per-token cost) | One usage window shared by the agents **and your own Claude Code sessions** | Cheapest, but see the trap below |
| API key | Pay-per-token, separate meter | Decoupled from your window; costs real money per wake |

### The trap: agents can lock you out of your own recovery tool

On a subscription, an agent that burns through the shared window takes your
Claude Code access down with it — **including the break-glass session
(`sbx exec … claude`) that is the documented way to fix a broken deployment.**
The recovery tool becomes unavailable at exactly the moment you need it, and
the failure looks like silence rather than an error.

The precedent is real and it's this project's own: the v1 deployment
**exhausted its plan limits running 4 agents.** This template set is 3 agents
with aggressive gating specifically because of that. Treat the shared window
as a resource with a hostile-neighbour problem, not an abstraction.

Four defenses, in order of effectiveness:

1. **Separate the meters where it counts.** If you can, put the agents on
   their own subscription (or an API key) and keep your personal Claude Code
   on yours. Full stop — this removes the failure mode instead of managing it.
2. **Pause tasks, don't downgrade models.** Moving the coding agent to local
   Ollama was evaluated and rejected — it saves little (the gates already cut
   coding to ~20–50 wakes/week on the cheapest tier) and shifts work onto the
   Sonnet-class lead that reviews its output. See
   [SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md). The pause-order list below is
   the real throttle.
3. **Keep the pause-order list to hand** (below). It's not a nice-to-have on
   a shared window — it's your throttle.
4. **Watch `clidash`** for session/usage state rather than discovering the
   ceiling by hitting it.

**And know what hitting it looks like**: the lead stops answering Discord
altogether — the community gets silence, which for a public-facing support
agent is the worst failure mode there is. A proposed safety net for exactly
this (a tiny always-local Ollama agent that posts holding acknowledgments
when the lead can't) is written up in
[SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md) — unverified wiring, decide after
install. It does not remove the need for the four defenses above; it just
makes the failure visible and polite instead of silent.

### What the install itself costs

**On a subscription, your install session and the agents draw from the same
window**, so budget them together:

- **Your Claude Code session**: ~16 documented commands plus `/add-discord`'s
  guided flow and reading each `templateReport`. Modest.
- **Welcome interview**: the biggest single line item — ~15K context per turn
  over 8–15 turns, heavily cache-discounted after the first.
- **Sub-agent relay + each `setup-check.sh`**: ~2–3 turns each, small.
- **Gate testing**: **13 of 16 gates exit `not-configured` with no model wake
  at all** — those are free. Only the ones you configured wake.
- **Smoke tests**: 3–4 real lead interactions.

### Measured context floors (per model wake, this template set)

Real measurements of the shipped files, not estimates. Every wake pays the
persona plus whatever skill loads:

| Agent | Persona + context | With its main skill |
|---|---|---|
| Lead | ~8.6K tokens | ~18.8K (community-support) · ~15K (welcome) |
| Coding | ~3.2K | ~6.2K |
| Marketing | ~3.9K | ~8.5K |

Task prompt bodies add ~400 tokens on average. The lead is the expensive one
and always will be — it carries the public-facing judgment. Prompt caching
makes repeat wakes much cheaper than these numbers suggest, since the persona
prefix is byte-identical every time.

### Will a single 5-hour window carry the install?

On volume, comfortably — nothing above is close to a ceiling. What actually
threatens it is **debugging loops**: a missed Message Content intent that
makes auto-reply silently fail, Discord wiring that won't round-trip, a token
scoped to the wrong repo list. Four things that protect the window:

1. **Finish PREREQS before you start the clock.** Every token created, vault
   loaded, identity verified. Credential problems are the most common stall
   and they're entirely front-loadable.
2. **Use the answers file.** `onboarding-answers.json` collapses an 8–15 turn
   interview into ~2 — on a shared window this is the single largest saving
   available, and it makes a retry nearly free.
3. **Don't interactively test all 18 gates.** Run the ones you configured;
   the other 13 are provably free and the harness covers their logic.
4. **Read the docs yourself rather than through the session** — `docs/` +
   PREREQS + README is ~22K tokens of context you don't need to spend.

Running out mid-install loses nothing: the sandbox state volume persists, and
"what's not set up?" plus each `setup-check.sh` resumes exactly where you
stopped. **But on a shared window, do the install when you don't need Claude
Code for anything else that day.**

## Right-sizing the agents

**Three agents is the right number — and it's cheaper than it looks.** Burn
comes from model *wakes*, not from agents existing: a stamped agent whose
tasks are paused costs nothing. 16 of 18 tasks are script-gated, so quiet
periods cost near zero regardless of agent count. The highest-frequency gate
by far — `repo-mirror-sync`, every 15 minutes — is also among the cheapest: a
sync with no upstream change never wakes the model at all. And the daily
`dev-metrics-report` doesn't just skip when unconfigured, it skips on any run
where nothing actually changed, with a 7-day heartbeat forcing a wake so the
channel never goes silent long enough to look dead. That makes the team elastic:
stamp all three, then tune budget by which tasks you activate — never by
deleting agents.

Two sizing mistakes this design specifically avoids (both were learned the
expensive way on a real deployment that exhausted its **subscription** limits
with 4 agents):

- **Don't add a "quick tasks" agent.** The lead stays responsive by design —
  scheduled work runs in isolated task sessions and long background work
  belongs to the sub-agents, so the owner DM is never stuck behind a slow
  thread. A fourth agent for responsiveness just duplicates context loads.
- **Don't merge everything into one agent to save tokens.** The savings are
  small (gated tasks already cost ~nothing when idle) and you lose the
  per-agent credential scoping and the single-voice structure.

**Model defaults per agent** (confirmed at cold start by the welcome flow —
the owner can change them there or later via group config):

| Agent | Default | Why |
|---|---|---|
| Lead | Sonnet-class | Public-facing judgment: tone, escalation calls, security routing |
| Marketing | Sonnet-class | Content quality is its whole job; drafts are the deliverable |
| Coding | Haiku-class | Triage/digest work with skills to guide it — and everything it produces is reviewed by the lead before publishing. Upgrade only if draft quality disappoints |

**Decided: no Ollama for the coding agent — Haiku stays.** Compared against
Haiku (not Sonnet), the case collapses: all 7 coding tasks together wake only
~20–50 times a week because the gates already suppress the rest, so there is
little left to save on the cheapest tier — while the risk lands precisely on
the judgment tasks (advisory reachability assessment, mirror-change
cross-referencing, triage duplicate/security detection). And because the
Sonnet-class lead reviews every coding output, degrading coding shifts work
onto the *more* expensive tier. On top of that, the only local model plausibly good enough
(`qwen3-coder:30b`, 18 GB) roughly triples the documented resource footprint
— and the coding agent barely writes code anyway; it reads GitHub metadata
and narrates it, which is a comprehension-and-judgment workload, not a
codegen one. Full reasoning, wake-volume table, and the model comparison:
[SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md). Revisit only if a genuinely
high-volume, purely mechanical workload appears (translation or bulk
classification, where a 1–2 GB model would earn its keep), or if clidash
shows coding consuming meaningfully after install.
**And a hard rule regardless of tier: never Opus-class on a scheduled task.**
Wakes are frequent; premium models belong in interactive sessions, not cron.

**If you hit the window ceiling** (on a shared subscription this also
restores your own Claude Code access), pause in this order — lowest value
first:
`repo-mirror-sync` → `repo-hygiene-audit` → `good-first-issue-health` → `draft-cleanup` → `dev-metrics-report` →
`social-metrics-snapshot` → `inbox-check` → reduce `github-ops-triage` to
2×/day → `content-draft-cycle` to 3×/week. The safety net (`health-check`,
`workspace-backup`, `weekly-identity-integrity-check`) and community replies
are the last things to give up — they're also nearly free, since all three
are gated.

## Reference: every task, required vs optional

"Silent skip" = safe to resume unconfigured (gate exits `not-configured` at
zero cost). "Leave paused" = agent-owned, no gate — resuming unconfigured burns
turns.

| Task | Agent | Wakes model | Needs | Unconfigured |
|---|---|---|---|---|
| `health-check` (every 3h) | lead | on a problem | nothing | safe |
| `workspace-backup` (daily) | lead | on failure | git repo + remote + `github.com` secret | silent skip |
| `daily-github-triage` (weekdays) | lead | only on new/updated items | lead PAT + `COMMUNITY_REPOS` in `plugin-data/community-support/config.env` | silent skip — leave paused permanently if coding agent stamped |
| `release-announcement-watch` (every 3h) | lead | only on a new stable release | lead PAT + `COMMUNITY_REPOS` | silent skip |
| `weekly-identity-integrity-check` | lead | only on prompt drift (hash gate) | nothing (`ncl`+`jq`; falls back to a manual-pass wake) | safe |
| `github-ops-triage` (4×/day) | coding | only on new/updated items | coding PAT + `COMMUNITY_REPOS` | silent skip |
| `security-advisory-sweep` (6×/day) | coding | on new alerts | coding PAT + Dependabot alerts (read) permission + `COMMUNITY_REPOS` | silent skip |
| `dev-metrics-report` (daily) | coding | only on notable change, else weekly heartbeat | PAT + `COMMUNITY_REPOS` | silent skip |
| `posthog-weekly-review` (Mon) | coding | only on an insight-value change, else a 28-day heartbeat | PostHog key + `POSTHOG_PROJECT_ID` + allowlist | silent skip |
| `repo-mirror-sync` (every 15m) | coding | only on a real content change or a sync failure | coding PAT + `MIRROR_REPOS` (falls back to `COMMUNITY_REPOS`) + `github.com` allowlisted for git | silent skip |
| `good-first-issue-health` (Mon) | coding | weekly | coding PAT + `COMMUNITY_REPOS` (+ optional `GFI_LABEL`) | silent skip |
| `docs-gap-review` (Tue) | lead | only when a support topic repeats 3+ times | question ledger (built up by normal support work) | safe — quiet until the ledger has data |
| `repo-hygiene-audit` (quarterly) | coding | only on missing community files | coding PAT + `COMMUNITY_REPOS` | silent skip |
| `inbox-check` (2×/day) | lead | every run | email MCP + read-only mailbox + allowlist | leave paused |
| `content-draft-cycle` (weekdays) | marketing | only on a new release or the 7-day floor | marketing PAT + `CONTENT_REPO` (+ optional `RELEASE_WATCH_REPO`) + brand source | silent skip |
| `weekly-analytics-report` (Sun) | marketing | weekly | GA4 OAuth + `GA4_PROPERTY_ID` + allowlist | silent skip |
| `draft-cleanup` (daily) | marketing | on stale PRs | PAT + `CONTENT_REPO` | silent skip |
| `social-metrics-snapshot` (Sun) | marketing | every run | public profile pages (no credentials) + **sandbox allowlist entries for the platform hosts** | leave paused until platforms are configured and allowlisted — it guards the one stateful asset (follower series; durable copy = the lead's ledger) |

**Shipped times (UTC under the kit) — deliberately staggered.** On a
memory-constrained host (a 16 GB Mac mini is the reference) every task
firing at :00 means several agent containers spinning up at once. These
are offset so no two tasks share a minute, and `unanswered-watch` keeps
the round minutes because it's the task the north star depends on:

| Agent | Task | Cron (UTC) |
|---|---|---|
| engineering | `daily-github-triage` | `13 13 * * 1-5` |
| engineering | `docs-gap-review` | `15 15 * * 2` |
| engineering | `github-ops-triage` | `35 */6 * * *` |
| engineering | `security-advisory-sweep` | `45 */4 * * *` |
| local | `dev-metrics-report` | `15 12 * * *` |
| local | `draft-cleanup` | `33 17 * * *` |
| local | `good-first-issue-health` | `16 16 * * 1` |
| local | `health-check` | `25 */3 * * *` |
| local | `posthog-weekly-review` | `5 15 * * 1` |
| local | `repo-hygiene-audit` | `55 10 1 */3 *` |
| local | `repo-mirror-sync` | `7,22,37,52 * * * *` |
| local | `social-metrics-snapshot` | `23 13 * * 0` |
| local | `unanswered-watch` | `*/10 * * * *` |
| local | `weekly-analytics-report` | `14 14 * * 0` |
| local | `workspace-backup` | `43 8 * * *` |
| marketing | `content-draft-cycle` | `37 13 * * 1-5` |
| support | `inbox-check` | `55 6,16 * * *` |
| support | `release-announcement-watch` | `5 */3 * * *` |
| support | `weekly-identity-integrity-check` | `45 15 * * 1` |

If you re-time these, keep them collision-free — the check is one command:

```bash
grep -h '^schedule:' */*/ai.nanoco.nanoclaw/tasks/*.md | sort | uniq -d
```

Rules of thumb: put the
integrity check before your own workday, dev metrics ahead of your dev
channel's hours, inbox checks at your real start/end of day. Ungated tasks cap
at 4 fires/day — the script gate is what lets health-check (8×) and the sweep
(6×) exceed it.

## Adding a new external capability — the three-layer recipe

Whenever the system needs to reach something new — a website, a search API,
another LLM (image generation, embeddings), any external service — the same
three layers apply, in order. The agent can *ask* for a capability; only you
can grant one, and the agent never receives a key at any layer.

1. **Network allowlist** (always): add the host to your local kit copy's
   `spec.yaml` → `permissions.network.allow` (e.g. `api.openai.com:443`) and
   recreate the sandbox with `--kit ./nanoclaw`. Default-deny is the
   security model — every hole is opened deliberately, per host, in a file
   agents can't write. For a keyless public website, this layer alone is the
   whole job.
2. **Vault entry** (if the service needs a key): `onecli secrets create`
   with a `--host-pattern` matching the new host (`--type openai` for an
   OpenAI-compatible LLM, `generic` for most others), or the dashboard. The
   proxy injects it; the key never enters an agent container.
3. **Selective grant** (if keyed): assign the new secret to **only** the
   agent whose job needs it, then update your copy of the per-agent
   footprint table (INSTALL.md §4) so the next `agent-access` audit doesn't
   flag the grant as unexplained.

Two policy gates on top, when they apply:

- **Paid, per-call services (image generation especially)** are an explicit
  owner opt-in — the agents' default-to-free rule means they must name the
  cost and any free alternative before you decide. Consider an OneCLI
  **request-hold** on the new host so each call needs your button-press
  approval until the usage pattern has earned trust.
- **Generated media is content**: an image an LLM produced flows through the
  same draft → PR → human-approval pipeline as any other content. A new
  capability never creates a new publishing path.

## Staying up to date — SHA-pinned pulls only, never `git pull`

**Hard rule: never update NanoClaw in place.** No `git pull` of the NanoClaw
source inside the sandbox, no in-place package upgrade, no floating-tag
re-pull under a live system. The runtime, its database schema, its task
table, and its adapters version together — pulling newer source or a newer
image under a running install desynchronizes them and corrupts the
deployment. NanoClaw documents no in-place upgrade path; do not invent one.

**All upgrades are digest-pinned image pulls plus a full recreate.** The
digest in [`platform-baseline.json`](../platform-baseline.json) is the exact
`sha256` this template set was last verified against — content-addressed, so
the same digest is byte-for-byte the same tested package everywhere. Pull by
digest (`docker.io/sbx/nanoclaw-kit@sha256:...`), never by tag, when you
actually upgrade; the `:latest` tag exists only so the watcher below can
notice that a new digest was published.

The system is built to make that upgrade path cheap: **cattle, not pets**.
Because almost nothing is stateful (context rebuilds from the web, config is a
conversation, the one durable file lives in the git backup), updating the
platform = recreating the sandbox — the same runbook you used to build it.

**Noticing updates is automated, not an agent job.** The
[`platform-watch`](../.github/workflows/platform-watch.yml) Action in this repo
runs weekly: it compares the sbx VM image digest (`sbx/nanoclaw-kit:latest`,
the prebuilt image this repo actually pulls), the latest NanoClaw release,
and the kit spec against `platform-baseline.json`,
and opens an issue here with a refresh checklist when any of them move.
Security advisories for NanoClaw deserve an immediate refresh; otherwise batch
refreshes when the issue appears.

**The refresh procedure** (~1 hour, mostly waiting on pulls):

1. Confirm the last workspace backup ran. The backup is a full
   `git add -A` of the lead's workspace, so it carries **everything in
   `plugin-data/` — restore that directory wholesale, not a hand-picked
   file or two.** Memory is a rebuildable cache, but these are append-only
   and cannot be reconstructed from the web:
   - `project-config.md` — the entire runtime config
   - `social-metrics-history.jsonl` — follower counts over time
   - `question-ledger.jsonl` — every resolved support topic;
     `docs-gap-review`'s only input, and it needs weeks of accumulation
     before it fires at all
   - `owner-instructions.jsonl` — the numbered ack ledger `health-check`
     watches for dropped threads
   - `public-actions.log` — what a session actually did publicly; the record
     that turns "unrecognized public action" into a lookup instead of an
     incident
   - `docs-proposals-sent.txt`, `seen-advisories.txt`, `nudge-sent-*.txt`,
     `known-contributors-*.txt` — dedup ledgers. Losing these isn't data
     loss so much as noise: the system re-proposes docs pages it already
     proposed and re-reports advisories it already handled.
2. Read the watch issue: it names the new digest. Verify it's what you
   intend (release notes, no open security advisories), then update
   `platform-baseline.json` to the new digest — that file is the record of
   what you verified.
3. `sbx rm nanoclaw` → `docker pull docker.io/sbx/nanoclaw-kit@sha256:<the
   verified digest>` → `sbx run` against that same digest. Never pull the
   bare `:latest` tag for the actual upgrade — the tag can move between your
   decision and your pull.
4. Restamp the latest templates from this repo; re-run `/add-discord` with the
   **same** Discord bot (its token comes from the Discord developer portal —
   the VM's stored copy died with the VM); re-verify the owner-DM round trip.
   Then **re-apply every platform skill marked "modifies install"** in
   [INSTALL.md → Platform skills](INSTALL.md) — clidash, and anything you
   adopted since (ollama-provider, dashboard). A fresh VM has none of them,
   and nothing detects their absence for you.
5. Re-enter the 3 GitHub PATs in the fresh vault, selective mode (~5 min).
   No rotation needed — refresh isn't compromise.
6. Restore `plugin-data/` from the backup repo into each agent's
   workspace (the lead's is the one the backup captures; sub-agent ledgers
   live in their own workspaces and are rebuildable). Restoring
   `project-config.md` skips re-interviewing — or hand the lead your filled
   `onboarding-answers.json` instead.
7. Smoke tests per INSTALL.md §7, and re-test anything in UPSTREAM-ISSUES.md
   against the new build before closing the watch issue.

**Template updates** flow the other way: edit this repo, restamp. Personas and
skills are read-only inside stamped agents by design, so a restamp *is* the
deployment mechanism — and the watch issue is a natural moment to fold in any
accumulated template improvements. Whether NanoClaw supports an in-place
upgrade instead of recreate is undocumented — tracked as an upstream docs ask
in UPSTREAM-ISSUES.md.
