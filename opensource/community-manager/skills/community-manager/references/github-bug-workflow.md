# Bug report → GitHub issue workflow

## Taking a bug report from chat to an issue

1. Before creating anything, make sure you have: steps to reproduce, the
   project version, and OS/browser (whatever's relevant to the project). If the
   reporter didn't give these, ask — don't create a thin issue and hope for
   detail later.

   **The slop guard — a report you can't stand behind gets a conversation,
   not an issue.** You are a machine that turns chat messages into
   well-formatted GitHub issues, which is exactly the machine maintainers
   are currently drowning under: fluent, plausible, *wrong* reports cost
   reviewers far more than obvious junk (curl's security-report confirmation
   rate fell from 15% to under 5% after AI-generated reports arrived). So a
   well-*formatted* report is not a well-*founded* one. If the report reads
   like generated text (generic phrasing, details that don't cohere, error
   messages that don't match any real version), if the reporter can't answer
   a basic follow-up about their own environment, or if you can't connect
   the claim to anything real in the project — keep asking in chat until it
   grounds out, and if it never does, don't file. Your issues carry the
   project's trust; every one of them must be one a maintainer won't regret
   opening.
2. **Search before you file.** A quick GitHub search on the repo for the
   report's key terms (error message, feature name) catches most duplicates
   before they're created. Found a clear match? Link the existing issue back
   to the reporter instead of filing a new one — same speed, no duplicate to
   triage later. Only file fresh when nothing close already exists.
3. **File it yourself, immediately — this doesn't wait for approval.** You
   already hold the scope for this (`repo`/`public_repo`, opens issues — see
   this template's README credentials table); a real bug report sitting
   unfiled while you wait on anything is exactly the "did the work, got
   ignored" failure this whole workflow exists to prevent. Create the issue
   with a structured body (repro steps, version/environment, expected vs.
   actual), label it appropriately, and reply to the reporter **in the same
   channel they reported in** with the issue URL as a card (see
   `discord-mechanics.md`) — meet them where they are, don't make them go
   open a GitHub account or switch platforms just to get a link back.
4. Read the full issue body — including any markdown tables — before your first
   comment on any issue, whether you filed it or someone else did. Never ask for
   information that's already in the issue; reference what was given to show you
   read it.

## Label-based routing to channels

**Prefer CI for the deterministic part.** A pure label→channel notification
(issue labeled bug → post to the bugs channel) has no judgment in it — if your
project can run a GitHub Actions workflow with a channel webhook, put the
notification there: it fires even when the agent is down, rate-limited, or out
of budget. You handle what needs judgment: the reply to the reporter, the
duplicate call, the escalation. Only do notification relay yourself when CI
webhooks aren't available. (A real deployment moved these notifications from
Actions into the agent and lost them silently whenever the agent hit its
token limit.) A ready-made workflow for this exact split is in
`examples/github-discord-notify.yml` in this template set — it's **ask the
owner first**, not a silent default: some projects would rather keep GitHub
notifications inside the agent's own judgment, or have no repo-admin access
to add workflow secrets. Offer it during onboarding; only propose adding it
if the owner says yes.

**New releases** get their own script-gated task (`release-announcement-watch`)
that announces stable releases to the team-lead tier's announcements channel —
that one you don't set up in CI; it's agent-owned because a good announcement
needs framing (highlights, contributor credit), not just a raw event relay.

When you do route, keep these separate:

- **Bug** → the developer tier's notifications channel.
- **Security** → the security channel only — never announcements, never a
  general channel, regardless of how minor it looks. See
  `escalation-paths.md`.
- **Security advisory published** → same security channel only, until a release
  actually ships the fix — only then does it become announcements-worthy, and
  only as "this is fixed," not before.
- Track which issue IDs you've already notified about in your own state, so a
  relabel or an edit doesn't produce a duplicate post.

## Offering real-time chat from GitHub

If the project has a Discord invite configured (`project-config.md`) and an
issue thread would genuinely move faster live — back-and-forth debugging, a
report that's missing detail and the reporter seems responsive, anything
async is dragging on — offer it once: "For faster back-and-forth, we're also
on Discord: <invite link>." Don't push people off GitHub who are managing
fine there, and don't repeat the offer if it's declined or ignored. The issue
thread stays the record either way — a resolution reached over Discord gets
summarized back onto the issue before closing it.

## Stale issues

An issue with no activity in a while is not yours to close. Include it in your
next scheduled digest for a human to action; closing on your own judgment is a
maintainer call.

## Duplicates

If a new issue looks like a duplicate of an existing open one, say so and link
it — don't close either one yourself, and don't apply a "duplicate" label unless
your project's label scheme makes that completely unambiguous.

## Stale docs found while answering

If answering a support question reveals that a docs or site page describes
outdated behavior, that page is a bug you just found: draft the docs/site
issue (which page, what it says, what the current behavior is) right after
sending the answer — don't leave it as a mental note. Route it like any other
issue you file: created under your identity, linked back to the conversation
that surfaced it.
