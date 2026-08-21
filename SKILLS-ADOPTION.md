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
| Cost | `ollama-provider` | nanoclaw.dev/skills/ollama-provider | — (official NanoClaw skill) | Per-group routing to a local Ollama model — zero Anthropic tokens for that group. Coding agent only (lead-reviewed output tolerates a weaker model; lead/marketing quality IS the product). See OPERATIONS.md → models for the three preconditions to verify (pinned-image support, VM-to-host networking, host hardware) |

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

| Skill | Blind spot it closes | How it fits |
|---|---|---|
| `dashboard` | **Observability** — our biggest documented gap: the owner had no way to see token usage, per-session state, context windows, or live logs without CLI archaeology | Read-only by design (safe), port 3100 — publish it and reach it the same way as the OneCLI dashboard (Tailscale for remote). **Caveat**: it wires a pusher into NanoClaw's source, i.e. a customization of the sealed install — treat it as a *replayable install step*: apply at setup, and it's one more line in the recreate checklist (cattle philosophy: customizations are replayed, never merged) |
| `debug` | Day-2 troubleshooting — logs, env, mounts, common container problems | Built-in; use from the break-glass Claude session. Add to the break-glass doctrine as the first tool to reach for |

### Optional — adopt when the trigger fires

| Skill | Trigger | Notes |
|---|---|---|
| `tavily` | The coding agent moves to Ollama (losing Claude's built-in search), or the lead needs structured page extraction | **Keyless** — fits default-to-free exactly; per-group scoping fits least-privilege. Claude-provider groups already have built-in search, so don't add it speculatively |
| `ollama` (tools, distinct from the provider) | Bilingual reply volume gets expensive | Offloads translation/summarization to a local model as a tool while the agent stays on Claude — a scalpel where `ollama-provider` is a hammer |
| `rtk` | Only if interactive lead sessions show heavy bash-output token burn | 60–90% savings on dev-command output via a PreToolUse hook — but our gates already strip the bulk of command output before any model sees it, so expect modest gains here. Per-group, Claude-only |
| `macos-statusbar` | Host is a Mac running NanoClaw as a host service | Green/red menu-bar dot + start/stop/restart + launch-on-login — directly softens "the session IS the system." **But it manages a launchd NanoClaw, not an `sbx` VM** — for our sandbox deployment it needs adaptation (point it at the sbx lifecycle) before it applies; until then, tmux + the weekly heartbeat is the answer |
| `learn` | Ongoing | Formalizes what the lead persona's "Grow your toolkit" section already does by hand — distill `plugin-data/*/learned/` notes into proper skills at restamp time |
| `clidash` | If `dashboard` feels heavy | Zero-dependency read-only alternative built from `ncl` JSON output — less coverage (no token usage), less surface |

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
