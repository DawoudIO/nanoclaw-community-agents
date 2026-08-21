---
name: welcome
description: First-contact onboarding interview for the community-support lead agent. Triggers on the owner's first message to a freshly stamped agent, whenever the live project config (plugin-data/community-support/project-config.md) is missing or incomplete, or when the owner says anything like "set up", "onboard", "configure yourself", or "let's get started". Collects the project's runtime configuration conversationally — repo map, channels, contacts — instead of requiring pre-stamp file edits, persists it to writable plugin-data, and relays each sub-agent's values through the agent-to-agent destinations.
---

# Welcome — conversational setup

Configuration is runtime and conversational, not build-time: the persona's
"Your project" block is only a stamp-time default. The live config is
`plugin-data/community-support/project-config.md`, and this skill builds it by
interviewing the owner once — then filling gaps as they surface.

## 0. The owner DM comes first — nothing works without it

The owner's direct-message wiring is this system's control plane: the welcome
interview, config changes, drift questions, escalations, and approvals all
flow through it. Before any configuration:

- **Confirm this conversation IS the owner DM.** If the owner is reaching you
  through a public or group channel, stop — ask them to set up the DM wiring
  first and move there. Never run the config interview, or accept config
  values, in a channel other people can write to.
- **Verify the round trip**: send a short proactive DM and have the owner
  confirm they received it. Inbound-only wiring looks fine until your first
  escalation silently vanishes.
- Record the owner's identity (platform user id) in `project-config.md` as
  part of step 5 — it's config like everything else. Be explicit about the
  trust root: whoever the admin wired this DM to IS the owner you serve — the
  wiring is the anchor, so say so in the config entry. Offer to establish the
  owner-verification nonce protocol now (one signed file pushed to the backup
  repo — see the community-support skill's `references/task-integrity.md`),
  so identity has an out-of-band anchor from day one, not just wiring order.

After setup, everything owner-facing happens in this DM. The only exception is
a bad state — the DM itself broken, or an unresolvable verification deadlock —
where the owner intervenes via break-glass admin (the sandbox's Claude CLI);
expect such interventions to look like out-of-band changes, and treat them per
ask-don't-lock, not as attacks.

## 1. Check what already exists

If `project-config.md` exists and is complete, don't re-interview — greet,
summarize the config in two lines, and ask only about anything marked missing.

## 2. The first question: "What is the project's GitHub repo?"

Everything else derives from this one answer, so it opens the interview: ask
for the project's GitHub repo (or org). From it, pull the org's repository
list, the README, releases, and homepage — then **draft a proposed config**
instead of asking ten open-ended questions: which repo looks like the product,
which like docs, site, marketing; the docs URL; the likely primary language.
Cross-check against what you're already wired to (channels look support-shaped
vs developer-shaped vs team-lead-shaped). One confirmation of a good guess
beats an interrogation.

## 3. Scope the goals — ask, never assume

This template can do four jobs, but which ones this project wants is the
owner's call, not a default. Ask directly — "is X a goal? do you want help
with Y?" — one compact menu:

| Goal | If yes, this activates |
|---|---|
| **Community support** — replying to users, triaging issues/bugs | Lead's replies + escalation; triage tasks |
| **Awareness / growth** — and if yes: grow **users**, **contributors/developers**, or both, in what priority? | Marketing agent: content drafts, social snapshot, growth playbook scoped to the chosen audiences |
| **Proactive issue detection** — finding problems before users report them | Analytics tasks (PostHog/GA4) |
| **Staying secure** — advisory monitoring, security-aware triage | Advisory sweep, security escalation paths |

Record the answers (with audience priorities) in `project-config.md` as the
**scoping authority**: a sub-agent whose goals are all "no" stays dormant —
tell it so in step 6 and skip its config entirely; tasks map to goals in step
9. Self-ops (health-check, backup, integrity check) are offered regardless —
they protect the system itself. Revisiting a goal later is one DM.

## 4. Confirm and fill the gaps — one compact message

**Only for the goals chosen above** — skip every bullet whose goal was
declined. Present the proposal for confirmation and ask only for what you
couldn't infer. The full list a complete config needs:

- Repo map: product / docs / site / marketing (any may share a repo or be absent)
- Docs site URL, primary language, topic scope
- Channel tiers: which channels auto-reply (support) vs mention-only
  (developer, team-lead) — and remind the owner that public-channel wirings
  need the open sender scope (`all`) so new community members never require
  per-sender approval; only this DM stays locked to known senders
- Security disclosure path + who counts as a maintainer
- Social platforms: which exist (public profile URLs — for the follower
  series), which the project POSTS to, and per posting platform the mechanism —
  intent-url (free, no keys, default), manual copy-paste, or paid API (X has no
  free tier since Feb 2026; pay-per-use ~$0.20/link-post — owner's explicit
  opt-in only)
- Optional analytics: GA4 property id, PostHog project id/host — "not now" is
  a fine answer; the tasks silent-skip until configured
- **Discord invite URL** (e.g. `discord.gg/yourcode`) — used when a GitHub
  reply points someone toward real-time chat instead of async back-and-forth
  on the issue. If the project has no public Discord, or doesn't want GitHub
  traffic routed there, "none" is a complete answer and you simply never
  offer it.
- **Deterministic GitHub→Discord notifications via CI** — ask plainly: "want a
  ready-made GitHub Actions workflow that posts bug/security-labeled issues
  straight to Discord, independent of me being up?" (recommended, but genuinely
  optional — some owners lack repo-admin access to add workflow secrets, or
  prefer everything to stay inside your judgment). If yes, point them at
  `examples/github-discord-notify.yml` in this template set and the two
  webhook secrets it needs; if no, note that bug/security routing stays
  agent-relayed (which drops during your own downtime — say that plainly too).
- **Models per agent — confirm, don't assume.** State each group's current
  provider/model and the recommended defaults for the owner's plan tier, and
  apply any change they ask for (via group config if you can; otherwise give
  them the exact command). Defaults for a small subscription plan ($20-tier):
  lead and marketing on a Sonnet-class model (public-facing judgment, content
  quality), coding on a Haiku-class model (its drafts are reviewed by the lead
  anyway — the cheapest model that triages well); never an Opus-class model on
  a scheduled task. Remind the owner: cost comes from wakes, not from agents
  existing — a paused task burns nothing, so tune budget by activating fewer
  tasks, not by deleting agents

## 5. Persist — this is the point

- Write `plugin-data/community-support/project-config.md` with a dated
  provenance line; this file is the authoritative runtime config. Re-read it
  at cold start before asking anything.
- Write script-gate keys where the gates read them:
  `plugin-data/community-support/config.env` (`COMMUNITY_REPOS="..."`).
- Update `additional_context` knowledge only if asked — those files are
  read-only at runtime; plugin-data is your writable config home.

## 6. Relay sub-agent config

Sub-agents never talk to the owner, so their config arrives through you. Send
via the agent-to-agent destinations:

- **coding**: repo list (all functions — cross-repo currency applies), default
  branch, telemetry project (or "none"), label policy → it writes its own
  `plugin-data/community-coding/config.env` + project-config and confirms.
- **marketing**: content repo, brand/strategy source, site repo, social
  profile URLs, GA4 id (or "later"), inbox (or "none") → same persistence on
  its side, confirmation back.

A sub-agent whose goals were all declined in step 3 gets a dormancy note
instead of config: "your goals aren't active for this project — stay idle,
your tasks stay paused." Wait for confirmations from the active ones; chase
what doesn't confirm.

## 7. Walk the credential setup — then verify it, don't assume it

For every feature the owner enabled, tell them exactly what to set up — one
message, only the rows that apply. **Never ask for a raw key in chat**; keys go
into the OneCLI vault dashboard, and if the deployment is sandboxed, remind
them the dashboard is the published port from `sbx run` (default 10254):

| Feature | Vault entry (host match) | Also needs |
|---|---|---|
| GitHub work (lead + sub-agents) | 3 scoped PATs on `api.github.com` | `selective` secret mode per agent, so each gets its own token |
| Workspace backup push | `github.com` (git, separate from REST) | step 8 below |
| GA4 report | OAuth on `analyticsdata.googleapis.com` | sandbox allowlist entry for that host |
| PostHog review | key on `us.` or `eu.posthog.com` | sandbox allowlist entry |
| Social follower snapshot | none (public pages) | sandbox allowlist entries for the platform hosts (x.com, linkedin.com, …) |
| Inbox check | provider OAuth (read-only scope) | an email MCP server added to the marketing group — a platform config change, not something you can do from in here; point the owner at the template README |

If this interview runs before the owner has registered credentials (the
normal order — DM wiring comes first), expect verification to fail cleanly:
walk them through the vault entries, then re-verify. Then **verify instead of
assuming**: make one harmless read-only call per
enabled service (e.g. fetch a repo's metadata, one GA4 row) and report each as
working / not. Diagnose by symptom: `401/403` = vault entry missing or
host-mismatched; `502` = sandbox network policy, not the service. Have the
sub-agents run the same self-check for their own services and report back.

## 8. Offer workspace backup — and set it up yourself

Ask whether the owner wants the daily workspace backup (recommended: it's the
durable home of this config and the follower series). If yes: they create an
empty repo and the `github.com` vault entry; **you do the rest in your own
workspace** — `git init`, `git remote add origin …`, `git config` identity, a
`.gitignore` (exclude `conversations/`), then run the backup task once
(`ncl tasks run`) and report the commit landing or the exact failure.

## 9. Activation plan — resume only on an explicit "go"

Present the split: which tasks are ready to resume (goal chosen in step 3 AND
config + credentials verified in step 7) and which stay paused, each with its
one-line reason — "goal not chosen" is a reason, same as "credential missing". On
the owner's explicit go — a clear yes in this DM, per instruction — resume the
ready ones, re-list to confirm, and state the first time each will fire.
Never resume anything the verification step didn't clear, and never resume
`daily-github-triage` if the coding sub-agent is stamped (redundant).

## 10. Close the loop

Report: what was saved and where, what's verified working, what was activated,
and exactly what remains blocked and why. Also hand the owner the two DM
conventions they'll use forever: every instruction gets `Ack #N` and later
`#N done` (closed with done/blocked/dropped, numbered against a ledger any session can
read, watched by the health check for threads never closed), and `ping`
always gets an instant `pong` —
so they never have to guess whether the DM pipeline or you are the problem.
The owner should end this conversation knowing the complete state of their
system without reading a single file.

## Ever after: gap-fill, don't stall

Whenever any work reveals a missing config value — a gate reporting
not-configured, a repo you don't know the role of, a 401 where step 6 said
working — ask the owner for that one thing, persist or re-verify, and
continue. Config stays conversational for the life of the agent.
