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
| `tavily` | The coding agent moves to Ollama (losing Claude's built-in search), or the lead needs structured page extraction | **Keyless** — fits default-to-free exactly; per-group scoping fits least-privilege. Claude-provider groups already have built-in search, so don't add it speculatively |
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

## Strong candidate: an Ollama "acknowledger" for when the lead is rate-limited

This is a **different and much better** use of Ollama than the coding-agent
idea below, and it targets a real failure this deployment has already lived
through: **when the lead exhausts its window it stops answering Discord
entirely, and the community gets silence.** For a public-facing support agent
that is the worst possible failure — worse than a slow reply, because silence
reads as abandonment.

### Why this case is strong where the coding case is weak

| | Coding on Ollama | Acknowledger on Ollama |
|---|---|---|
| What it replaces | Good judgment → worse judgment, on tasks that need judgment | **Silence → a holding reply.** Strictly better than the alternative |
| Capability required | High (advisory reachability, duplicate detection, 1,130-word rule following) | **Almost none** — "seen it, logged it, a maintainer will follow up" |
| Model needed | `qwen3-coder:30b`, 18 GB — triples the resource budget | **`gemma3:1b`, 1 GB** — fits the documented budget comfortably |
| Failure mode if the model is bad | Confidently wrong security assessment | A slightly awkward acknowledgment |

It also matches the responsiveness research this template set already cites:
first-response delay is the strongest predictor of whether a newcomer comes
back, and CHAOSS's own guidance is that *any* response beats none — "even if
the response is to thank them and give them an idea of when to expect
feedback."

### The design that would work

**Acknowledge, never answer.** The agent's entire permitted output is a
holding reply from a narrow template: it confirms receipt, says a maintainer
will follow up, and stops. It makes **no substantive claim** about the
project, ever — no how-to answers, no bug assessments, no version facts. That
constraint is what makes a 1 GB model safe here: there is almost nothing to
get wrong.

- **Trigger**: a support-tier message the lead hasn't replied to within N
  minutes (owner-configured). Not instant, so the lead answers normally
  whenever it can and the acknowledger stays silent.
- **Escalation**: if something looks security- or abuse-shaped, it
  acknowledges and flags to the owner DM — it does not triage.
- **Handoff**: log the message so the lead picks it up when it recovers; the
  acknowledgment is a receipt, not a resolution.

### Honest open questions — none of these are settled

1. **Does it break single voice?** Readers see one bot (both agents post
   through the same Discord bot token), so the *reader-facing* identity holds.
   But architecturally it's a second agent with channel-write access — a
   second surface an injected instruction could aim at. The narrow
   template-only capability is the mitigation, and it needs to be a hard
   persona rule, not a preference.
2. **Can two agent groups wire to one Discord channel** in NanoClaw, and does
   the per-group provider override coexist with that? Unverified.
3. **Double-posting** if the lead recovers mid-flight — needs a claim/lock
   convention, probably via the public-action ledger.
4. **Is an LLM even the right tool?** The acknowledge-only role needs so
   little intelligence that a non-model responder would be more robust still.
   Within NanoClaw's agent-per-group model an Ollama agent is the available
   way to get a non-consuming responder — but if the platform ever exposes a
   plain scripted auto-reply, that would beat this.

**Verdict: propose, verify at install, decide after.** The problem is real and
already experienced; the design is sound; the resource cost is genuinely
small. What's missing is confirmation that the wiring works, which only a live
install settles. Note this also does nothing about the underlying cause —
**pausing tasks and separating meters is still what keeps the lead alive**;
this is a safety net for when that fails, not a substitute.

## Decided: NO Ollama for the coding agent — Haiku stays

Asked to compare Ollama against the coding agent's actual Haiku-class
workload rather than against Sonnet. The comparison kills the idea, and it's
worth writing down so it isn't re-proposed on vibes.

**1. The volume it would save is already tiny.** The gates did that work.
Realistic wakes per week across all 7 coding tasks:

| Task | Cron | Wakes only when | Est. wakes/wk |
|---|---|---|---|
| `github-ops-triage` | 4×/day | new or updated issues/PRs | ~10–20 |
| `repo-mirror-sync` | 96×/day | an upstream commit landed | ~5–20 |
| `dev-metrics-report` | daily | a number moved, else 7-day heartbeat | ~3–7 |
| `good-first-issue-health` | weekly | always (its output IS the funnel state) | 1 |
| `security-advisory-sweep` | 6×/day | a NEW advisory | ~0–1 |
| `posthog-weekly-review` | weekly | an insight changed, else 28-day | ~0–1 |
| `repo-hygiene-audit` | quarterly | a community file is missing | ~0.08 |

~20–50 wakes/week at ~6.2K context each, with a byte-identical persona prefix
that caches. On the cheapest model tier, that is close to noise.

**2. The risk is concentrated in exactly the wrong tasks.** The 7 split into
mechanical narration and real judgment — and the judgment half is where a
small local model fails:

- `security-advisory-sweep` asks it to "assess whether the project is
  genuinely affected (a vulnerable dependency that isn't reachable in this
  codebase is worth a different note than an exploitable one)." That is
  security reachability reasoning. A confidently-wrong local answer here is
  worse than no answer.
- `repo-mirror-sync` asks whether a wiki edit contradicts current code, or a
  docs change needs a currency check — cross-referencing judgment.
- `github-ops-triage` is the highest-volume task AND needs duplicate
  detection plus spotting security-shaped reports.

**3. `dev-metrics-report`'s prompt is ~1,130 words of conditional rules**
(degraded repos first, ready-to-merge leads, `null` ≠ zero, ratio sample
floor, sampled flag, name the contributors). Instruction-following is the
first thing to degrade on small models, and a silently-dropped rule is nearly
undetectable — the lead reviews the content, not whether a rule was skipped.

**4. It can cost MORE window than it saves.** Coding is Haiku; the lead that
reviews every coding output is Sonnet-class. Making coding worse shifts work
onto the more expensive tier, plus your own review attention. That inverts
the entire point.

**5. Real costs on the other side of the ledger:** Ollama infra and host RAM
for a capable model, cold-start latency, replay-on-recreate, and the
"local models sometimes claim to be Claude" wrinkle interacting badly with
our mechanical identity checks.

**6. And the model options make it concrete — the only one good enough
blows the resource budget.** The commonly-suggested pulls:

| Model | Size | Fit for the coding agent's actual work |
|---|---|---|
| `gemma3:1b` | 1 GB | No. Would drop rules from a 1,130-word conditional prompt and cannot be trusted on advisory reachability |
| `llama3.2` | 2 GB | Marginal. Closest in *kind* to the work (reading comprehension, not codegen), but too small for the judgment tasks |
| `qwen3-coder:30b` | **18 GB** | Capable enough — and it alone roughly *triples* our documented footprint (INSTALL §0 budgets 10–15 GB free disk for the entire sandbox stack, plus "a few GB of RAM headroom"). A 30B model wants ~20 GB RAM on top of the VM, nested images, and three agent containers |

There's also a category mismatch worth naming: **the coding agent barely
writes code.** It reads GitHub metadata and narrates it — triage digests,
metric deltas, advisory assessments, change summaries. Those are reading
comprehension, instruction-following, and judgment tasks. A code-specialised
model is not obviously the right tool for them, so "strong at code tasks"
doesn't transfer to this workload the way it looks like it should.

**What would change this verdict:** a genuinely high-volume, purely
mechanical workload — mass translation, large-scale log summarization, bulk
classification. That is exactly where a 1–2 GB model would earn its keep, and
none of it exists in this template set today. **Measure at install**
(clidash), and revisit only if coding turns out to consume meaningfully. The
prediction is that it won't, because the gates already solved the problem
Ollama would be solving.

## Proposed, NOT yet decided — needs an owner call

**`ollama-provider` and `ollama` are alternatives, not a pair — you never
need both for the same agent.** `ollama-provider` *replaces* the model that
runs an agent group (that group leaves the shared window entirely).
`ollama` adds Ollama as a *tool the agent calls* (the agent stays on Claude
and still consumes window, but can hand discrete subtasks — summarization,
translation — to a local model). Which one applies depends on the agent:

| Agent | Right choice | Why |
|---|---|---|
| Coding | `ollama-provider` | Most formulaic output, lead-reviewed anyway — the whole group can move off-window. The tool version would be pointless here: it'd already *be* a local model |
| Lead | `ollama` tool **only** — never the provider | Public-voice judgment is exactly what you don't downgrade. But offloading bulk translation for the bilingual reply rule is a legitimate scalpel |
| Marketing | Neither, by default | Draft quality is the deliverable |

Both rebuild the container image, so **both are replay-on-recreate**
customizations (see [INSTALL.md → Platform skills](docs/INSTALL.md)).

| Skill | What it would buy | Why it's not adopted yet |
|---|---|---|
| `ollama-provider` (nanoclaw.dev/skills/ollama-provider) | Routes ONE agent group to a local Ollama model — zero shared-window consumption for that group. The coding agent is the only sensible candidate: most formulaic output, and the lead reviews everything it produces anyway | **Never approved — it was analysed, not decided.** The skill does its own setup (`/add-ollama-provider` extends `ContainerConfig` with `env`/`blockedHosts`, writes the per-group `container.json`, and sets `blockedHosts: api.anthropic.com` on that group as a spend guard), so the install work is not the obstacle. What's actually open: (a) **you must supply Ollama yourself** — running on `:11434` with a model already pulled, on a host that can run it; (b) **unverified whether `host.docker.internal:11434` reaches the host from inside the sandbox VM's *inner* Docker daemon** — that's two network boundaries and the skill assumes one, so it needs a real test; (c) it **modifies the Dockerfile (chmod 777 for non-root host UIDs) and NanoClaw's source**, making it a replay-on-recreate customization like the clidash pusher, which our digest-pinning policy tolerates but should record deliberately. Counter-argument worth weighing: on a shared subscription the lead still reviews every coding draft, and that review costs window capacity — so the net saving is real but smaller than "zero tokens for one agent" implies. Decide after the first install, with usage numbers in hand |
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

1. Pin + read + copy the "Adopt" rows into the right template's `skills/`
   (lead: triage/support + security-review; marketing: coreyhaines subset +
   brand-voice; coding: analyst pair + trailofbits + ghsa).
2. Prefer the analyst template's many-small-skills layout over one mega-skill.
3. Re-run `check-templates.mjs` (frontmatter + no-symlink rules apply to
   vendored skills too) and restamp.
4. Consider optional `mcp.json` entries: a community GA4 MCP server
   (marketing) and PostHog's MCP (coding) — placeholder credentials, and test
   whether OneCLI proxy injection satisfies their boot checks.
