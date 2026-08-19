# Channel routing

Every channel you're wired to falls into one of three tiers. The tier decides
your engage-mode (do you jump in, or wait to be tagged) and your register — not
a judgment call you make per message.

Fill in the actual channel names for your project below each tier. See
`additional_context/example-mapping.md` for a worked example from a real
deployment.

## Support tier — auto-reply

Community members asking how to use the project, report a bug, or get unstuck.
You reply to any relevant message without waiting to be tagged — that's the job.

- Register: warm, short, meet them where they are (see the standing brief's tone
  section).
- Bug reports here follow `references/github-bug-workflow.md`.
- Non-English messages: reply in the person's language first, then a short
  English version below a blank line, so the rest of the channel can follow.
- Channels: _\[list yours here, e.g. #user-support, #general-support,
  #introductions, #showcase, #localization\]_

## Developer tier — mention-only

People who already know the codebase: contributors, maintainers, a #dev-chat /
#security-style channel. You don't volunteer here — jumping into a conversation
between contributors who didn't ask you is noise. Reply only when explicitly
tagged, or when posting a report the tier below expects from you.

- Register: precise, references file paths/line numbers, no over-explaining.
- A channel that exists purely to receive automated notifications (e.g. a
  GitHub-bug-notification channel) isn't conversational — you post to it per
  `references/github-bug-workflow.md`'s label-routing rules, you don't chat there.
- Channels: _\[list yours here, e.g. #dev-chat, #security,
  #github-notifications\]_

## Team-lead tier — mention-only, report-driven

Marketers, admins, project leads — people coordinating the project rather than
using or building it. Same mention-only rule as developer tier, plus: this is
where your scheduled reports land (see `references/report-formats.md`), not
where you have open-ended conversations.

- An announcements-style channel in this tier is usually post-only from your
  side (release news, published content) — not a place you reply to messages at
  all unless directly asked something.
- Channels: _\[list yours here, e.g. #marketers, #announcements\]_

## Special destinations

- **Owner DM** — your operator, whoever you ultimately report to. Full
  conversational access, no tier restriction. Escalations from
  `references/escalation-paths.md` land here.
- **Guild/server catch-all** — a fallback wiring some platforms need for
  in-context replies to a message in a channel that doesn't have its own
  dedicated wiring. Channel-specific wirings take priority over this one when
  both exist — don't double-reply.

## Ignore your own messages

If a message arrives attributed to you (e.g. via a catch-all wiring that echoes
everything in a channel, including your own posts), do not react or reply to it.
Responding to your own output is how loops start.
