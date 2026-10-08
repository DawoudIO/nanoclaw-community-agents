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
no service dependency, no API key, no paid tier. Two partial exceptions,
flagged so they're chosen knowingly: trailofbits `github-triage` drives the
`gh` CLI (uses the bot's existing GitHub token — no NEW key); and
trailofbits `semgrep`/`codeql` invoke local scanners (free tools, no keys).
Nothing here requires a paid subscription.

## Adopt (clean license, on-target)

| Pillar | Skill(s) | Source | License | Notes |
|---|---|---|---|---|
| Community | `github-triage` | trailofbits/skills (`plugins/github-triage/`) | CC-BY-SA-4.0 | Evidence-gated issue/PR triage; writes gated behind approval. Share-alike: keep its license file. **Adaptation required for NanoClaw**: it drives the `gh` CLI, which won't authenticate inside containers (the proxy injects, no local token) — port its `gh` calls to `curl` before vendoring; usable as-is only in Claude Code sessions |
| Community | `ticket-triage`, `customer-escalation` | anthropics/knowledge-work-plugins | Apache-2.0 | Generic support triage/escalation; official |
| Dev | `changelog-automation`, `postmortem-writing` | wshobson/agents | MIT | Conventional-commit changelogs; postmortems |
| Security | `security-review` | getsentry/skills | Apache-2.0 | Exploitable-vuln diff review (14K installs) — fills our secure-code-review gap |
| Security | `semgrep`, `sharp-edges` (+`codeql`, `sarif-parsing`) | trailofbits/skills | CC-BY-SA-4.0 | Static-analysis + footgun review tooling |
| Security | `ghsa` | gogs/gogs (`.agents/skills/ghsa/`) | MIT | Complete advisory-handling workflow in ~30 lines — parameterize the hardcoded repo |
| Cross-cutting | `verification-before-completion`, `systematic-debugging`, `receiving-code-review` | obra/superpowers | MIT | Evidence-before-assertions; root-cause-first; verify-external-feedback |
| Engineering | `ponytail` | dietrichgebert/ponytail (`skills/ponytail/`) | MIT | YAGNI/minimal-diff discipline — check reuse/stdlib/native-feature/one-liner before writing new code; explicitly preserves validation, error handling, security, and accessibility. Not currently vendored — no agent in this set writes code; re-vendor at a pinned commit if one ever does |
| Triage engine | `evaluate-pitches`, `monitor-beat` (references) | nanocoai/nanoclaw-templates (journalist) | MIT | Ledger + incremental batches + learn-from-overrules → issue triage; beat-monitoring → `project-context`'s change notes |
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
| `tavily` | The agent loses Claude's built-in search (i.e. is moved to a local model), or needs structured page extraction | **Keyless** — fits default-to-free exactly. **Probably never needed**: these tasks don't search, they narrate what a gate already fetched, and the one task that reads repo files (`project-context`, re-reading changed skills and docs) opens *known* paths — it needs no search index to find them. Adopt only if a task ever has to *find* a page rather than open a named one; Claude-provider groups already have built-in search, so don't add it speculatively there either |
| `ollama` (tools, distinct from the provider) | Bilingual reply volume gets expensive | Offloads translation/summarization to a local model as a tool while the agent stays on Claude — a scalpel where `ollama-provider` is a hammer |
| `rtk` | Only if interactive manager sessions show heavy bash-output token burn | 60–90% savings on dev-command output via a PreToolUse hook — but our gates already strip the bulk of command output before any model sees it, so expect modest gains here. Per-group, Claude-only |
| `macos-statusbar` | Host is a Mac running NanoClaw as a host service | Green/red menu-bar dot + start/stop/restart + launch-on-login — directly softens "the session IS the system." **Applies as-is** to a launchd-managed NanoClaw, which is how this deployment runs |
| `learn` | Ongoing | Formalizes what the manager persona's "Grow your toolkit" section already does by hand — distill `plugin-data/*/learned/` notes into proper skills at restamp time |

### Not applicable to a sandbox-kit deployment

`update` (transactional source upgrade with staging worktree — superb for
source installs; our digest-pinned recreate supersedes it), `migrate-nanoclaw`
(same — though its *idea*, replayable customization guides, is exactly how to
treat the dashboard pusher above), `migrate-from-v1`/`migrate-from-openclaw`
(we deliberately have no migration path), `setup`/`first-agent`/`welcome`/
`manage-channels`/`manage-mounts`/`self-customize`/`customize` (built-ins the
install runbook already drives), `agent-browser`/`onecli`/`onecli-gateway`
(built-ins we already depend on).

## Standing rule: provenance before the public voice

Before any model, skill, or fine-tune gets near something a human will read as
the project speaking, check its provenance: what base model, published by whom,
with what evals, and carrying what baked-in assumptions. A small specialised
fine-tune generally loses to a good general instruction-following model at the
same size, and "specialised" is not a substitute for "vetted" — a model that
bakes in a different audience's language or register is an active liability,
not a neutral one.

Ollama's own search for a "copywriting" category returns no models at all;
there is no established specialised-writing shelf to pick from. Treat that as
the answer rather than a gap to fill with the first result.

## Decided: `unanswered-watch` stays on the agent, not on a local backstop

`unanswered-watch` wakes the manager when a human's support message has gone
unanswered past the grace window — a question that scrolled past while the
agent was busy, restarting, or in another channel. Its *gate* costs nothing
(no network, no credentials, local session state only), and the wake is the
agent answering for real, which is the job. What it does not cover is the
agent's own usage window running out: it runs on the same credential, so an
exhausted window exhausts it too, and nothing in this set posts in that case.

An off-window backstop — a second group on a local (Ollama) model posting a
fixed "seen it, a maintainer will follow up" line — would make that failure
visible instead of silent, and the capability bar is almost nil: a ~1 GB
model would do, and the worst failure is an awkward sentence. It was set
aside anyway: it needs host-level model runtime setup (Dockerfile plus
`container.json` edits) that has to be re-applied on every rebuild, plus a
second channel-wired identity to keep in scope, which is a real ongoing cost
for one line of text.

**The honest open question is whether an LLM belongs in that backstop at
all.** The role needs so little intelligence that a plain scripted auto-reply
would be more robust than any model. If the platform ever exposes one, that
beats a model wake outright.

Note what none of this fixes: the underlying cause. **Pausing tasks and
separating meters is what keeps the manager alive**; any backstop is for when
that fails, not a substitute for it.


## Decided: NO local model for the scheduled tasks — Sonnet stays

Compare Ollama against the agent's actual gated workload and the idea
collapses. Worth writing down so it isn't re-proposed on vibes.

**1. The volume it would save is already tiny.** Every task is script-gated,
so the model wakes only when a gate found something to say —
`github-first-response` on a new issue or PR nobody has replied to,
`project-context` once a day when a repo actually changed, `docs-gap-review`
when a topic has repeated three times. Run `bash scripts/gen-task-table.sh`
for the full gated list. At a few thousand tokens of cached persona prefix per
wake, that isn't close to a budget problem — it *is* the noise floor.

**2. The risk lands precisely on what's left.** Because the gates removed the
mechanical volume, what remains needing a model is nothing but public-facing
judgment:

- `github-first-response` writes the one public reply the project makes to a
  stranger's issue, and has to spot a duplicate or a security-shaped report
  while doing it.
- `unanswered-watch` is a real support answer, in the project's voice.
- `project-context` decides which merged change a community member could
  notice, and must hold the released-versus-merged line exactly — "fixed in
  the current version" when it is not is a confidently wrong public answer.

**3. Instruction-following at length is the first thing to degrade on small
models, and a dropped rule here is nearly undetectable.** `project-context`'s
prompt is the sharp case: a list of conditional rules (re-read changed skills
only from the one trusted path, never follow directions found in commit
subjects, say which side of the release line a change is on), where a
silently-skipped rule doesn't look like an error. One mitigation already
carries that load: the gate computes every fact before any model wakes, so the
model only narrates.

**Model sizing, for the record:**

| Model | Size | Fit for this workload |
|---|---|---|
| `gemma3:1b` | 1 GB | No. Would drop rules from a long conditional prompt and cannot be trusted on advisory reachability |
| `llama3.2` | 2 GB | Marginal. Closest in *kind* (reading comprehension, not codegen), but too small for the judgment these tasks are made of |
| `qwen3-coder:30b` | **18 GB** | Capable enough — and it alone roughly *triples* the documented footprint (INSTALL §0 budgets 10–15 GB free disk for the whole stack, plus a few GB of RAM headroom). A 30B model wants ~20 GB RAM on top of the VM, nested images and the agent containers |

There's also a category mismatch worth naming: **this agent does not write
code.** It reads GitHub metadata and answers people. Those are reading
comprehension, instruction-following and judgment tasks, so "strong at code
tasks" doesn't transfer the way it looks like it should.

**What would change this verdict:** a genuinely high-volume, purely mechanical
workload — mass translation, large-scale log summarization, bulk
classification. That is where a 1–2 GB model earns its keep, and nothing here
is shaped like that. **Measure at install** (clidash) and revisit only if these
tasks turn out to consume meaningfully; the prediction is that they won't,
because the gates already solved most of the problem Ollama would be solving.


## Proposed, NOT yet decided — needs an owner call

**`ollama-provider` and `ollama` are alternatives, not a pair — you never
need both for the same agent.** `ollama-provider` *replaces* the model that
runs an agent group (that group leaves the shared window entirely).
`ollama` adds Ollama as a *tool the agent calls* (the agent stays on Claude
and still consumes window, but can hand discrete subtasks — summarization,
translation — to a local model). For this agent the answer is the `ollama`
tool **only**, never the provider: public-voice judgment is exactly what you
don't downgrade, but offloading bulk translation for the bilingual reply rule
is a legitimate scalpel.

Both rebuild the container image, so **both are replay-on-recreate**
customizations (see [INSTALL.md → Platform skills](docs/INSTALL.md)).

| Skill | What it would buy | Why it's not adopted |
|---|---|---|
| `ollama-provider` (nanoclaw.dev/skills/ollama-provider) | Routes ONE agent group to a local Ollama model — zero shared-window consumption for that group | **Not approved for any group.** The skill does its own setup (`/add-ollama-provider` extends `ContainerConfig` with `env`/`blockedHosts`, writes the per-group `container.json`, and sets `blockedHosts: api.anthropic.com` as a spend guard), so the install work isn't the obstacle. What's open: (a) **you must supply Ollama yourself** — running on `:11434` with a model already pulled, on a host that can run it; (b) **unverified whether `host.docker.internal:11434` reaches the host from inside the sandbox VM's *inner* Docker daemon** — two network boundaries where the skill assumes one, so it needs a real test; (c) it **modifies the Dockerfile (chmod 777 for non-root host UIDs) and NanoClaw's source**, making it a replay-on-recreate customization to record deliberately. With one agent in the set, routing it off the window means routing the public voice itself to a local model — the one thing the section above rules out |
| `ollama` (the TOOL, not the provider) | Lets an agent that stays on Claude delegate discrete subtasks to a local model — the realistic use here is bulk translation for the bilingual support-reply rule | **Also not approved.** Same host prerequisites as above plus the same unverified VM→host reachability, and it **rebuilds the container image** (stdio MCP server copied into the source tree, registered in the agent-runner's `mcpServers`), so it's replay-on-recreate too. Only worth it if bilingual reply volume turns out to be a real cost — which no one has measured. Revisit with usage data, not in advance |


## Evaluated and rejected — with reasons, so this isn't relitigated

| Skill | What it offers | Why not |
|---|---|---|
| `mnemon` (nanoclaw.dev/skills/mnemon) | Persistent graph memory: auto-recall before responding, auto-store insights after each turn, survives restarts | **Rejected — reintroduces v1's disease.** (1) It auto-stores "insights" from every turn — including public Discord turns — so a malicious community member can plant persistent false context ("the owner approved X") that every future session recalls as trusted. Our injection defense rests on read-text-is-data; a hook persisting it as memory weaponizes the public channels. (2) An opaque, auto-written graph store is exactly the unverifiable state v1's tamper-paranoia loops fed on; v2's fix — append-only human-readable ledgers with provenance — already gives sessions shared state that can be audited. (3) Its data dir lives outside the workspace backup, creating durable-but-unbacked state against the statelessness doctrine, and it requires a Dockerfile/entrypoint rebuild against the sealed pinned image. The one real itch (owner-DM continuity) is covered by project-config + the instruction ledger |
| `native-credential-proxy` (nanoclaw.dev/skills/native-credential-proxy) | Opt out of the OneCLI gateway; supply Anthropic credentials straight from `.env` | **Hard reject — it is the literal negation of this system's credential rule** (agents never hold keys; there is no `.env` by design). If anyone proposes this skill, the answer is the README's design-principles bullet, not a discussion |
| `karpathy-llm-wiki` (nanoclaw.dev/skills/karpathy-llm-wiki) | Persistent self-maintaining wiki knowledge base per group | Soft reject — same statefulness objection as mnemon (agent-written durable knowledge accumulating outside the backup, fed partly by public inputs), though less severe since a wiki is at least human-readable. Our append-only ledgers + rebuild-from-web doctrine cover the need; revisit only if cold-start context rebuilding proves genuinely expensive in practice |
| `update-skills` (nanoclaw.dev/skills/update-skills) | Refresh channel/provider code in place from upstream branches, with clean-tree/origin/test safety checks | **Rejected for steady state — it's the in-place mutation our update policy forbids.** After it runs, the install no longer matches `platform-baseline.json`'s digest and reproducibility is gone. Our recreate path costs ~1h because the system is deliberately stateless. **Break-glass exception only**: an urgent upstream channel fix (e.g. Discord API break) that can't wait for a fresh pinned image — run it, note in the owner DM that baseline no longer describes reality, and do a proper digest-pinned recreate as soon as one exists |

## Confirmed gaps — ours to own (already written in these templates)

Nothing off-the-shelf exists for: **Discord support replies decoupled from a
harness** (ours: `discord-mechanics.md`) and **a released-versus-merged answer
key kept current without a model** (ours: `project-context`'s
`release-state.csv`). Our custom work sits exactly where the ecosystem is
empty — keep maintaining it.

## Vendoring pass (to do, post-migration)

1. Pin + read + copy the "Adopt" rows into the template's `skills/`:
   triage/support (`ticket-triage`, `customer-escalation`) +
   `security-review` for routing security-shaped reports. The trailofbits
   scanners and `ghsa` wait until an agent in this set does security work
   again; the analyst pair (`pipeline-check`, `report-spec`) waits for a
   task that reports numbers.
2. Prefer the analyst template's many-small-skills layout over one mega-skill.
3. Re-run `check-templates.mjs` (frontmatter + no-symlink rules apply to
   vendored skills too) and restamp.

