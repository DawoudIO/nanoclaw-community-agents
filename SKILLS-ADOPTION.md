# Off-the-shelf skills — vetted adoption list

Result of a five-source survey (2026-08-20): skills.sh (Vercel's registry —
"npm for agent skills", plain SKILL.md folders, format-compatible with
NanoClaw), anthropics/skills, anthropics/knowledge-work-plugins,
obra/superpowers, nanocoai/nanoclaw-templates, and a broad GitHub sweep.
Licenses were verified via the GitHub API on the survey date — re-verify
before vendoring.

**Rules for adopting anything below:**
1. Read the full skill before vendoring — third-party skills are
   instruction-bearing files; treat like any dependency (skill injection is a
   known ecosystem risk; skills.sh has no submission gating).
2. Vendor by copy at a pinned commit into this repo; never live-fetch at
   stamp time. Keep the source folder's LICENSE file alongside.
3. NOASSERTION / no license = do not redistribute — use as a reference for
   writing our own, or install privately on the deployment only.

## Standing rule, not just how this list was picked

This isn't a one-time filter — it's the default for **any future addition**
to this template set. This is open-source infrastructure; most projects it
runs for have no budget. Any new skill, tool, or MCP server proposed later
(by a contributor, an owner, or an agent's own suggestion per its persona's
"default to free" rule) gets the same bar before it's added: no required API
key, no paid tier, unless the owner explicitly opts in with the cost stated
up front (the X posting path is the template for how to do that honestly).

## Selection principle: free, and no API keys (applied to the list below)

Every "Adopt" row below is a pure-knowledge skill — markdown instructions with
no service dependency, no API key, no paid tier. Three partial exceptions,
flagged so they're chosen knowingly: trailofbits `github-triage` drives the
`gh` CLI (uses the bot's existing GitHub token — no NEW key); google's GA4
skill teaches an API the analytics pillar only uses if the owner opts in; and
trailofbits `semgrep`/`codeql` invoke local scanners (free tools, no keys).
Nothing here requires a paid subscription.

## Adopt (clean license, on-target)

| Pillar | Skill(s) | Source | License | Notes |
|---|---|---|---|---|
| Community | `github-triage` | trailofbits/skills (`plugins/github-triage/`) | CC-BY-SA-4.0 | Evidence-gated issue/PR triage; writes gated behind approval. Share-alike: keep its license file. **Adaptation required for NanoClaw**: it drives the `gh` CLI, which won't authenticate inside containers (the proxy injects, no local token) — port its `gh` calls to `curl` before vendoring; usable as-is only in Claude Code sessions |
| Community | `ticket-triage`, `customer-escalation` | anthropics/knowledge-work-plugins | Apache-2.0 | Generic support triage/escalation; official |
| Marketing | `copywriting`, `social-content`, `content-strategy`, `seo-audit`, `launch-strategy`, `community-marketing` | coreyhaines31/marketingskills | MIT | Category leader (48 skills, 45K★); pure-knowledge, harness-agnostic. `community-marketing` = growth strategy, not support |
| Marketing | `brand-voice-enforcement`, `draft-content` | anthropics/knowledge-work-plugins | Apache-2.0 | Pairs with the drafts-via-PR flow |
| Marketing/dev | `changelog-automation`, `postmortem-writing` | wshobson/agents | MIT | Conventional-commit changelogs; postmortems |
| Analytics | `google-analytics-data-api-basics` | google/skills | Apache-2.0 | Official Google GA4 Data API skill — complements our scripted weekly gate |
| Security | `security-review` | getsentry/skills | Apache-2.0 | Exploitable-vuln diff review (14K installs) — fills our secure-code-review gap |
| Security | `semgrep`, `sharp-edges` (+`codeql`, `sarif-parsing`) | trailofbits/skills | CC-BY-SA-4.0 | Static-analysis + footgun review tooling |
| Security | `ghsa` | gogs/gogs (`.agents/skills/ghsa/`) | MIT | Complete advisory-handling workflow in ~30 lines — parameterize the hardcoded repo |
| Cross-cutting | `verification-before-completion`, `systematic-debugging`, `receiving-code-review` | obra/superpowers | MIT | Evidence-before-assertions; root-cause-first; verify-external-feedback |
| Triage engine | `evaluate-pitches`, `monitor-beat` (references) | nanocoai/nanoclaw-templates (journalist) | MIT | Ledger + incremental batches + learn-from-overrules → issue triage; beat-monitoring → advisory digests |
| Analytics | `pipeline-check`, `report-spec` | nanocoai/nanoclaw-templates (analyst) | MIT | "Exit-code-zero isn't healthy" telemetry checks; metric definitions |

## Install on deployment only (license blocks redistribution)

| Skill | Source | Why |
|---|---|---|
| `clawsec-nanoclaw`, `clawsec-feed` | prompt-security/clawsec | **Built for NanoClaw** — checks skills against a security-advisory feed, monitors installed skills. AGPL-3.0: install per-deployment, don't vendor into templates |

## Reference only (no license — rewrite, don't copy)

| Skill | Source | Worth stealing |
|---|---|---|
| `github-issue-response` | amd/gaia (MIT — but project-specific) | Reply-length caps per response type; security-escalation protocol (never discuss exploit detail publicly) |
| `tone-writing-style` (posthog-voice), `x-article` | PostHog/posthog.com (NOASSERTION) | The best brand-voice skill template found: anti-slop rules, per-surface voice guidance — swap PostHog's principles for the project's |
| `security-audit` | PostHog/posthog (NOASSERTION) | "Surface real exploitable bugs, suppress theoretical findings" calibration; findings require data-flow + exploit + fix + confidence |
| `diagnosing-dependabot-alerts` | medusajs/medusa (NOASSERTION) | Reachability-before-remediation doctrine |
| `discord`, `openclaw-ghsa-maintainer` | openclaw/openclaw (NOASSERTION) | Discord ID/thread discipline; GHSA publish gating |
| `internal-comms` router pattern | anthropics/skills (per-folder licenses!) | Dispatcher SKILL.md → per-format example files — the right architecture for content drafting |

## NanoClaw official catalog — full review (2026-08-21, all 52 skills)

Reviewed against our two axes: documented blind spots (observability, the
foreground-session fragility, search) and manageability. Channel skills
(Slack/Telegram/Matrix/etc.) and provider alternatives (Codex/OpenCode) were
skipped as out of scope — Discord + GitHub + Claude is the design.

### Adopt

| Skill | Blind spot it closes | Cost | How it fits |
|---|---|---|---|
| `debug` | Day-2 troubleshooting — logs, env, mounts, common container problems | **~zero.** No install step, no persistent process, no source change, no footprint. Purely on-demand (`/debug` inside a session) — costs only the conversation tokens you'd spend diagnosing anyway. Nothing to weigh; just use it | Built-in; use from the break-glass Claude session. First tool to reach for in the break-glass doctrine |
| `clidash` (not `dashboard` — see below) | **Observability** — our biggest documented gap: the owner had no way to see session/group/channel state or logs without CLI archaeology | **Near-zero.** Zero-dependency, copies one directory (`tools/clidash`), no NanoClaw source touched, no persistent secret, Node built-ins only. A local server, but the read-only/no-injection design keeps footprint minimal | Covers groups/sessions/channels/users, message-activity charts, allowlisted log tails — refresh-driven, not live-push, but that's the only real gap vs. full `dashboard` |

**`dashboard` demoted to gated-upgrade, not default-adopt — the cost is real and asymmetric to what it buys.** Digging into it: it's an always-on Node process (RAM/CPU 24/7, not on-demand), it wires a pusher module directly into NanoClaw's `src/index.ts` (a genuine source customization needing replay on every recreate, not a config toggle), it requires a restart plus a published port to reach remotely, and `DASHBOARD_SECRET` is a plain bearer token living in env config — not OneCLI-brokered (it's inbound human-UI auth, not an outbound agent credential, so it doesn't violate the agents-never-hold-keys rule, but it's still a secret needing its own careful handling if adopted). The one thing it costs nothing on: no LLM tokens, ever — pure local polling. Its actual marginal value over `clidash` is exactly two things: live push (vs. refresh) and token-usage/context-window numbers. **Install it only when that specific number — "which task or agent is burning budget" — becomes a real question**, e.g. approaching plan limits; don't install it by default alongside `clidash`.

### Optional — adopt when the trigger fires

| Skill | Trigger | Notes |
|---|---|---|
| `tavily` | **Half-fired already.** The trigger used to read "the coding agent moves to Ollama, losing Claude's built-in search" — coding never moved, but the **local** agent is on Ollama today and therefore has no built-in search, so for that group the condition is met. Remaining unfired trigger: the lead needs structured page extraction | **Keyless** — fits default-to-free exactly; per-group scoping fits least-privilege. **Not adopted for local, and it may never need to be**: local tasks don't search, they narrate what a gate already fetched. The one local task that reads pages itself, `social-metrics-snapshot`, opens *known* profile URLs via `agent-browser` — it needs no search index to find them. Adopt per-group only if a local task ever has to *find* a page rather than open a named one. Claude-provider groups already have built-in search, so don't add it speculatively there either |
| `ollama` (tools, distinct from the provider) | Bilingual reply volume gets expensive | Offloads translation/summarization to a local model as a tool while the agent stays on Claude — a scalpel where `ollama-provider` is a hammer |
| `rtk` | Only if interactive lead sessions show heavy bash-output token burn | 60–90% savings on dev-command output via a PreToolUse hook — but our gates already strip the bulk of command output before any model sees it, so expect modest gains here. Per-group, Claude-only |
| `macos-statusbar` | Host is a Mac running NanoClaw as a host service | Green/red menu-bar dot + start/stop/restart + launch-on-login — directly softens "the session IS the system." **But it manages a launchd NanoClaw, not an `sbx` VM** — for our sandbox deployment it needs adaptation (point it at the sbx lifecycle) before it applies; until then, tmux + the weekly heartbeat is the answer |
| `learn` | Ongoing | Formalizes what the lead persona's "Grow your toolkit" section already does by hand — distill `plugin-data/*/learned/` notes into proper skills at restamp time |

### Not applicable to a sandbox-kit deployment

`update` (transactional source upgrade with staging worktree — superb for
source installs; our digest-pinned recreate supersedes it), `migrate-nanoclaw`
(same — though its *idea*, replayable customization guides, is exactly how to
treat the dashboard pusher above), `migrate-from-v1`/`migrate-from-openclaw`
(we deliberately have no migration path), `setup`/`first-agent`/`welcome`/
`manage-channels`/`manage-mounts`/`self-customize`/`customize` (built-ins the
install runbook already drives), `agent-browser`/`onecli`/`onecli-gateway`
(built-ins we already depend on — the follower snapshot's page reads ride on
agent-browser; verify it's enabled in the ready gate if snapshot fetches 502
with the hosts correctly allowlisted).

## Decided: marketing stays on Claude — and a standing rule on model provenance

Asked whether a content-writing fine-tune (`sachin2505/cw`) or something like
it should run the marketing agent. **No**, for reasons worth keeping:

**On that model specifically.** Base is **Llama 2** — two generations behind
the `llama3.2` we picked for local ops, and weakest exactly where drafting
needs strength (following a brief). **176 downloads, single anonymous
publisher, no evals.** And it bakes in **Tanglish (Tamil-English blending)** —
a feature for a different audience, and an active liability for a project
writing plain English to church administrative staff.

**On the category.** Ollama's own search for "copywriting" returns **no
models**. There is no established specialised-writing category to pick from;
the field's actual recommendation for writing is a good *general*
instruction-following model at size (Qwen3 14B, Phi-4 14B, Llama 3.1 8B),
because drafting to a brief IS instruction-following. Small specialised
fine-tunes lose to general models at this.

**On the economics, which settle it.** After the model-tier split, marketing
holds exactly ONE task: `content-draft-cycle`. It's event-triggered — a new
release, or a 7-day evergreen floor — so roughly **4–6 wakes a month**.
Localising it saves almost nothing, while spending that saving on the one
output humans read as the project's own voice. Marketing's *mechanical* work
(follower snapshot, GA4 narration, stale-draft cleanup) already moved to the
local agent, which was the correct half to move. What's left is precisely the
half that shouldn't.

A bigger local model could plausibly draft acceptably, and if you ever want
zero cloud dependency that's the shape it would take — one larger model
serving both local ops and drafting, rather than `llama3.2` plus a second
model. On the actual host (a Mac mini) that runs into unified memory: the
model competes with Docker and the sandbox for one pool, so a 12b draft-
capable model is a 24 GB-and-up proposition. Spending that to save 4–6 cloud
wakes a month is the wrong trade today. See
[INSTALL.md → On a Mac mini specifically](docs/INSTALL.md).

### Standing rule: provenance before the public voice

Any model that writes text published under the project's name needs
provenance — a recognised publisher, a real download count, and a base model
you can name. A community upload with three digits of downloads and no evals
does not clear that bar, however well its description reads. This is the same
principle as the existing brand-assets rule ("never a generated, placeholder,
or 'close enough' logo") applied to prose instead of images: the project's
voice is a brand asset. Mechanical narration behind a human reviewer is a
different risk class and a general local model is fine there.

## Shipped: the Ollama "acknowledger" for when the lead is rate-limited

**This one is built, not proposed.** It lives at
`local/community-local/ai.nanoco.nanoclaw/tasks/unanswered-watch.md`, runs every
10 minutes, and holds no network access and no credentials of any kind. It was
a **different and much better** use of Ollama than the coding-agent idea below,
and it targets a real failure this deployment has already lived through: **when
the lead exhausts its window it stops answering Discord entirely, and the
community gets silence.** For a public-facing support agent that is the worst
possible failure — worse than a slow reply, because silence reads as
abandonment.

### Why this case is strong where the coding case is weak

| | Coding on Ollama | Acknowledger on Ollama |
|---|---|---|
| What it replaces | Good judgment → worse judgment, on tasks that need judgment | **Silence → a holding reply.** Strictly better than the alternative |
| Capability required | High (advisory reachability, duplicate detection, 1,130-word rule following) | **Almost none** — "seen it, logged it, a maintainer will follow up" |
| Model needed | `qwen3-coder:30b`, 18 GB — triples the resource budget | The acknowledge role alone would fit in ~1 GB. **As shipped it runs on `llama3.2` (~2 GB)** — not because acknowledging needs that, but because the same `local` agent also runs the ten other local tasks, and one model serves all of them |
| Failure mode if the model is bad | Confidently wrong security assessment | A slightly awkward acknowledgment |

It also matches the responsiveness research this template set already cites:
first-response delay is the strongest predictor of whether a newcomer comes
back, and CHAOSS's own guidance is that *any* response beats none — "even if
the response is to thank them and give them an idea of when to expect
feedback."

### The design as built

**Acknowledge, never answer.** The agent's entire permitted output is a
holding reply from a narrow template: it confirms receipt, says a maintainer
will follow up, and stops. It makes **no substantive claim** about the
project, ever — no how-to answers, no bug assessments, no version facts. That
constraint is what makes a small model safe here: there is almost nothing to
get wrong.

- **Trigger**: a support-tier message the lead hasn't replied to within
  `ACK_GRACE_MINUTES` (owner-configured, default 20). The gate runs every 10
  minutes but the grace window means it is never instant — the lead answers
  normally whenever it can and the acknowledger stays silent.
- **Deliberately blind to *why*.** The gate makes no API call to check the
  lead's health. "A human's message went unanswered" is the signal that
  matters, and it is equally true whether the cause is a rate limit, a crashed
  session or a wiring fault.
- **No network, no credentials.** It reads local message state only — which is
  exactly why it survives the outage it exists to cover.
- **Escalation**: anything security- or abuse-shaped gets the same neutral
  line with none of its detail repeated, then goes to the lead flagged
  owner-DM-urgent. It never triages.
- **Handoff**: every acknowledged id is appended to
  `plugin-data/community-local/acknowledged.txt` and reported to the lead, so
  the lead picks the message up when its window returns. The acknowledgment is
  a receipt, not a resolution — an acknowledged message nobody ever answers is
  a worse outcome than the silence it replaced.

### On single voice — as built, stated precisely

Readers see one bot (both agents post through the same Discord bot token), so
the *reader-facing* identity holds. But the old blanket claim that sub-agents
"have no channel wiring at all and cannot post publicly even if instructed to"
is **no longer true as written**, and shouldn't be repeated. The accurate
version: the **Reviewer and marketing** have no channel wiring and cannot post
publicly under any instruction. The **local agent is the one deliberate
exception** — it needs a channel to deliver holding acknowledgments, so its
restriction is enforced by *scope* instead of by absence: one channel,
read-only credentials everywhere else, no write access, and a template-only
reply it is forbidden to compose freely. That is a second surface an injected
instruction could aim at, and the template-only rule is a hard persona rule
rather than a preference precisely because of it.

### Install-verification items — three things a live install has to settle

These were open questions in the proposal; the code shipped without waiting for
them, so they are now **checks to run at install**, not design debates:

1. **Two groups, one channel.** Confirm the lead and the local agent can both
   wire to the same Discord channel, and that a per-group provider override
   coexists with that. Still unverified. If it turns out they can't, the
   acknowledger has no delivery path and this whole safety net is inert — check
   this first.
2. **`ncl messages list --json` output shape.** The gate depends on it and the
   shape varies by NanoClaw version. It already fails *closed* rather than
   quiet — an unexpected shape reports `cannot-read-messages` instead of
   "nothing to do" — so the check is that the status you see is `all-answered`
   and not `cannot-read-messages` sitting there unnoticed.
3. **Double-post avoidance if the lead recovers mid-flight.** The shipped
   mitigation is two-layered: `acknowledged.txt` stops the gate re-firing on
   the same id, and the task instructs the agent to read the channel first and
   post nothing if the lead already replied. Verify the second layer actually
   holds in practice — a duplicate under the same bot name reads as broken.

**Still open in principle, and not blocking:** whether an LLM is the right tool
at all. The acknowledge-only role needs so little intelligence that a
non-model responder would be more robust. Within NanoClaw's agent-per-group
model an Ollama agent is the available way to get a non-consuming responder; if
the platform ever exposes a plain scripted auto-reply, that beats this.

Finally, note what this does *not* fix: the underlying cause. **Pausing tasks
and separating meters is still what keeps the lead alive**; this is the safety
net for when that fails, not a substitute for it.

## Decided: NO Ollama for the coding agent — Haiku stays

Asked to compare Ollama against the coding agent's actual Haiku-class
workload rather than against Sonnet. The comparison kills the idea, and it's
worth writing down so it isn't re-proposed on vibes.

**1. The volume it would save is already tiny.** The gates did that work, and
the model-tier split then took most of the volume away as well: the Reviewer
owns **two** tasks, not seven. Realistic wakes per week:

| Task | Cron | Wakes only when | Est. wakes/wk |
|---|---|---|---|
| `github-ops-triage` | 4×/day | new or updated issues/PRs | ~10–20 |
| `security-advisory-sweep` | 6×/day | a NEW advisory | ~0–1 |

That is ~10–21 wakes/week at ~6.2K context each, with a byte-identical persona
prefix that caches. On the cheapest model tier it isn't close to noise — it
*is* noise. The five tasks that used to pad this table
(`dev-metrics-report`, `repo-mirror-sync`, `good-first-issue-health`,
`posthog-weekly-review`, `repo-hygiene-audit`) belong to the local agent now,
and the two that went to the lead (`daily-github-triage`, `docs-gap-review`)
are Sonnet-tier by design. Neither set is coding's to save, so neither belongs
in a table about coding's spend.

**2. The risk was concentrated in exactly the wrong tasks — and that split is
precisely what shipped.** The old seven divided cleanly into mechanical
narration and real judgment, and the argument here was that a small local model
fails on the judgment half. **That division is now the org chart**: the
mechanical-narration half *became* the `local` agent on `llama3.2`, and what
remained on Haiku is the judgment half, undiluted. This makes the conclusion
stronger rather than weaker. The old case for keeping coding on Claude was an
average over a mixed workload; now every task left in this agent is one of the
individual reasons.

- `security-advisory-sweep` asks it to "assess whether the project is
  genuinely affected (a vulnerable dependency that isn't reachable in this
  codebase is worth a different note than an exploitable one)." That is
  security reachability reasoning. A confidently-wrong local answer here is
  worse than no answer — and the local persona's never-do list forbids it
  outright, which is the same judgment written from the other side.
- `github-ops-triage` is the higher-volume of the two AND needs duplicate
  detection plus spotting security-shaped reports.

One judgment-shaped item did travel with the mechanical half:
`repo-mirror-sync`'s "does this wiki edit contradict current code, does this
docs change need a currency check" cross-referencing. It runs on `llama3.2`
today. That is a **documented, accepted risk on the local tier**, not an
oversight — the mitigation is that its output is a change summary the lead
reads, and the local persona forbids it from judging scope, duplicates, or
security. It belongs on the week-1 watch list below, not in coding's column.

**3. Instruction-following at length is the local tier's primary known risk —
accepted, not avoided.** The sharpest form of this argument used to be
`dev-metrics-report`: its prompt is ~1,130 words of conditional rules
(degraded repos first, ready-to-merge leads, `null` ≠ zero, ratio sample floor,
sampled flag, name the contributors); instruction-following is the first thing
to degrade on small models; and a silently-dropped rule is nearly undetectable,
because the lead reviews the content, not whether a rule was skipped.

**That task is now a local `llama3.2` task.** The argument did not stop being
true — it changed owner, and keeping it honest means recording it as the local
agent's headline risk rather than deleting it. Two mitigations shipped with it:

- **The gate computes every number.**
  `scripts/tasks/local/dev-metrics-report.sh` does the fetching, the deltas and
  the `null`-on-failure handling before any model wakes, so the model narrates
  a computed result instead of deriving one. A dropped rule can make the prose
  worse; it cannot make the numbers wrong.
- **The local persona's explicit never-do list**
  (`local/community-local/ai.nanoco.nanoclaw/context/instructions.md`) hard-codes
  the rules least safe to drop: never invent a number, `null` means
  "unavailable" and never zero, never assess security, never write anything
  readable as the project's voice.

Residual risk stands, and it is a **week-1 verification item, not a solved
problem**: read the first few `dev-metrics-report` outputs against the gate's
raw JSON and confirm the conditional rules actually survived. If they didn't,
that's the trigger for a larger local model — not a reason to move the task
back onto a metered tier.

**4. It can cost MORE window than it saves.** Coding is Haiku; the lead that
reviews every coding output is Sonnet-class. Making coding worse shifts work
onto the more expensive tier, plus your own review attention. That inverts
the entire point.

**5. Real costs on the other side of the ledger:** Ollama infra and host RAM
for a capable model, cold-start latency, replay-on-recreate, and the
"local models sometimes claim to be Claude" wrinkle interacting badly with
our mechanical identity checks.

**6. And the model options make it concrete — for *this* agent, the only one
good enough blows the resource budget.** Read the table below strictly as what
it is: **a fit assessment for a hypothetical coding-agent migration.** It is
not a general ranking of these models, and it is emphatically not the local
agent's model decision — see the note underneath.

| Model | Size | Fit **for a coding-agent migration** (not a general verdict) |
|---|---|---|
| `gemma3:1b` | 1 GB | No. Would drop rules from a 1,130-word conditional prompt and cannot be trusted on advisory reachability |
| `llama3.2` | 2 GB | Marginal **for this workload**. Closest in *kind* to it (reading comprehension, not codegen), but too small for the judgment the Reviewer's two remaining tasks are made of |
| `qwen3-coder:30b` | **18 GB** | Capable enough — and it alone roughly *triples* our documented footprint (INSTALL §0 budgets 10–15 GB free disk for the entire sandbox stack, plus "a few GB of RAM headroom"). A 30B model wants ~20 GB RAM on top of the VM, nested images, and the agent containers |

**`llama3.2` is nonetheless the shipped model for the `local` agent, and that
is not a contradiction with its "marginal" row above.** "Too small for the
judgment tasks" is a verdict about a *workload*, not about the model. The local
agent was defined so that it does no judgment work at all: its gates compute
every number, its persona's never-do list forbids assessing anything, and its
single public utterance is a fixed template. A model that is marginal for the
Reviewer's two judgment tasks is correctly sized for narration with the
judgment removed. That is the same reasoning as "Decided: marketing stays on
Claude" applied one tier down — see also
[INSTALL.md → On a Mac mini specifically](docs/INSTALL.md) for the unified-memory
side of the choice.

There's also a category mismatch worth naming: **the coding agent barely
writes code.** It reads GitHub metadata and narrates it — triage digests and
advisory assessments. Those are reading comprehension, instruction-following
and judgment tasks. A code-specialised model is not obviously the right tool
for them, so "strong at code tasks" doesn't transfer to this workload the way
it looks like it should.

**What would change this verdict:** a genuinely high-volume, purely
mechanical workload — mass translation, large-scale log summarization, bulk
classification. That is exactly where a 1–2 GB model earns its keep, and it is
worth being precise about who has it: **not the Reviewer.** The mechanical
narration in this template set was separated out into the `local` agent, which
already runs on exactly such a model; what stayed on Haiku is the residue that
isn't mechanical. **Measure at install** (clidash), and revisit only if the
Reviewer's two tasks turn out to consume meaningfully. The prediction is that
they won't — the gates already solved most of the problem Ollama would be
solving, and the tier split solved the rest.

## Proposed, NOT yet decided — needs an owner call

> **Read this section as being about the agents Ollama has *not* been applied
> to.** `ollama-provider` itself is no longer hypothetical: it is how the
> `local` agent runs, and the acknowledger section above is its as-built
> record. What remains undecided is whether it (or the `ollama` tool) should
> also be applied to the coding, lead or marketing groups — and for coding the
> section above already says no.

**`ollama-provider` and `ollama` are alternatives, not a pair — you never
need both for the same agent.** `ollama-provider` *replaces* the model that
runs an agent group (that group leaves the shared window entirely).
`ollama` adds Ollama as a *tool the agent calls* (the agent stays on Claude
and still consumes window, but can hand discrete subtasks — summarization,
translation — to a local model). Which one applies depends on the agent:

| Agent | Right choice | Why |
|---|---|---|
| Local | `ollama-provider` — **done, this is how it runs** | The group was created *for* the local model. Off-window entirely; the tool version would be pointless here, since it'd already *be* a local model |
| Coding | **Neither** — Haiku stays | Superseded by "Decided: NO Ollama for the coding agent" above. The formulaic half of its old workload is what became the local group; what's left is the judgment half, which is the part you don't downgrade |
| Lead | `ollama` tool **only** — never the provider | Public-voice judgment is exactly what you don't downgrade. But offloading bulk translation for the bilingual reply rule is a legitimate scalpel |
| Marketing | Neither, by default | Draft quality is the deliverable |

Both rebuild the container image, so **both are replay-on-recreate**
customizations (see [INSTALL.md → Platform skills](docs/INSTALL.md)).

| Skill | What it would buy | Why it's not adopted yet |
|---|---|---|
| `ollama-provider` (nanoclaw.dev/skills/ollama-provider) | Routes ONE agent group to a local Ollama model — zero shared-window consumption for that group | **Adopted for `local`; still not approved for any other group.** The three items that were open when this was only a proposal are now install prerequisites and verification steps rather than reasons to wait — see PREREQS §1 for (a) and the Mac mini note for the RAM side. The skill does its own setup (`/add-ollama-provider` extends `ContainerConfig` with `env`/`blockedHosts`, writes the per-group `container.json`, and sets `blockedHosts: api.anthropic.com` on that group as a spend guard), so the install work is not the obstacle. What's actually open: (a) **you must supply Ollama yourself** — running on `:11434` with a model already pulled, on a host that can run it; (b) **unverified whether `host.docker.internal:11434` reaches the host from inside the sandbox VM's *inner* Docker daemon** — that's two network boundaries and the skill assumes one, so it needs a real test; (c) it **modifies the Dockerfile (chmod 777 for non-root host UIDs) and NanoClaw's source**, making it a replay-on-recreate customization like the clidash pusher, which our digest-pinning policy tolerates but should record deliberately. Counter-argument, which is why this stops at `local`: on a shared subscription the lead still reviews every sub-agent output, and that review costs window capacity — so the net saving is real but smaller than "zero tokens for one agent" implies. That argument is survivable for narration the lead skims; it is not survivable for judgment the lead would have to redo |
| `ollama` (the TOOL, not the provider) | Lets an agent that stays on Claude delegate discrete subtasks to a local model — the realistic use here is bulk translation for the bilingual support-reply rule | **Also never approved.** Same host prerequisites as above (Ollama running, model pulled) plus the same unverified VM→host reachability, and it **rebuilds the container image** (stdio MCP server copied into the source tree, registered in the agent-runner's `mcpServers`), so it's replay-on-recreate too. Only worth it if bilingual reply volume turns out to be a real cost — which no one has measured yet. Revisit with usage data, not in advance |

## Evaluated and rejected — with reasons, so this isn't relitigated

| Skill | What it offers | Why not |
|---|---|---|
| `mnemon` (nanoclaw.dev/skills/mnemon) | Persistent graph memory: auto-recall before responding, auto-store insights after each turn, survives restarts | **Rejected — reintroduces v1's disease.** (1) It auto-stores "insights" from every turn — including public Discord turns — so a malicious community member can plant persistent false context ("the owner approved X") that every future session recalls as trusted. Our injection defense rests on read-text-is-data; a hook persisting it as memory weaponizes the public channels. (2) An opaque, auto-written graph store is exactly the unverifiable state v1's tamper-paranoia loops fed on; v2's fix — append-only human-readable ledgers with provenance — already gives sessions shared state that can be audited. (3) Its data dir lives outside the workspace backup, creating durable-but-unbacked state against the statelessness doctrine, and it requires a Dockerfile/entrypoint rebuild against the sealed pinned image. The one real itch (owner-DM continuity) is covered by project-config + the instruction ledger |
| `native-credential-proxy` (nanoclaw.dev/skills/native-credential-proxy) | Opt out of the OneCLI gateway; supply Anthropic credentials straight from `.env` | **Hard reject — it is the literal negation of this system's credential rule** (agents never hold keys; there is no `.env` by design). If anyone proposes this skill, the answer is the README's design-principles bullet, not a discussion |
| `karpathy-llm-wiki` (nanoclaw.dev/skills/karpathy-llm-wiki) | Persistent self-maintaining wiki knowledge base per group | Soft reject — same statefulness objection as mnemon (agent-written durable knowledge accumulating outside the backup, fed partly by public inputs), though less severe since a wiki is at least human-readable. Our append-only ledgers + rebuild-from-web doctrine cover the need; revisit only if cold-start context rebuilding proves genuinely expensive in practice |
| `update-skills` (nanoclaw.dev/skills/update-skills) | Refresh channel/provider code in place from upstream branches, with clean-tree/origin/test safety checks | **Rejected for steady state — it's the in-place mutation our update policy forbids.** After it runs, the install no longer matches `platform-baseline.json`'s digest and reproducibility is gone. Our recreate path costs ~1h because the system is deliberately stateless. **Break-glass exception only**: an urgent upstream channel fix (e.g. Discord API break) that can't wait for a kit image — run it, note in the owner DM that baseline no longer describes reality, and do a proper digest-pinned recreate as soon as one exists |

## Confirmed gaps — ours to own (already written in these templates)

Nothing off-the-shelf exists for: **Discord support replies decoupled from a
harness** (ours: `discord-mechanics.md`), **analytics-review → GitHub-issue
drafting** (ours: the posthog/GA4 gated tasks; PostHog's internal "signals"
model is the pattern, not public), and **advisory feed monitoring** (ours: the
scripted sweep; clawsec covers the skill-supply-chain slice only). Our custom
work sits exactly where the ecosystem is empty — keep maintaining it.

## Vendoring pass (to do, post-migration)

1. Pin + read + copy the "Adopt" rows into the right template's `skills/`.
   Allocation follows the tasks, so the model-tier split moved several of these:
   - **lead** — triage/support (`ticket-triage`, `customer-escalation`) +
     `security-review`.
   - **local** — the analyst pair (`pipeline-check`, `report-spec`) and
     google's `google-analytics-data-api-basics`. All three follow the tasks
     that read telemetry, and those are local's now: `dev-metrics-report`,
     `posthog-weekly-review`, `weekly-analytics-report`. "Exit-code-zero isn't
     healthy" and metric definitions are exactly the guardrails a small model
     narrating numbers needs.
   - **marketing** — coreyhaines subset + `brand-voice-enforcement` /
     `draft-content`. One task, so keep this set tight.
   - **coding** — trailofbits (`semgrep`, `sharp-edges`) + `ghsa`, matching its
     two remaining tasks. The analyst pair used to be listed here; it isn't
     coding's work any more.
2. Prefer the analyst template's many-small-skills layout over one mega-skill.
3. Re-run `check-templates.mjs` (frontmatter + no-symlink rules apply to
   vendored skills too) and restamp.
4. Consider optional `mcp.json` entries: a community GA4 MCP server and
   PostHog's MCP — **both belong on `local`, not on marketing or coding**.
   `weekly-analytics-report` and `posthog-weekly-review` both run there, and
   local is the only agent holding the GA4 and PostHog credentials at all, so
   an entry on any other agent would be an MCP server with nothing to
   authenticate as. Placeholder credentials, and test whether OneCLI proxy
   injection satisfies their boot checks.
