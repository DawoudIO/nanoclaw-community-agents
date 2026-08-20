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
  part of step 4 — it's config like everything else.

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

## 3. Confirm and fill the gaps — one compact message

Present the proposal for confirmation and ask only for what you couldn't
infer. The full list a complete config needs:

- Repo map: product / docs / site / marketing (any may share a repo or be absent)
- Docs site URL, primary language, topic scope
- Channel tiers: which channels auto-reply (support) vs mention-only
  (developer, team-lead)
- Security disclosure path + who counts as a maintainer
- Social platforms: which exist (public profile URLs — for the follower
  series), which the project POSTS to, and per posting platform the mechanism —
  intent-url (free, no keys, default), manual copy-paste, or paid API (X has no
  free tier since Feb 2026; pay-per-use ~$0.20/link-post — owner's explicit
  opt-in only)
- Optional analytics: GA4 property id, PostHog project id/host — "not now" is
  a fine answer; the tasks silent-skip until configured

## 4. Persist — this is the point

- Write `plugin-data/community-support/project-config.md` with a dated
  provenance line; this file is the authoritative runtime config. Re-read it
  at cold start before asking anything.
- Write script-gate keys where the gates read them:
  `plugin-data/community-support/config.env` (`COMMUNITY_REPOS="..."`).
- Update `additional_context` knowledge only if asked — those files are
  read-only at runtime; plugin-data is your writable config home.

## 5. Relay sub-agent config

Sub-agents never talk to the owner, so their config arrives through you. Send
via the agent-to-agent destinations:

- **coding**: repo list (all functions — cross-repo currency applies), default
  branch, telemetry project (or "none"), label policy → it writes its own
  `plugin-data/community-coding/config.env` + project-config and confirms.
- **marketing**: content repo, brand/strategy source, site repo, social
  profile URLs, GA4 id (or "later"), inbox (or "none") → same persistence on
  its side, confirmation back.

Wait for both confirmations; chase what doesn't confirm.

## 6. Close the loop

Report to the owner: what was saved and where, which tasks are now ready to
resume, and exactly what remains blocked and why (usually credentials — point
at the README's vault table rather than asking for keys; **never ask for a raw
key in chat**).

## Ever after: gap-fill, don't stall

Whenever any work reveals a missing config value — a gate reporting
not-configured, a repo you don't know the role of — ask the owner for that one
value, persist it the same way, and continue. Config stays conversational for
the life of the agent.
