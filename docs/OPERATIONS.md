# Operations — day 2 and beyond

Everything after go-live: token budget, the full task reference, keeping the
system alive, and the update policy. Install steps are in
[INSTALL.md](INSTALL.md); the ready gate and the day-2/week-1/month-1
verification checkpoints are in [CHECKPOINTS.md](CHECKPOINTS.md).

## Keeping it running

`nanoclaw.sh` installs a real background service (`launchd` on macOS,
`systemd` on Linux) — this is no longer the foreground-terminal, "session IS
the system" situation the old `sbx run` deployment had. The shipped plist
sets `RunAtLoad` and `KeepAlive`: the service starts on login/boot and
restarts itself if it crashes, without you doing anything. Confirm it's
actually running rather than assuming it: `launchctl list | grep nanoclaw`
(macOS) or the equivalent `systemctl` check on Linux.

That said, a stopped system still can't report its own death, so silence is
still the failure mode if something does take it down (a host that's fully
off, a launchd/systemd config that got removed). **Check liveness on demand rather than waiting to be told.** DM the manager the
single word `ping` — it answers `pong #<last-ledger-id> <UTC time>` and
nothing else, which separates "the system is down" from "a rule is being
ignored" in about five seconds.

Deliberately, there is **no heartbeat task** that reports "all healthy" on a
schedule. An alarm that fires by *not* arriving needs a human to notice the
absence, which nobody reliably does — and a per-container "my environment is
fine" signal is easily mistaken for system-wide health, which it never is.

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
(running `claude` from the `nanoclaw` checkout) that is the documented way
to fix a broken deployment.**
The recovery tool becomes unavailable at exactly the moment you need it, and
the failure looks like silence rather than an error.

The precedent is real and it's this project's own: the v1 deployment
**exhausted its plan limits running 4 agents** — four *cloud-backed* agents,
all on the one window. **This template set has a reduced version of the same
exposure**: one agent, but it still draws on that one window, and every
consolidation since has removed containers and wakes without changing the
shape: one cloud agent, one meter. A local-model provider (which would take
the agent off the window entirely, the way v1's design should have) was
evaluated and set aside — the public voice is exactly what you don't move to
a smaller model; see [SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md). Aggressive
gating is doing most of the mitigation work. Treat the shared window as a
resource with a hostile-neighbour problem, not an abstraction — and count
neighbours by meter, not by agent.

Four defenses, in order of effectiveness:

1. **Separate the meters where it counts.** If you can, put the agent on
   its own subscription (or an API key) and keep your personal Claude Code
   on yours. Full stop — this removes the failure mode instead of managing it.
2. **Pause tasks, don't downgrade the model.** A local model was evaluated
   and rejected — the gates already cut the scheduled wakes to a handful a
   day, and what is left is public-facing judgment. See
   [SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md). The pause-order list below is
   the real throttle.
3. **Keep the pause-order list to hand** (below). It's not a nice-to-have on
   a shared window — it's your throttle.
4. **Watch `clidash`** for session/usage state rather than discovering the
   ceiling by hitting it.

**And know what hitting it looks like**: the manager stops answering Discord
altogether — the community gets silence, which for a public-facing support
agent is the worst failure mode there is. **Nothing in this set covers that
case.** `unanswered-watch` runs every 5 minutes and its gate costs nothing
(local session state, no network, no credentials), but it wakes the same
agent on the same credential: it catches a question that scrolled past while
the agent was busy, restarting, or in another channel, and that is all. An
exhausted window exhausts it too. A backstop that survives exhaustion would
need its own credential or an off-window model, and this deployment
deliberately runs one agent on one credential — so the four defenses above
are the whole protection, not a fallback to one. One piece of the gate is
still **unverified** until a real install (the `ncl sessions list --json`
output shape); see [CHECKPOINTS.md](CHECKPOINTS.md) for how to prove it.

### What the install itself costs

**On a subscription, your install session and the agents draw from the same
window**, so budget them together:

- **Your Claude Code session**: ~16 documented commands plus `/add-discord`'s
  guided flow and reading each `templateReport`. Modest.
- **Welcome interview**: the biggest single line item — ~15K context per turn
  over 8–15 turns, heavily cache-discounted after the first.
- **`setup-check.sh`**: ~2–3 turns, small.
- **Gate testing**: the GitHub-facing gates exit `not-configured` with no
  model wake at all until `COMMUNITY_REPOS` is set — those are free (run
  `bash scripts/gen-task-table.sh --counts` for the current count).
  `docs-gap-review` exits `no-ledger-yet` (also free, and stays that way for
  weeks), and `conversation-archive-prune` never wakes a model at any point
  in its life. Only the gates you actually configured can cost you anything;
  `project-context`'s first run always wakes once, to take its baseline.
- **Smoke tests**: 3–4 real manager interactions.

### Measured context floors (per model wake, this template set)

Real measurements of the shipped files, not estimates. Every wake pays the
persona plus whatever skill loads:

| Agent | Persona + context | With its main skill |
|---|---|---|
| Manager | ~8.6K tokens | ~18.8K (community-manager) · ~15K (welcome) |

**Re-measure before trusting it for budget**: these numbers were taken before
`project-context` and `unanswered-watch` joined this agent. Measure the same
way they were: persona + context on a cold wake.

Task prompt bodies add ~400 tokens on average. Prompt caching makes repeat
wakes much cheaper than these numbers suggest, since the persona prefix is
byte-identical every time.

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
3. **Don't interactively test every gate script.** Run the ones you configured
   (`bash scripts/gen-task-table.sh` for the current count and which are
   gated); the rest are provably free and the harness covers their logic.
4. **Read the docs yourself rather than through the session** — `docs/` +
   PREREQS + README is ~22K tokens of context you don't need to spend.

Running out mid-install loses nothing: the sandbox state volume persists, and
"what's not set up?" plus each `setup-check.sh` resumes exactly where you
stopped. **But on a shared window, do the install when you don't need Claude
Code for anything else that day.**

### A long-running owner DM is the one thing this design doesn't bound

Every scheduled task in this set is either genuinely 0-token on a quiet day
or bounded to a small, known ceiling (see the cost tables in each template's
README) — that's the point of gating. **The owner's own direct conversation
with the manager is the one exception**, because it has to respond to real
messages and can't be gated the same way a scheduled task is.

That matters because there is **no supported way to reset an ongoing
conversation's accumulated cost** short of tearing down the whole agent
group. Confirmed directly against the platform source: `ncl groups restart`
respawns the container but reuses the same session row, and `ncl sessions`
exposes only `list`/`get`/`history` — no reset or rotate. A long single-
sitting exchange re-reads its entire accumulated history (plus the persona
prefix) from cache on every turn, and that cost compounds with turn count,
not with elapsed time. A measured real example: a 1,109-turn conversation
spanning a few days billed on the order of $15-20 on its own from cache
reads alone — on a tight monthly budget, one unusually long conversation can
be the majority of it.

**The practical mitigation, since no reset primitive exists**: keep owner-DM
exchanges focused and let them end naturally rather than treating one thread
as a running command line across many days. If a conversation feels
long-running, check `token-audit.sh` (ships at the manager's template
root — see the operator's toolkit above) for the real turn count and cache
totals before assuming a specific task is the cost driver; on a long enough
thread it usually isn't. Claude Code's own auto-compaction
(`CLAUDE_CODE_AUTO_COMPACT_WINDOW`, default 165000 tokens) bounds *marginal*
per-turn cost once a conversation's context crosses that size, but it
doesn't undo tokens already spent and doesn't cap turn count directly — it
softens the problem, it doesn't solve it.

## Right-sizing the agent

**The agent draws on your window** (see the trap section above — a
local-model provider was evaluated and set aside for this phase). Burn comes
from model *wakes*, not from the agent existing: a stamped agent whose tasks
are paused costs nothing. Every task is script-gated (run
`bash scripts/gen-task-table.sh --counts` for the exact count), so quiet
periods cost near zero. The two highest-frequency gates are also the two
cheapest, which is not a coincidence — frequency was traded for cheapness
deliberately. **`unanswered-watch` is the most frequent of all: every 10
minutes (`*/10`)**, and its *gate* is the cheapest thing in the system on
every axis at once — no network call, no credentials, nothing but local
session state. `github-first-response` polls GitHub every 5 minutes in bash
and wakes only on a genuinely new, unanswered item. And the daily
`project-context` does every fetch in bash, records every commit to
`recent-changes.csv`, and wakes the model only for something it must act on
(a changed skill or docs file, a release, a rewritten branch). A day of
ordinary commits is 0-token. Tune
budget by which tasks you activate, never by deleting the agent.

**Keep the public voice on the capable tier.** Cheap work done wrong in
public costs more than expensive work done right, and everything this agent
does is public-facing.

**Model default** (confirmed at cold start by the welcome flow — the owner
can change it there or later via group config):

| Agent | Default | Why |
|---|---|---|
| Manager | Sonnet-class **in steady state, Haiku-class during setup** | Public-facing judgment: tone, escalation calls, security routing. The welcome interview is structured Q&A and CLI calls, so it runs on Haiku and the manager promotes itself at the end of onboarding (`welcome/SKILL.md` §10) |

**The tier is not automatic — pin it, and restart.** Two separate traps
here, each invisible from the outside:

1. **An unpinned group is not Haiku.** With no model of its own it falls
   back to `NANOCLAW_DEFAULT_MODEL`, which no installer sets; unset, the
   platform sends no model and the provider SDK picks its own default — a
   Sonnet-class one (`src/config.ts`: "Unset means the provider SDK's own
   default, which is what every existing install gets"). So a setup interview
   on an unpinned group bills Sonnet rates for every turn.
2. **A pin does nothing until a restart.** `ncl groups config update
   --model …` only writes the row (the platform's own CLI help says so).
   Without `ncl groups restart` the config reads one tier while every wake
   bills the other.

Check the effective value with `ncl groups config get --id <group-id>`
after any tier change — it is the only thing that reports what a group will
actually run on.

**A hard rule regardless of tier: never Opus-class on a scheduled task.**
Wakes are frequent; premium models belong in interactive sessions, not cron.

**If you hit the window ceiling** (on a shared subscription this also
restores your own Claude Code access): there is no off-meter tier to lean on
right now. If a local-model provider is adopted later (see
[SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md)), this section's advice shifts:
the agent would cost host memory instead of window budget.

Pause in this order — lowest value first:

0. `follow-up-nudge` — weekly, one wake at most; pausing it only delays a
   check-in by a week.
1. `project-context` — wakes only when a skill or docs file changed, a
   release shipped, or a branch was rewritten; ordinary commits are recorded
   with no wake. Pausing it costs currency: the agent answers "is X
   released?" from the last `release-state.csv` it wrote, and says so.
   Resume it before anything else when the window recovers.
2. `docs-gap-review` — weekly, and it wakes only when a topic has repeated
   three times. Pausing it defers a docs proposal, nothing more.

`owner-instruction-watch` and `weekly-identity-integrity-check` are weekly
and gated to near-silence, so pausing them is effort without savings.

**Never pause, at any ceiling — cheap and irreplaceable:**

- **`unanswered-watch`.** Its *gate* has no network call, no credentials, and
  costs nothing regardless of window state; the wake only fires when a
  support question has actually sat unanswered past the grace period, and
  answering it is the job.
- **`github-first-response`.** Same shape: a 5-minute bash poll that wakes
  only on a new issue or PR nobody has replied to. First response is the
  strongest predictor of whether a contributor comes back.
- **`owner-tldr`.** It is the only routine path to the owner, it wakes only
  when its queue is non-empty, and pausing it means findings pile up unseen.
- **`conversation-archive-prune`.** Never wakes a model, and it is what keeps
  a known platform bug from filling the container's disk (see
  UPSTREAM-ISSUES.md #38). Pausing it trades nothing for an eventual crash
  loop.
- **Community replies.** They are the job.

Approved-but-unmerged PRs, stale good-first-issues and missing
community-health files are not scheduled at all — they are point-in-time
checks, so they live in the project repo's `repo-health` skill and run on
demand. Project metrics are not an agent job either: they run as GitHub
Actions in the project's own repos.

## How fast each surface actually is

Cadence questions are really three different questions, because the surfaces
have different mechanics:

| Surface | Path | Speed |
|---|---|---|
| **Discord** | **Live.** The manager is wired to the channels and answers events as they arrive — no cron involved | realtime |
| Discord, when a question scrolled past | `unanswered-watch` wakes the manager to answer it | ≤5 min + `ACK_GRACE_MINUTES` (default 5); detection is free, the answer is one wake |
| **GitHub** | No live wiring in this design, so it polls: `github-first-response` finds new unanswered items | ≤10 min + grace |
| "Is X released yet?" | answered from `release-state.csv`, which `project-context` rewrites daily | ≤24h behind the repo; no fetch at answer time |
| Everything else | its own gated schedule, posted to the channel that cares | see the table below |
| **The owner's DM** | `owner-tldr` digest, plus urgent bypass | **07:00 the owner's local time**, or ~4h for "we may be blind" while they're awake |

**The digest is the one schedule that is timezone-correct by itself.** Every
other time in this system is a UTC cron line that you adjust by hand before
stamping; `owner-tldr` runs every 2 hours and works out whether it is 07:00
where the owner is, from `OWNER_TZ`. So it follows daylight saving with no
maintenance, and an unresolvable zone is reported rather than silently becoming
UTC (`tz_resolved: false`).

The two things worth internalising: **Discord is realtime and GitHub is a
5-minute poll**, and **most of what the agent does never reaches the owner at
all** — it answers people where they asked. The owner's DM is for what needs
the owner, which is a much shorter list.

## Reference: every task, required vs optional

**Agent and schedule columns are generated, not hand-written.** Run
`bash scripts/gen-task-table.sh` for the authoritative task → agent → cron
mapping; it derives that from the task files themselves, so it cannot go stale
the way this prose can. `--check` is wired into the test harness and fails the
build on doc drift. The table below quotes it and adds the two columns a
script can't derive: what each task actually *needs*, and what happens if you
leave it unconfigured. Earlier versions of this table attributed roughly a
dozen tasks to the wrong agent and omitted `unanswered-watch` entirely — which
is exactly why the generator now exists.

Reading the columns: "silent skip" = safe to resume unconfigured (gate exits
`not-configured` at zero cost). "Leave paused" = ungated, so resuming
unconfigured burns turns on every fire.

**Manager** (`opensource/community-manager`) — every task; config in
`plugin-data/community-manager/config.env`:

| Task | Wakes model | Needs | Unconfigured |
|---|---|---|---|
| `conversation-archive-prune` (daily) | **never** | nothing | safe |
| `docs-gap-review` (Tue) | only when a support topic repeats 3+ times | the manager's own `plugin-data/community-manager/question-ledger.csv`, built up by normal support work | safe — quiet until the ledger has data |
| `follow-up-nudge` (Wed) | only when an outsider's PR has sat idle `STALE_PR_DAYS` (7) days, or an issue the agent answered with a fix/workaround has had no reply for `FOLLOWUP_DAYS` (5) — one check-in per item per `RENUDGE_DAYS` (30), with `CHAT_INVITE_URL` offered if set | manager PAT + `COMMUNITY_REPOS`; the agent's own `issue-followups.csv` and `nudged.csv` | safe — quiet until something has gone silent |
| `github-first-response` (**every 5m**) | only on a brand-new issue/PR nobody has replied to — no grace by default, the owner wants near-real-time while the person is still there | manager PAT + `COMMUNITY_REPOS` (+ optional `FIRST_RESPONSE_GRACE_MINUTES`, default 15) | silent skip |
| `owner-instruction-watch` (Mon) | only when an owner instruction was acked `received` and never closed | nothing (`jq` over the instruction ledger) | safe |
| `owner-tldr` (**07:00 owner-local**) | only when the digest queue is non-empty, and only at the owner's morning hour — `attention` items escalate within ~4h during their waking window; urgent bypasses the queue entirely | `jq` only — **no network, no credentials** (+ `OWNER_TZ`, `TLDR_LOCAL_HOUR`) | safe, but set `OWNER_TZ`: without it the digest runs on UTC, which for most owners is the wrong morning. This is the ONLY routine path to the owner |
| `project-context` (daily, 06:08) | only when a changed `.agents/skills/**` or docs file needs re-reading, a release shipped, a branch was rewritten, on the first run (`baseline`), or when a repo could not be read — ordinary commits are recorded to `recent-changes.csv` with no wake (`status: recorded`) | manager PAT + `CONTEXT_REPOS` (defaults to `COMMUNITY_REPOS`). Writes `release-state.csv` every run; the agent keeps `project-notes.md` | silent skip |
| `unanswered-watch` (**every 5m**) | only when the newest message in a support channel is inbound and older than `ACK_GRACE_MINUTES` (default 5) — then the manager answers it for real | `ncl`+`jq` — **no network, no credentials**; the support channels must be wired to this agent | reports `no-channel-sessions` until the channels are wired — check for it, it looks like a quiet night |
| `weekly-identity-integrity-check` (Mon) | only on prompt drift (hash gate) | nothing (`ncl`+`jq`; falls back to a manual-pass wake) | safe |

**Shipped times (written in UTC; fire in each group's configured
timezone) — deliberately staggered.** The cron lines below are as written
in the task frontmatter. What timezone they actually fire in is per-group:
`ncl groups config update --timezone <IANA id>` sets it and takes effect
immediately (confirmed against `src/modules/scheduling/recurrence.ts` and
its test) — no cancel-and-recreate needed, and no restart. Unset, a group
defaults to the install-wide default, which itself defaults to **whatever
timezone the host machine reports**, not UTC (`src/config.ts`'s
`resolveConfigTimezone()` — UTC is only the fallback if that detection
fails). So don't assume these times land in UTC on your install; check
each group's actual timezone before reading this table as wall-clock time.

On a memory-constrained host (a 16 GB Mac mini is the reference) every task
firing at :00 means several gate scripts spinning up at once. These are
offset so no two tasks share a minute, and `unanswered-watch` keeps the
round minutes because it's the task the north star depends on:

| Task | Agent | Cadence | When (UTC) | Gated |
|------|-------|---------|------------|-------|
| `conversation-archive-prune` | Manager | **daily** | 05:18 | yes |
| `docs-gap-review` | Manager | **weekly** | 15:16, Tue | yes |
| `follow-up-nudge` | Manager | **weekly** | 15:26, Wed | yes |
| `github-first-response` | Manager | **12× hourly** | :2/7/12/17/22/27/32/37/42/47/52/57 each hour | yes |
| `owner-instruction-watch` | Manager | **weekly** | 16:23, Mon | yes |
| `owner-tldr` | Manager | **every 2h** | every 2h at :41 | yes |
| `project-context` | Manager | **daily** | 06:08 | yes |
| `unanswered-watch` | Manager | **every 5 min** | on the 5-minute mark | yes |
| `weekly-identity-integrity-check` | Manager | **weekly** | 15:46, Mon | yes |

_9 tasks on one agent; 9 script-gated_
_Generated by `scripts/gen-task-table.sh` — do not hand-edit._

**This table is generated — do not hand-edit it.** It was hand-maintained
until a `posthog-weekly-review` move once left it claiming the wrong agent
and the wrong minute, so it now comes straight from the task files:

```bash
bash scripts/gen-task-table.sh
```

If you re-time these, keep them collision-free — but **do not check it by
comparing cron strings.** That is what we did, and it missed two real
collisions: `5 */3 * * *` and `5 15 * * 1` are different strings that both
fire at 15:05 on Mondays, and `7,22,37,52 * * * *` quietly claims four minutes
of every hour. The harness now expands every field across minute × hour ×
day-of-week:

```bash
bash scripts/test/run.sh        # fails on any two tasks sharing a firing slot
```

Rules of thumb: put the integrity check before your own workday, and
`project-context` before your community's day starts, so the agent answers
from today's repo state rather than yesterday's.

**No task wakes its model on every fire, and none wakes on a routine day.**
`project-context` records daily commits without waking; it wakes only for a
changed skill or docs file, a release, or a rewritten branch — a few times a
month on an active project, not daily.

Everything else is 0-token when there's nothing to judge — **all 9 tasks are
gated, and ~99% of all scheduled runs cost nothing**, because the two
highest-frequency tasks are both gated: `unanswered-watch` at 144×/day and
`github-first-response` at 144×/day, plus `owner-tldr` at 12×, all costing
nothing on the runs where the gate finds nothing to say. Out of ~300
scheduled executions a day, none is guaranteed to spend tokens.

## Local telemetry — one file per task, worth a weekly look

Every gate script mirrors its own one-line JSON output to a local file:
`plugin-data/community-manager/telemetry/<task-name>.jsonl`, one line per run.
It is local, disposable, published nowhere, and exists purely so you can see
wake/error patterns over time and adjust a gate's threshold, cadence, or
config if something looks off.

```bash
# how often did each task actually wake the model this week?
jq -s 'group_by(.task) | map({task: .[0].task, runs: length,
  wakes: (map(select(.wakeAgent == true)) | length)})' \
  groups/<folder>/plugin-data/community-manager/telemetry/*.jsonl

# any errors (fetch-failed, script crash) surfaced this week?
jq -s '[.[] | select(.data.status | test("fail|error"; "i"))]' \
  groups/<folder>/plugin-data/community-manager/telemetry/*.jsonl
```

It's written via a background pipe inside each script, so on a very fast
exit the last line can occasionally be dropped — an accepted trade, since
the alternative (touching every exit path in every gate) was a much larger
and riskier change for what's meant to be a casual, adjust-as-you-go log,
not a source of truth. There's no scheduled task that reads or reports on
this file; reviewing it is a manual, human habit.

## The operator's toolkit — three scripts worth knowing about

These run on your machine against this repo or a live install. Neither is an
agent job; both exist because the alternatives were "read prose and hope" and
"redo the interview."

**`bash scripts/gen-task-table.sh`** — prints the authoritative task → agent →
cron → gated table, derived from the task files. Use it instead of trusting any
hand-written list, including the ones in this file. `--counts` gives just the
headline numbers; **`--check` verifies the docs against reality and is wired
into `scripts/test/run.sh`, so doc drift fails the harness rather than
shipping.** It exists because every hand-written topology table in these docs
went stale the moment the topology changed, and nothing caught it — prose isn't
testable, so the generator makes it testable.

**`bash scripts/export-answers.sh <nanoclaw-root> [out.json]`** — walks a live
install and writes its configuration back out in the shape
`onboarding-answers.example.json` used to document (that file is deliberately
absent for now, deferred until closer to a real test pass — see
SKILLS-ADOPTION.md; the script fails with a clear message if you run it
before recreating one). This closes the round trip: onboarding can
be done conversationally, which is friendlier but leaves the answers in
`config.env` and `project-config.md` with no single editable record. Export
gives you that record, so **changing one value means editing one line and
rebuilding instead of redoing the interview** — and it's what to run *before*
tearing an install down for a recreate. Two limits to know: it recovers every
`config.env` key the template actually reads, preserves
`project-config.md` verbatim rather than pretending to parse prose, and cannot
recover anything that never lands in `config.env` (free-text tone guidance
stays null with its `_ask` text intact). **It refuses to write the file at all
if it finds a credential in a `config.env`** — secrets live in the OneCLI vault
by design, and an answers file is something you diff, edit, and commit.

**`bash scripts/db-health-check.sh <nanoclaw-root> [--checkpoint]`** — run this
the moment `ncl tasks list`/`ncl tasks run` looks broken, **before** trying
anything else. A real install hit intermittent task-DB failures repeatedly
with no way to tell "genuinely corrupted" apart from "just locked" from the
CLI's error text alone — this script runs SQLite's own `PRAGMA
integrity_check` (read-only, always safe, even against a DB another process
still has open) against every `.db` file it finds, and tells you which. If
it's corrupted, it prints the least-destructive recovery command instead of
running it — that step can silently drop rows, so it stays a human decision.
`--checkpoint` additionally runs `PRAGMA wal_checkpoint(TRUNCATE)` on any DB
that passes — also always safe, and the routine maintenance most likely to
prevent the corruption in the first place (see UPSTREAM-ISSUES.md #18: the
central DB is missing hardening this same platform already added to its
per-session DBs after hitting this exact class of bug there once). For the
exact step-by-step — finding the real data directory, what to capture for
the team — see
[DB-HEALTH-CHECK-RUNBOOK.md](DB-HEALTH-CHECK-RUNBOOK.md).

## `token-audit.sh` — the one tool that ships INSIDE the agent, not beside it

Unlike the three scripts above, `token-audit.sh` isn't something you run —
it's a template-root file (next to `setup-check.sh`) that stamps into the
group's folder and runs **in the agent's own container**, invoked by the
agent itself via Bash when the owner asks "where is our budget going."

Real per-session token counts (input, output, cache read, cache creation)
straight from the transcript's own `usage` fields, plus a byte/line
inventory of the static context files (persona, memory) and any
JSON/JSONL `plugin-data` worth converting to CSV. Pure `jq` over a local
file — no LLM call, so the question costs nothing to answer and can be
re-run anytime without spending the budget it's trying to explain.

**It deliberately stops at token counts and never computes a dollar
figure** — that was a real mistake once: an agent reading this script's own
accurate token counts then quoted a cost from its training memory, and it
landed on the *previous* Sonnet generation's price per token (about 1.5x
the actual current rate), because pricing changes faster than a model's
training data does. The script's own final section tells the agent that
directly: look up the current published rate at answer time, never from
memory, or point the owner at the Admin API's usage/cost report if they
have an admin credential — that's ground truth, this script's counts are
the reliable second-best source, and a recalled price table is not a
source at all.

## Adding a new external capability — the three-layer recipe

Whenever the system needs to reach something new — a website, a search API,
another LLM (image generation, embeddings), any external service — the same
three layers apply, in order. The agent can *ask* for a capability; only you
can grant one, and the agent never receives a key at any layer.

1. **Network reachability** (check first — there's no per-host allowlist to
   edit anymore). The old `sbx`-kit `spec.yaml` had a per-host allowlist;
   without `sbx`, egress is binary: open by default, or fully gateway-only
   if `NANOCLAW_EGRESS_LOCKDOWN=true` is set — there's no "add just this one
   host" step in between. If lockdown is off, a keyless public website needs
   nothing here at all. If lockdown is on, the new host is reachable through
   the gateway the same as everything else already routed through it — no
   separate per-host grant exists to add.
2. **Vault entry** (if the service needs a key): `onecli secrets create`
   with a `--host-pattern` matching the new host (`--type openai` for an
   OpenAI-compatible LLM, `generic` for most others), or the dashboard. The
   proxy injects it; the key never enters an agent container.
3. **Selective grant** (if keyed): assign the new secret to the agent, then
   update your copy of the footprint table (INSTALL.md §2) so the next
   `agent-access` audit doesn't flag the grant as unexplained.

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
digest, never by tag, when you actually upgrade.

The system is built to make that upgrade path cheap: **cattle, not pets**.
Because almost nothing is stateful (context rebuilds from the repos, config
is a conversation, and everything the agent keeps sits in one directory),
updating the platform = recreating the install — the same runbook you used to
build it.

**Noticing updates is a manual job.** There is no automated watcher for the
image digest — check
[`nanocoai/nanoclaw`'s releases](https://github.com/nanocoai/nanoclaw/releases)
and `versions.json`'s `agent-image` field by hand, periodically, and update
`platform-baseline.json` yourself when you've verified a new one.

**The refresh procedure** (~1 hour, mostly waiting on pulls):

1. **Decide what, if anything, to copy out of
   `plugin-data/community-manager/`.** Nothing is published anywhere and
   there is no workspace backup in this set, by design: a restore nobody runs
   is a write-only cost. That one directory is everything the agent keeps,
   and it dies with the container:
   - `project-config.md` — re-created by the welcome interview, or instantly
     from `onboarding-answers.json` (see step 6).
   - Dedup caches (`acknowledged.txt`, `docs-proposals-sent.txt`,
     `first-response-seen.csv`, `context-heads.csv`) — losing these is noise,
     not data loss: the system re-answers a message it already answered, once,
     and `project-context` takes a fresh baseline on its next run.
   - `release-state.csv` and `project-notes.md` — rewritten by the next
     `project-context` run; nothing to save.
   - `question-ledger.csv` — `docs-gap-review`'s only input. It rebuilds from
     live traffic over weeks, so a rebuild resets that clock.
   - `owner-instructions.jsonl`, `digest-queue.jsonl` and `public-actions.log`
     — the ack, digest and public-action records. These are deliberately
     never published: they contain community members' words and the owner's
     private direction, which don't belong in a repo branch. They only need to
     outlive a session, not a repave.

   If you decide you *do* want one of those preserved, `cp -r` the directory
   out by hand before the recreate — but decide that deliberately rather than
   assuming a backup exists.
2. Check for a new NanoClaw release and a new agent image digest
   (`versions.json`'s `agent-image` field, or the hardened-image registry).
   Verify it's what you intend (release notes, no open security advisories),
   then update `platform-baseline.json` to the new digest — that file is the
   record of what you verified. There's no automated watcher for the image
   digest right now (see "Noticing updates" above) — this step is manual
   until one exists.
3. Stop the service, pull the new agent image by digest — never a floating
   `:latest` tag, which can move between your decision and your pull — and
   restart. The exact pull/recreate command depends on whether you're on the
   hardened-image path or building locally (`docs/hardened-image.md` in the
   `nanoclaw` repo); this deployment no longer goes through `sbx rm`/`sbx run`.
4. Restamp the latest templates from this repo; re-run `/add-discord` with the
   **same** Discord bot (its token comes from the Discord developer portal —
   the VM's stored copy died with the VM); re-verify the owner-DM round trip.
   Then **re-apply every platform skill marked "modifies install"** in
   [INSTALL.md → Platform skills](INSTALL.md) — clidash, and anything you
   adopted since (dashboard). A fresh VM has none of them, and nothing
   detects their absence for you. (If you've since adopted a local-model
   provider — see [SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md) — re-apply and
   re-verify that too; it isn't part of this phase's default.)
5. Re-enter the GitHub PAT in the fresh vault, selective mode (~5 min). No
   rotation needed — refresh isn't compromise.
6. **Don't restore plugin-data — re-interview instead.** Hand the manager your
   filled `onboarding-answers.json` and it re-creates its config; if the live
   install predates that file, run `bash scripts/export-answers.sh` to
   reconstruct one *before* you tear the install down. `project-context`
   needs no restore step: its first run after the recreate takes a new
   baseline and rewrites `release-state.csv`.
7. Smoke tests per INSTALL.md §4, and re-test anything in UPSTREAM-ISSUES.md
   against the new build before closing the watch issue.

**Template updates** flow the other way: edit this repo, restamp. Personas and
skills are read-only inside stamped agents by design, so a restamp *is* the
deployment mechanism — and the watch issue is a natural moment to fold in any
accumulated template improvements. Whether NanoClaw supports an in-place
upgrade instead of recreate is undocumented — tracked as an upstream docs ask
in UPSTREAM-ISSUES.md.
