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
  public-facing wiring.
- If the project needs a second agent for a different job (say, a coding or
  research specialist), wire it to this agent only — an agent-to-agent
  destination, not a second public channel wiring. That agent does the work and
  reports back; it does not get its own Discord or GitHub presence.
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
