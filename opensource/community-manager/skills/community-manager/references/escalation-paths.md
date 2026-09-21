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

### The risk-reality read (owner DM only, never public)

Security reports are the one category where the reporter has an incentive to
overstate, and generated reports have made fluent, plausible, *wrong*
submissions the common case (curl's confirmation rate fell from 15% to under
5% after they arrived). Before the owner spends an evening on it, read the
claim against the code and say how much of it stands up. This is triage for
the maintainer, not a verdict for the reporter — you never tell a reporter
their finding is inflated, and you never dismiss one publicly.

Work through, in order, and cite what you looked at:

1. **Does the code path exist?** Find the file, function or route named in
   the report in the current default branch and in the version they claim.
   A report against code that was removed two releases ago, or that names a
   function the project never had, ends here.
2. **Are the preconditions real?** What does the attacker need — an admin
   account? a logged-in user? network position? Authenticated-admin-only
   findings are routinely filed as "critical". Say plainly what the
   precondition reduces the impact to.
3. **Is there a reproducible proof of concept?** Concrete request, payload,
   and observed result, against a stated version — or prose that describes
   what "could" happen? Untested claims are not zero, but they are not
   confirmed either.
4. **Does the claimed severity match the evidence?** Take their CVSS or
   wording and compare to what steps 1–3 support. Name the gap.
5. **Slop signals.** Generic phrasing that fits any PHP app, error output
   that matches no real version, several near-identical reports from one
   account across projects, a payload that could not have produced the
   described result. Any of these is a reason for more scrutiny, not a
   reason to ignore.

Send the owner one block: **grounded / plausible-unverified / inflated /
not-a-vulnerability**, the two or three facts that decided it, what you
could not check, and the exact one-line reply you suggest sending the
reporter through the private channel. If the code path exists and the
precondition is low, say so with the same directness — this read has to be
willing to confirm, or the owner will stop trusting it when it says
"inflated".

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
> `plugin-data/community-manager/project-config.md` — read them there; the
> placeholders below are only the pre-stamp default path.

- Private security contact / advisory process: _\[document here before this
  template goes live for your community\]_
- Who counts as a maintainer for the decisions above: _\[document here\]_
