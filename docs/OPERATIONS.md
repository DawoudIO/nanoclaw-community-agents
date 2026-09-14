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
Note the honest limit of `ping`: it proves the *manager* is alive. A sub-agent
that has stopped shows up instead as its reports going quiet.
  Two consequences of that chain worth knowing: the *detection* half runs on
  no model at all and so keeps working when the Claude window is gone, but the
  *delivery* half goes through the manager. A missing heartbeat therefore means
  "something upstream of your DM is broken" — a dead sandbox, or a manager that
  can't speak — which is exactly the set of things you want to be told about.

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
exposure**: both agents draw on that one window. Retiring the fourth
(narration) agent removed a whole container's worth of both memory and
wakes, which is part of why that consolidation happened at all — but it did
not change the fundamental shape: three cloud agents, one meter. A
local-model provider for a sub-agent (which would take it off the window
entirely, the way v1's design should have) was evaluated and set aside — too
much host setup to get the system working end to end first; see
[SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md). Aggressive gating is doing more
of the mitigation work than it would otherwise need to, until that's
revisited. Treat the shared window as a resource with a hostile-neighbour
problem, not an abstraction — and count neighbours by meter, not by agent.

Four defenses, in order of effectiveness:

1. **Separate the meters where it counts.** If you can, put the agents on
   their own subscription (or an API key) and keep your personal Claude Code
   on yours. Full stop — this removes the failure mode instead of managing it.
2. **Pause tasks, don't downgrade models.** Moving the helper to local
   Ollama was evaluated and rejected — it saves little (the gates already cut
   the helper to ~20–50 wakes/week on the cheapest tier) and shifts work onto the
   Sonnet-class manager that reviews its output. See
   [SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md). The pause-order list below is
   the real throttle.
3. **Keep the pause-order list to hand** (below). It's not a nice-to-have on
   a shared window — it's your throttle.
4. **Watch `clidash`** for session/usage state rather than discovering the
   ceiling by hitting it.

**And know what hitting it looks like**: the manager stops answering Discord
altogether — the community gets silence, which for a public-facing support
agent is the worst failure mode there is. The safety net for exactly this now
ships: the Helper's `unanswered-watch` **gate** runs every 10 minutes,
sees only local session state (no network, no credentials), and costs
nothing regardless of the shared window's state — so the *detection* survives
a window exhaustion. **The acknowledgment itself does not**, for this phase:
posting it is still a model wake on the Helper, which shares the same
cloud window as the manager. If the window is fully exhausted, both the manager and
the acknowledger go quiet together. This is a real, reduced version of the
safety net compared to an off-window local model — see
[SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md) for why Ollama was set aside and
what adopting it later would restore. It does not remove the need for the
four defenses above — a receipt is not a resolution — it just makes the
failure visible and polite instead of silent, when the window allows it. Two pieces of its wiring are
still **unverified** until a real install (whether two groups can share one
Discord channel, and the `ncl messages list --json` output shape); see
[CHECKPOINTS.md](CHECKPOINTS.md) for how to prove both.

### What the install itself costs

**On a subscription, your install session and the agents draw from the same
window**, so budget them together:

- **Your Claude Code session**: ~16 documented commands plus `/add-discord`'s
  guided flow and reading each `templateReport`. Modest.
- **Welcome interview**: the biggest single line item — ~15K context per turn
  over 8–15 turns, heavily cache-discounted after the first.
- **Sub-agent relay + each `setup-check.sh`**: ~2–3 turns each, small.
- **Gate testing**: most script-gated tasks exit `not-configured` with no
  model wake at all on a fresh install — those are free (run
  `bash scripts/gen-task-table.sh --counts` for the current split).
  `docs-gap-review` exits `no-ledger-yet` (also free, and stays that way for
  weeks), and `ledger-publish` / `conversation-archive-prune` never wake a
  model on success at any point in their lives. Only the gates you actually
  configured can cost you anything.
- **Smoke tests**: 3–4 real manager interactions.

### Measured context floors (per model wake, this template set)

Real measurements of the shipped files, not estimates. Every wake pays the
persona plus whatever skill loads:

| Agent | Persona + context | With its main skill |
|---|---|---|
| Manager | ~8.6K tokens | ~18.8K (community-manager) · ~15K (welcome) |
| Helper | ~3.2K | ~6.2K |

**Re-measure the Helper's row** before trusting it for budget: it carries nearly
every task in the set, so its floor is the one that matters most here, and
these numbers were taken against a smaller persona. Measure the same way they
were: persona + context on a cold wake. See
[SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md).

Task prompt bodies add ~400 tokens on average. The manager is the expensive one
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
3. **Don't interactively test every gate script.** Run the ones you configured
   (`bash scripts/gen-task-table.sh` for the current count and which are
   gated); the rest are provably free and the harness covers their logic.
4. **Read the docs yourself rather than through the session** — `docs/` +
   PREREQS + README is ~22K tokens of context you don't need to spend.

Running out mid-install loses nothing: the sandbox state volume persists, and
"what's not set up?" plus each `setup-check.sh` resumes exactly where you
stopped. **But on a shared window, do the install when you don't need Claude
Code for anything else that day.**

## Right-sizing the agents

**Both agents currently draw on your window** (see the trap section
above — a local-model provider was evaluated and set aside for this phase).
Burn comes from model *wakes*, not from agents existing: a stamped agent
whose tasks are paused costs nothing. Nearly all tasks are script-gated (run
`bash scripts/gen-task-table.sh --counts` for the exact split), so quiet
periods cost near zero regardless of agent count. The two highest-frequency
gates are also the two
cheapest, which is not a coincidence — frequency was traded for cheapness
deliberately. **`unanswered-watch` is the most frequent of all: every 10
minutes (`*/10`)**, and its *gate* is the cheapest thing in the system on
every axis at once — no network call, no credentials, nothing but local
session state. Its acknowledgment does cost a Haiku wake on the Helper,
which shares this window; the detection is what stays free. That combination
is the point: the task the north star depends on had to be the one thing
that can't be knocked over by an outage, even if it can be slowed by an
exhausted window. And the daily
`dev-metrics-report` doesn't just skip when unconfigured, it skips on any run
where nothing actually changed, with a heartbeat forcing an occasional wake so
the channel never goes silent long enough to look dead. That makes the team
elastic: stamp what you need, then tune budget by which tasks you activate —
never by deleting agents.

**Two agents is the floor, not a starting point to trim further.** A real
deployment exhausted its **subscription** limits running four cloud-backed
agents, which is why agent count is treated as a budget item here at all. Two
still share one meter, so the pause-order list below is your throttle.

Two rules worth keeping:

- **Don't merge the last two to save tokens.** The savings are small (gated
  tasks already cost ~nothing when idle) and you would lose the thing that
  actually protects you: separate credential scoping, and a single public
  voice that a sub-agent structurally cannot speak with.
- **Keep the public voice on the capable tier.** The split is by *model tier*
  for a reason. Cheap work done wrong in public costs more than expensive work
  done right — which is exactly why the Helper's one public-facing task is
  restricted to a fixed template it cannot compose freely.

**Model defaults per agent** (confirmed at cold start by the welcome flow —
the owner can change them there or later via group config):

| Agent | Default | Why |
|---|---|---|
| Manager | Sonnet-class | Public-facing judgment: tone, escalation calls, security routing |
| Helper | Haiku-class | Triage/digest judgment with skills to guide it, and everything it produces is reviewed by the manager before publishing — except the one fixed holding line it may post itself, which it cannot compose freely. Upgrade only if quality disappoints |

**Decided: no local model for the Helper — Haiku stays.** Compared against
Haiku (not Sonnet), the case collapses: the Helper's tasks together wake
only a few dozen times a week because the gates already suppress the rest, so
there is little left to save on the cheapest tier — while the risk lands
precisely on what's left, which is nothing but judgment: advisory reachability
assessment and triage duplicate detection. Because the Sonnet-class manager reviews
every Helper output, degrading the Helper shifts work onto the *more*
expensive tier. And the only local model plausibly good enough
(`qwen3-coder:30b`, 18 GB) does not fit alongside everything else on a 16 GB
host at all. Full reasoning, wake-volume table, and model comparison:
[SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md). Note the contrast with the
agent, which took the mechanical work *away* from this tier rather than
degrading the tier itself — that's the move that generalizes.

**A hard rule regardless of tier: never Opus-class on a scheduled task.**
Wakes are frequent; premium models belong in interactive sessions, not cron.

**If you hit the window ceiling** (on a shared subscription this also
restores your own Claude Code access): **both agents draw on that
meter** — there is no off-meter tier to lean on right now. The Helper
costs less per-wake than the manager (cheapest cloud tier, aggressively gated),
so its tasks are lower priority to pause than genuinely expensive ones, but
pausing them is a real lever. If a local-model provider is adopted later (see
[SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md)), this section's advice shifts:
whichever agent moved off the window would cost host memory instead of window
budget.

Pause in this order — lowest value first, across both agents:

1. `daily-github-triage` — if the Helper is stamped it's already redundant
   with `github-ops-triage`; it should be paused anyway.
2. `inbox-check` — ungated, so it wakes the manager on **every** run, twice a day,
   whether or not there's mail. Per-wake it's the most reliably expensive thing
   in the set.
3. `contributor-health-review` — a reasonable early pause: nothing it reports
   is time-sensitive. It reads 30- and 90-day windows weekly, and the signals
   it tracks (unmerged ratio, contribution concentration) move over months, so
   a few skipped weeks change the picture by nothing. One cost worth knowing:
   its history only gains a point on a run, so after a pause the next run
   diffs against the last week it actually ran — the first post-resume "move"
   will look larger than any single week's drift really was.
4. `repo-hygiene-audit` → reduce from daily to weekly. It runs daily to catch
   a newly added repo quickly, but the absences it reports change on the scale
   of months; a weekly read loses almost nothing.
5. `release-announcement-watch` → reduce from every 3h to daily.
6. `github-ops-triage` → reduce to 2×/day.
7. `weekly-analytics-report` / `social-metrics-snapshot` → these are already
   weekly, but if you pause one, pause the **analytics** report, never the
   follower snapshot: GA4 can be re-queried for a missed week, and follower
   counts cannot be recovered at all.
8. `security-advisory-sweep` → reduce to 2×/day. Last of the cloud tier
   deliberately: a late advisory is a worse outcome than a late digest.

`docs-gap-review` and `weekly-identity-integrity-check` are weekly and gated to
near-silence, so pausing them is effort without savings.

**Never pause, at any ceiling — cheap and irreplaceable, even though they now
share the meter:**

- **`unanswered-watch`.** It is the north star's safety net. Its *gate* has no
  network call, no credentials, and costs nothing regardless of window state
  — only the acknowledgment wake itself is a (cheap, gated) model call. For
  this phase that wake shares the window with everything else, so it is not
  literally free, but it's one of the cheapest wakes in the set (Haiku,
  templated, only fires when something's actually unanswered) and pausing it
  removes the one thing that keeps a window exhaustion from reading to the
  community as silence. There is no budget argument for pausing it.
- **`ledger-publish`.** It never wakes a model on success, so
  pausing it saves literally nothing — while every paused day is a day of an
  unrecoverable series that will not exist after the next rebuild. This is the
  clearest "no upside" pause in the set.
- **`conversation-archive-prune`** (all agents). Also never wakes a model, and
  it is what keeps a known platform bug from filling the container's disk (see
  UPSTREAM-ISSUES.md #38). Pausing it trades nothing for an eventual crash
  loop.
- **`ready-to-merge`.** Cheap and the best value-per-token in the set: it
  produces a *list* rather than an assessment, runs
  twice a day, and only wakes when the set of approved PRs actually changes (an
  unchanged set resurfaces once a week, not every run). What it costs you is a
  few API calls; what it prevents is a contributor's already-approved work
  sitting unmerged, which is the most discouraging way for a contribution to
  end. There is no ceiling at which pausing this is the right trade.
- **Community replies.** They are the job.

## How fast each surface actually is

Cadence questions are really three different questions, because the surfaces
have different mechanics:

| Surface | Path | Speed |
|---|---|---|
| **Discord** | **Live.** The manager is wired to the channels and answers events as they arrive — no cron involved | realtime |
| Discord, when the manager is down | `unanswered-watch` on the Helper posts a holding ack | ≤10 min; detection is free, the ack itself is a cheap Haiku wake sharing the window for this phase |
| **GitHub** | No live wiring in this design, so it polls: `github-first-response` finds new unanswered items | ≤10 min + grace |
| GitHub triage (duplicates, staleness, labels) | `github-ops-triage` digest | 6h — deliberately slow |
| Everything else | its own gated schedule, posted to the channel that cares | see the table below |
| **The owner's DM** | `owner-tldr` digest, plus urgent bypass | **07:00 the owner's local time**, or ~4h for "we may be blind" while they're awake |

**The digest is the one schedule that is timezone-correct by itself.** Every
other time in this system is a UTC cron line that you adjust by hand before
stamping; `owner-tldr` runs every 2 hours and works out whether it is 07:00
where the owner is, from `OWNER_TZ`. So it follows daylight saving with no
maintenance, and an unresolvable zone is reported rather than silently becoming
UTC (`tz_resolved: false`).

The two things worth internalising: **Discord is realtime and GitHub is a
10-minute poll**, and **most reports never reach the owner at all** — they go to
the developer/security/announcement channels where the people who act on them
live. The owner's DM is for what needs the owner, which is a much shorter list.

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
unconfigured burns turns on every fire. And **"wakes model" means a different
meter depending on the agent** — a Local-ops wake spends host RAM, never the
shared Claude window.

**Manager** (`opensource/community-manager`) — 7 tasks, the only agent with a full
public voice:

| Task | Wakes model | Needs | Unconfigured |
|---|---|---|---|
| `daily-github-triage` (weekdays) | only on new/updated items | manager PAT + `COMMUNITY_REPOS` in `plugin-data/community-manager/config.env` | silent skip. **This is the manager's standalone-mode fallback** — leave it paused when the Helper is stamped, because `github-ops-triage` covers the same ground at higher cadence. Resume it if you ever run without the Helper |
| `docs-gap-review` (Tue) | only when a support topic repeats 3+ times | the manager's own `plugin-data/community-manager/question-ledger.jsonl`, built up by normal support work | safe — quiet until the ledger has data |
| `github-first-response` (**every 10m**) | only on a brand-new issue/PR nobody has replied to, past the grace window | manager PAT + `COMMUNITY_REPOS` (+ optional `FIRST_RESPONSE_GRACE_MINUTES`, default 15) | silent skip |
| `owner-tldr` (**07:00 owner-local**) | only when the digest queue is non-empty, and only at the owner's morning hour — `attention` items escalate within ~4h during their waking window; urgent bypasses the queue entirely | `jq` only — **no network, no credentials** (+ `OWNER_TZ`, `TLDR_LOCAL_HOUR`) | safe, but set `OWNER_TZ`: without it the digest runs on UTC, which for most owners is the wrong morning. This is the ONLY routine path to the owner — sub-agent reports are queued, not relayed |
| `inbox-check` (2×/day) | **every run** (ungated) | email MCP + read-only mailbox + allowlist | leave paused |
| `release-announcement-watch` (every 3h) | only on a new stable release | manager PAT + `COMMUNITY_REPOS` (+ optional `RELEASE_WATCH_REPOS` to scope announcements to a subset) in `plugin-data/community-manager/config.env` | silent skip |
| `weekly-identity-integrity-check` (Mon) | only on prompt drift (hash gate) | nothing (`ncl`+`jq`; falls back to a manual-pass wake) | safe |

**Helper** (`opensource/community-helper`) — read-only except for drafting
security patch PRs and docs PRs (branch + draft PR, never merged), never posts
publicly. Config in `plugin-data/community-helper/config.env`.
`contributor-health-review` gets its own weekly slot for the
same reason `posthog-weekly-review` was, before it was removed for never
getting working end to end (see SKILLS-ADOPTION.md if it comes back): each is
the *interpretation* half of a metric. The same unmerged-PR ratio means
opposite things depending on why it moved, and naming a delegation candidate
is a judgment about a person. Narration went local; judgment stayed cloud.

| Task | Wakes model | Needs | Unconfigured |
|---|---|---|---|
| `docs-currency-watch` (every 6h) | only on merged PRs not yet assessed | helper PAT (Contents+PRs **write**) + `PRODUCT_REPO`/`COMMUNITY_REPOS` + `DOCS_REPO` | silent skip — no `DOCS_REPO` means the project has no docs site and the task never fires |
| `contributor-health-review` (Wed) | only on a 10-point move in the unmerged ratio or the top-author share, on the first run (no baseline to diff against), on a fetch failure, or a 90-day heartbeat | helper PAT + `COMMUNITY_REPOS` | silent skip |
| `github-ops-triage` (4×/day) | only on new/updated items | helper PAT + `COMMUNITY_REPOS` | silent skip |
| `dependabot-pr-review` (every 6h) | only on a Dependabot PR not yet reviewed at its current head SHA (a rebase brings it back) | helper PAT + `COMMUNITY_REPOS` | silent skip |
| `security-advisory-sweep` (6×/day) | on new alerts — correlated to any open Dependabot PR, so it reviews that diff rather than opening a duplicate | helper PAT + Dependabot alerts (read) permission + `COMMUNITY_REPOS` (+ optional `SECURITY_WATCH_REPOS` to scope the sweep to a subset) | silent skip |
| `social-metrics-snapshot` (weekly) | **every run** (ungated) | public profile pages (**no credentials**) + sandbox allowlist entries for the platform hosts + a real page-reading capability in the container | leave paused until the platforms are configured and allowlisted — it guards the one series nothing can rebuild |
| `weekly-analytics-report` (Sun) | weekly | GA4 OAuth + `GA4_PROPERTIES` + allowlist | silent skip |
| `ledger-publish` (daily) | **never on success** — only on a publish failure | `LEDGER_REPO` + a `github.com` (git) push credential | silent skip, and all three series then live only in this container |
| `conversation-archive-prune` (daily) | **never** | nothing | safe |

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
firing at :00 means several agent containers spinning up at once. These
are offset so no two tasks share a minute, and `unanswered-watch` keeps
the round minutes because it's the task the north star depends on:

| Task | Agent | Cadence | When (UTC) | Gated |
|------|-------|---------|------------|-------|
| `conversation-archive-prune` | Manager | **daily** | 05:17 | yes |
| `daily-github-triage` | Manager | **weekdays** | 13:13, Mon–Fri | yes |
| `docs-gap-review` | Manager | **weekly** | 15:15, Tue | yes |
| `github-first-response` | Manager | **6× hourly** | :4/14/24/34/44/54 each hour | yes |
| `inbox-check` | Manager | **2× daily** | 06:55, 16:55 | no |
| `owner-tldr` | Manager | **every 2h** | every 2h at :41 | yes |
| `release-announcement-watch` | Manager | **every 3h** | every 3h at :05 | yes |
| `weekly-identity-integrity-check` | Manager | **weekly** | 15:45, Mon | yes |
| `contributor-health-review` | Helper | **weekly** | 11:26, Wed | yes |
| `contributor-nudge` | Helper | **daily** | 09:18 | yes |
| `conversation-archive-prune` | Helper | **daily** | 05:17 | yes |
| `dependabot-pr-review` | Helper | **every 6h** | every 6h at :11 | yes |
| `dev-metrics-report` | Helper | **daily** | 12:15 | yes |
| `docs-currency-watch` | Helper | **every 6h** | every 6h at :29 | yes |
| `github-ops-triage` | Helper | **every 6h** | every 6h at :35 | yes |
| `good-first-issue-health` | Helper | **weekly** | 16:16, Mon | yes |
| `ledger-publish` | Helper | **daily** | 06:38 | yes |
| `ready-to-merge` | Helper | **2× daily** | 09:47, 17:47 | yes |
| `repo-hygiene-audit` | Helper | **daily** | 10:55 | yes |
| `security-advisory-sweep` | Helper | **every 4h** | every 4h at :45 | yes |
| `social-metrics-snapshot` | Helper | **weekly** | 13:23, Sun | no |
| `unanswered-watch` | Helper | **every 10 min** | on the 10-minute mark | yes |
| `weekly-analytics-report` | Helper | **weekly** | 14:19, Sun | yes |

_23 tasks across 2 agents; 21 script-gated (ungated: inbox-check social-metrics-snapshot)_
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

Rules of thumb: put the
integrity check before your own workday, dev metrics ahead of your dev
channel's hours, inbox checks at your real start/end of day.

**The two ungated tasks are `inbox-check` (manager, 2×/day) and
`social-metrics-snapshot` (the Helper, weekly)** — those are the only two that
wake their model on every fire, and they're capped at a few fires/day for
exactly that reason. The script gate is what lets the frequent tasks exceed
that cap safely: `unanswered-watch` at 144×/day, `owner-tldr` at 12×,
`security-advisory-sweep` at 6× — all of which cost nothing on the runs where
the gate finds nothing to say.

## Local telemetry — one file per task, worth a weekly look

Every gate script mirrors its own one-line JSON output to a local file:
`plugin-data/<agent-folder>/telemetry/<task-name>.jsonl`, one line per run.
This is **not** part of `ledger-publish`'s published series — it's local,
disposable, and exists purely so you can see wake/error patterns over time
and adjust a gate's threshold, cadence, or config if something looks off.

```bash
# how often did each task actually wake the model this week, in one agent?
jq -s 'group_by(.task) | map({task: .[0].task, runs: length,
  wakes: (map(select(.wakeAgent == true)) | length)})' \
  groups/<folder>/plugin-data/community-helper/telemetry/*.jsonl

# any errors (fetch-failed, script crash) surfaced this week?
jq -s '[.[] | select(.data.status | test("fail|error"; "i"))]' \
  groups/<folder>/plugin-data/community-helper/telemetry/*.jsonl
```

It's written via a background pipe inside each script, so on a very fast
exit the last line can occasionally be dropped — an accepted trade, since
the alternative (touching every exit path in every gate) was a much larger
and riskier change for what's meant to be a casual, adjust-as-you-go log,
not a source of truth. There's no scheduled task that reads or reports on
this file; reviewing it is a manual, human habit.

## The operator's toolkit — two scripts worth knowing about

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
be done conversationally, which is friendlier but scatters the answers across
both agents' `config.env` files with no single editable record. Export gives
you that record, so **changing one value means editing one line and rebuilding
instead of redoing the interview** — and it's what to run *before* tearing an
install down for a recreate. Two limits to know: it recovers every
`config.env` key the templates actually read, preserves each agent's
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
3. **Selective grant** (if keyed): assign the new secret to **only** the
   agent whose job needs it, then update your copy of the per-agent
   footprint table (INSTALL.md §2) so the next `agent-access` audit doesn't
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
digest, never by tag, when you actually upgrade.

The system is built to make that upgrade path cheap: **cattle, not pets**.
Because almost nothing is stateful (context rebuilds from the web, config is a
conversation, the one durable file lives in the git backup), updating the
platform = recreating the install — the same runbook you used to build it.

**Noticing updates is a manual job.** There is no automated watcher for the
image digest — check
[`nanocoai/nanoclaw`'s releases](https://github.com/nanocoai/nanoclaw/releases)
and `versions.json`'s `agent-image` field by hand, periodically, and update
`platform-baseline.json` yourself when you've verified a new one.

**The refresh procedure** (~1 hour, mostly waiting on pulls):

1. **Confirm the metrics branch is current, and understand that it is the
   only thing that survives.** There is no workspace backup in this set, by
   design: a restore nobody runs is a write-only cost. What persists is what
   `ledger-publish` pushed to `LEDGER_REPO`'s `agent-metrics` branch:
   - `agent-metrics/social-metrics-history.jsonl` — the follower series.
     Unrecoverable by any other means: every platform exposes today's count
     and nothing else.
   - `agent-metrics/traffic-history-*.json` — GA4 traffic. Re-queryable
     inside the property's retention window (14 months by default), gone
     beyond it.
   - `agent-metrics/metrics-history.json` — repo metrics. Rebuildable only by
     paging every stargazer and every issue's comments; treat as gone.

   Check the branch's last commit date before you tear anything down. If
   `ledger-publish` has been failing quietly, this is the moment that costs
   you — not the moment you notice.

   **Everything else is accepted loss, deliberately.** Each agent's
   `plugin-data/` dies with its container:
   - `project-config.md` per agent — re-created by the welcome interview, or
     instantly from `onboarding-answers.json` (see step 6).
   - Dedup ledgers (`nudge-sent-*.txt`, `known-contributors-*.txt`,
     `acknowledged.txt`, `docs-proposals-sent.txt`, `seen-advisories.txt`) —
     losing these is noise, not data loss: the system re-nudges someone it
     already nudged and re-acknowledges a message it already acknowledged,
     once.
   - `question-ledger.jsonl` (the manager) — `docs-gap-review`'s only input. It
     rebuilds from live traffic over weeks, so a rebuild resets that clock.
   - `owner-instructions.jsonl` and `public-actions.log` (the manager) — the ack
     and public-action records. These are deliberately never published: they
     contain community members' words and the owner's private direction, which
     don't belong in a repo branch. They only need to outlive a session, not a
     repave.

   If you decide you *do* want one of those preserved, copy it out by hand
   before the recreate — but decide that deliberately rather than assuming a
   backup exists.
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
   provider for a sub-agent — see [SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md)
   — re-apply and re-verify that too; it isn't part of this phase's default.)
5. Re-enter the 2 GitHub PATs in the fresh vault, selective mode (~5 min) —
   one per agent — plus the `github.com` (git) secret the Helper pushes the
   metrics branch with. No rotation needed — refresh isn't compromise.
6. **Don't restore plugin-data — re-interview instead.** Hand the manager your
   filled `onboarding-answers.json` and it re-creates each agent's config; if
   the live install predates that file, run
   `bash scripts/export-answers.sh` to reconstruct one *before* you tear the
   install down. The history series need no restore step at all: they live in
   the ledger repo, and the next `ledger-publish` run appends to what is
   already there rather than starting over — as long as `LEDGER_REPO` points
   at the same repo and branch it did before.
7. Smoke tests per INSTALL.md §4, and re-test anything in UPSTREAM-ISSUES.md
   against the new build before closing the watch issue.

**Template updates** flow the other way: edit this repo, restamp. Personas and
skills are read-only inside stamped agents by design, so a restamp *is* the
deployment mechanism — and the watch issue is a natural moment to fold in any
accumulated template improvements. Whether NanoClaw supports an in-place
upgrade instead of recreate is undocumented — tracked as an upstream docs ask
in UPSTREAM-ISSUES.md.
