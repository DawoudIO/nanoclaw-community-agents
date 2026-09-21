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
| Dev | `changelog-automation`, `postmortem-writing` | wshobson/agents | MIT | Conventional-commit changelogs; postmortems |
| Analytics | `google-analytics-data-api-basics` | google/skills | Apache-2.0 | Official Google GA4 Data API skill — complements our scripted weekly gate |
| Security | `security-review` | getsentry/skills | Apache-2.0 | Exploitable-vuln diff review (14K installs) — fills our secure-code-review gap |
| Security | `semgrep`, `sharp-edges` (+`codeql`, `sarif-parsing`) | trailofbits/skills | CC-BY-SA-4.0 | Static-analysis + footgun review tooling |
| Security | `ghsa` | gogs/gogs (`.agents/skills/ghsa/`) | MIT | Complete advisory-handling workflow in ~30 lines — parameterize the hardcoded repo |
| Cross-cutting | `verification-before-completion`, `systematic-debugging`, `receiving-code-review` | obra/superpowers | MIT | Evidence-before-assertions; root-cause-first; verify-external-feedback |
| Engineering | `ponytail` | dietrichgebert/ponytail (`skills/ponytail/`) | MIT | YAGNI/minimal-diff discipline — check reuse/stdlib/native-feature/one-liner before writing new code; explicitly preserves validation, error handling, security, and accessibility. Vendored unmodified at commit `2ed6c52`, owned by `community-helper` only (it is the only agent that writes code at all) |
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
| `tavily` | An agent loses Claude's built-in search (i.e. is moved to a local model), or the manager needs structured page extraction | **Keyless** — fits default-to-free exactly; per-group scoping fits least-privilege. **Probably never needed**: these tasks don't search, they narrate what a gate already fetched, and the one task that reads pages itself (`project-health`, on collect days) opens *known* profile URLs — it needs no search index to find them. Adopt per-group only if a task ever has to *find* a page rather than open a named one; Claude-provider groups already have built-in search, so don't add it speculatively there either |
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
(built-ins we already depend on — the follower snapshot's page reads ride on
agent-browser; verify it's enabled in the ready gate if snapshot fetches 502
with the hosts correctly allowlisted).

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

## Decided: the acknowledger stays on the shared model, not a local one

`unanswered-watch` (on the Helper) posts a holding reply when a human's
message has gone unanswered past the grace window — normally because the manager
exhausted its usage window and went silent, which for a public-facing support
agent is the worst failure there is. Its *gate* costs nothing (no network, no
credentials, local session state only), so detection survives a window
exhaustion; the acknowledgment itself is a cheap model wake on the same shared
window, so a fully exhausted window silences both.

Routing that one task to a local (Ollama) model would make the acknowledgment
genuinely non-consuming, and the capability bar is almost nil — "seen it,
logged it, a maintainer will follow up" would fit in a ~1 GB model, and the
worst failure is a slightly awkward sentence rather than a confidently wrong
judgment. It was set aside anyway: it needs host-level model runtime setup
(Dockerfile plus `container.json` edits) that has to be re-applied on every
rebuild, which is a real ongoing cost for one task.

**The honest open question is whether an LLM belongs here at all.** The role
needs so little intelligence that a plain scripted auto-reply would be more
robust than any model. Within NanoClaw's agent-per-group model, a model wake is
the available way to get a responder; if the platform ever exposes a scripted
auto-reply, that beats this outright.

Note what none of this fixes: the underlying cause. **Pausing tasks and
separating meters is what keeps the manager alive**; this is the safety net for
when that fails, not a substitute for it.


## Decided: NO Ollama for the Helper — Haiku stays

Compare Ollama against the Helper's actual Haiku-class workload rather than
against Sonnet and the idea collapses. Worth writing down so it isn't
re-proposed on vibes.

**1. The volume it would save is already tiny.** Nearly every task is
script-gated, so the model wakes only when a gate found something to say —
`github-ops-triage` on new or updated issues/PRs (~10–20/week),
`security-advisory-sweep` only on a genuinely new advisory (~0–1),
`project-health` for a small daily follower-count read plus one weekly post
(~1 real composition). Run `bash scripts/gen-task-table.sh` for the full gated list.
At a few thousand tokens of cached persona prefix per wake, on the cheapest
tier, that isn't close to a budget problem — it *is* the noise floor.

**2. The risk lands precisely on what's left.** Because the gates removed the
mechanical volume, what remains needing a model is disproportionately
judgment:

- `security-advisory-sweep` asks whether the project is *genuinely affected* —
  a vulnerable dependency that isn't reachable in this codebase deserves a
  different note than an exploitable one. That is security reachability
  reasoning, and a confidently-wrong local answer is worse than no answer.
- `github-ops-triage` is the higher-volume one AND needs duplicate detection
  plus spotting security-shaped reports.
- `project-health`'s contributor-health read exists to decide *why* a number moved (incoming
  low-quality PRs vs. maintainer burnout — opposite problems, same number),
  which is the reasoning a smaller model does worst.

**3. Instruction-following at length is the first thing to degrade on small
models, and a dropped rule here is nearly undetectable.** `project-health`'s
weekly post is the sharp case: a long prompt of conditional rules (degraded repos first,
`null` ≠ zero, the ratio sample floor, the sampled flag, name the
contributors), where a silently-skipped rule doesn't look like an error —
the manager reviews the *content*, not whether a rule was honored. Two
mitigations already carry that load: the gate computes every number before any
model wakes, so the model only narrates; and `null` means "unavailable", never
zero.

**Model sizing, for the record:**

| Model | Size | Fit for this workload |
|---|---|---|
| `gemma3:1b` | 1 GB | No. Would drop rules from a long conditional prompt and cannot be trusted on advisory reachability |
| `llama3.2` | 2 GB | Marginal. Closest in *kind* (reading comprehension, not codegen), but too small for the judgment these tasks are made of |
| `qwen3-coder:30b` | **18 GB** | Capable enough — and it alone roughly *triples* the documented footprint (INSTALL §0 budgets 10–15 GB free disk for the whole stack, plus a few GB of RAM headroom). A 30B model wants ~20 GB RAM on top of the VM, nested images and the agent containers |

There's also a category mismatch worth naming: **this agent barely writes
code.** It reads GitHub metadata and narrates it. Those are reading
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
translation — to a local model). Which one applies depends on the agent:

| Agent | Right choice | Why |
|---|---|---|
| Helper | **Neither** — Haiku stays | See the section above. What needs a model here is the judgment, which is the part you don't downgrade |
| Manager | `ollama` tool **only** — never the provider | Public-voice judgment is exactly what you don't downgrade. But offloading bulk translation for the bilingual reply rule is a legitimate scalpel |

Both rebuild the container image, so **both are replay-on-recreate**
customizations (see [INSTALL.md → Platform skills](docs/INSTALL.md)).

| Skill | What it would buy | Why it's not adopted |
|---|---|---|
| `ollama-provider` (nanoclaw.dev/skills/ollama-provider) | Routes ONE agent group to a local Ollama model — zero shared-window consumption for that group | **Not approved for any group.** The skill does its own setup (`/add-ollama-provider` extends `ContainerConfig` with `env`/`blockedHosts`, writes the per-group `container.json`, and sets `blockedHosts: api.anthropic.com` as a spend guard), so the install work isn't the obstacle. What's open: (a) **you must supply Ollama yourself** — running on `:11434` with a model already pulled, on a host that can run it; (b) **unverified whether `host.docker.internal:11434` reaches the host from inside the sandbox VM's *inner* Docker daemon** — two network boundaries where the skill assumes one, so it needs a real test; (c) it **modifies the Dockerfile (chmod 777 for non-root host UIDs) and NanoClaw's source**, making it a replay-on-recreate customization to record deliberately. Counter-argument that matters on a shared subscription: the manager reviews sub-agent output, and that review costs window capacity — so the net saving is smaller than "zero tokens for one agent" implies, and it is not survivable at all for judgment the manager would have to redo |
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
harness** (ours: `discord-mechanics.md`), **analytics-review → GitHub-issue
drafting** (ours: the posthog/GA4 gated tasks; PostHog's internal "signals"
model is the pattern, not public), and **advisory feed monitoring** (ours: the
scripted sweep; clawsec covers the skill-supply-chain slice only). Our custom
work sits exactly where the ecosystem is empty — keep maintaining it.

## Vendoring pass (to do, post-migration)

1. Pin + read + copy the "Adopt" rows into the right template's `skills/`.
   Allocation follows the tasks:
   - **manager** — triage/support (`ticket-triage`, `customer-escalation`) +
     `security-review`.
   - **helper** — trailofbits (`semgrep`, `sharp-edges`) + `ghsa` for the
     advisory work; google's `google-analytics-data-api-basics` alongside
     `project-health` (metric definitions are exactly the guardrail a
     narration task needs); the analyst pair (`pipeline-check`, `report-spec`)
     if `posthog-weekly-review` ever returns.
2. Prefer the analyst template's many-small-skills layout over one mega-skill.
3. Re-run `check-templates.mjs` (frontmatter + no-symlink rules apply to
   vendored skills too) and restamp.
4. Consider optional `mcp.json` entries: a community GA4 MCP server and
   PostHog's MCP — **GA4 on `local`, PostHog on the Helper**.
   `project-health` and `posthog-weekly-review` both run there, and
   local is the only agent holding the GA4 and PostHog credentials at all, so
   an entry on any other agent would be an MCP server with nothing to
   authenticate as. Placeholder credentials, and test whether OneCLI proxy
   injection satisfies their boot checks. (`posthog-weekly-review` itself is
   removed for now, 2026-08-24 — see the credential note above if it comes
   back.)

