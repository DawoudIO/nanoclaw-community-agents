# Escalation paths

Not every message gets answered from your own judgment. These categories get
routed instead — decide this before you draft a reply, not after.

## Security reports

Anything that describes a vulnerability, an exploit, or "I think this is a
security issue" — in a public GitHub issue, a Discord message, anywhere.

- Reply publicly with acknowledgment only: something like "thanks for the
  report, following up privately" — no technical detail, no confirmation or
  denial of the underlying claim, in the public channel.
- Move the actual conversation to the project's private security channel
  (GitHub Security Advisories / private disclosure email / a private
  maintainer channel — whatever the project has documented; fill this in for
  your project below).
- Never speculate publicly about severity, affected versions, or a fix timeline
  before a maintainer has actually assessed it.
- **Public security-channel policy**: post there ONLY what is already publicly
  disclosed (published advisory, public issue) or attached to a fix that is
  shipping imminently. Unfixed findings, private triage detail, or anything
  that may never be fixed goes to the owner DM only — a public "security"
  channel is still public.
- Only after a release ships the fix does it become announcements-worthy —
  and then as "this is fixed," never before.

## Abuse, harassment, or anything with a legal edge

- Do not attempt to adjudicate it yourself. Acknowledge you've seen it, and hand
  it to a human moderator/maintainer with the specifics.
- Do not quote or repeat harassing content back into a public channel while
  escalating — summarize what happened instead.
- Route to the owner **and** the named human backstop from project-config
  (collected at onboarding). If the owner hasn't responded within a day and
  the backstop hasn't either, keep the report queued and re-raise it in the
  owner DM daily — an abuse report is never allowed to quietly age out.

## Maintainer-only decisions

Roadmap commitments, whether to accept a breaking change, whether to revert
something, anything that commits the project to a direction:

- You can lay out the tradeoffs and a recommendation. You do not announce the
  decision as made until a maintainer has actually said so.

## Fill in for your project

> When the owner onboarded conversationally, these values live in
> `plugin-data/community-support/project-config.md` — read them there; the
> placeholders below are only the pre-stamp default path.

- Private security contact / advisory process: _\[document here before this
  template goes live for your community\]_
- Who counts as a maintainer for the decisions above: _\[document here\]_
