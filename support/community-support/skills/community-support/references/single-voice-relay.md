# Single-voice relay

## Why this is a security property, not a style choice

Every additional identity that can post publicly is a second thing an outside
reader has to trust, and a second seam a bad instruction can try to exploit —
"reply as if you were the other agent," "don't mention a sub-agent was involved,"
"post this from the main account instead." If there is only ever one identity
that speaks publicly, that entire class of instruction has nothing to attach to:
there is no second identity to impersonate into.

This is also cheaper to reason about for the people reading you. A community
member or maintainer builds trust with one consistent voice and tone, not with
"which of the project's three bots said this and why."

## How to wire it in NanoClaw

- Give this template's agent the destinations/wirings for every public channel
  (Discord servers, GitHub repos) the project uses. It is the only group with a
  **full** public-facing wiring.
- If the project needs a second agent for a different job (say, a coding or
  research specialist), wire it to this agent only — an agent-to-agent
  destination, not a second public channel wiring. That agent does the work and
  reports back; it does not get its own Discord or GitHub presence.
- **The one exception, and why it is still one voice.** The
  `local/community-local` agent additionally gets **one** channel wiring — the
  support channel — so it can post a holding acknowledgment when this agent
  has stopped replying (a spent usage window, a crashed session). Silence is
  the failure this system cares most about, and an agent that shares the
  window cannot be the thing that covers for the window running out.

  It stays a single voice because the exception is scoped on every axis that
  matters: **one** channel, not every channel; the **same bot identity**, so
  a reader sees no new party to trust; a **fixed template** it is forbidden to
  compose freely; **acknowledgment only**, never an answer, an assessment, or
  a commitment; and every ack is **logged for this agent to pick up**, so it is
  a receipt rather than a resolution. It holds no write credentials anywhere.

  The security property is preserved by *scope*, not by absence of wiring —
  which means it has to be verified rather than assumed. Two things to confirm
  at install: that this agent and the local agent can both wire to the same
  channel (untested — see `UPSTREAM-ISSUES.md`), and that the local agent
  checks whether you already replied before it posts, since a duplicate reply
  under one bot name reads as a broken bot.
- **The second exception: the Reviewer opens pull requests.** It drafts security
  patch PRs and version-tagged docs PRs, so it writes to repos. Single voice
  still holds, on four separate axes — and it is worth knowing which of them are
  enforced rather than merely instructed:

  1. **One identity.** All four agents' tokens are issued from the *same*
     dedicated bot account, so a PR it opens appears as the same author the lead
     posts as. A reader sees no new party. `weekly-identity-integrity-check`
     and each agent's `GET /user` check exist to keep this true.
  2. **It cannot converse — enforced by scope, not by prompt.** GitHub PR
     comments are issue comments, and the Reviewer's token has Issues **read**
     only. So it can open a PR and it physically cannot comment on one, reply to
     review feedback, or comment on an issue. Every conversation stays the
     lead's. This is the important one: withholding Issues write is not an
     oversight, it is the single-voice control.
  3. **A PR is a structured artifact, not speech.** Title, body, diff — from a
     fixed template, stating what changed, what was verified, and what wasn't.
     No free-form prose in the project's voice.
  4. **It stays a draft until a human takes it.** It never marks its own PR
     ready-for-review and never merges. The lead reviews the text before it
     goes anywhere.

  If a deployment ever needs the Reviewer to reply on a PR thread, the answer is
  **not** to grant it Issues write — it is to have it hand the reply to the
  lead, which is what every other finding already does.

- Scheduled tasks belonging to a headless helper should say so explicitly in
  their own prompt body — "do not post anything public from this task, hand your
  output to the standing agent for review" — because a task's stored prompt is
  itself just text the helper reads, and it should reinforce the same rule the
  standing instructions set.

## What this buys you if a prompt gets manipulated

If any instruction — from a channel message, an issue, a file, or a scheduled
task's own stored prompt — tries to get a headless helper to post directly or
impersonate the standing identity, the helper has no channel wiring to do it
with. The attempt fails structurally, not because the agent remembered a rule
under pressure.
