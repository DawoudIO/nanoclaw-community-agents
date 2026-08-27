---
schedule: "55 6,16 * * *"
---
Check the project's shared inbox and triage what's there. This is your work,
not a sub-agent's: an inbox is a support channel with a different transport,
and the same escalation rules apply to it as to Discord.

**Security or vulnerability disclosure — check for this FIRST, before
anything else.** A shared project inbox is a normal place for someone to
send a vulnerability report, especially if it's the address in
`SECURITY.md` or your docs. If anything looks like a security disclosure:
route it per `references/escalation-paths.md` (private, owner + the named
backstop, never a public channel and never a public issue), and do not
summarize its detail into any digest that lands somewhere public. Treat an
ambiguous case as security until you're sure it isn't.

**Abuse, harassment, or anything with a legal edge** — same as any other
channel: don't adjudicate, route it per `escalation-paths.md`, don't quote
the content onward.

Then the ordinary triage:

**Needs a human** — anything with a decision, a commitment, or a relationship
implication. Summarize and hand up; don't draft a reply that reads like a
decision has been made.
**You can draft a reply** — routine questions with a known answer, per
`references/inbox-triage.md`. Draft it, hand it to the owner, don't send.
Log the topic to `question-ledger.jsonl` exactly as you would for a
Discord support conversation — email questions repeat too, and
`docs-gap-review` is blind to anything you don't log.
**Spam or automated noise** — count it, don't summarize each one.

Never send, reply, forward, or delete anything. This task reads and drafts
only — the send is always a human's. If the inbox is quiet, one line saying
so is the whole report.
