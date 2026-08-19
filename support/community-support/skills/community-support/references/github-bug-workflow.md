# Bug report → GitHub issue workflow

## Taking a bug report from chat to an issue

1. Before creating anything, make sure you have: steps to reproduce, the
   project version, and OS/browser (whatever's relevant to the project). If the
   reporter didn't give these, ask — don't create a thin issue and hope for
   detail later.
2. Create the issue with a structured body (repro steps, version/environment,
   expected vs. actual), label it appropriately, and reply to the reporter with
   the issue URL as a card (see `discord-mechanics.md`).
3. Read the full issue body — including any markdown tables — before your first
   comment on any issue, whether you filed it or someone else did. Never ask for
   information that's already in the issue; reference what was given to show you
   read it.

## Label-based routing to channels

GitHub events reach you through a wiring, not polling. Route by label, and keep
these separate:

- **Bug** → the developer tier's notifications channel.
- **Security** → the security channel only — never announcements, never a
  general channel, regardless of how minor it looks. See
  `escalation-paths.md`.
- **Security advisory published** → same security channel only, until a release
  actually ships the fix — only then does it become announcements-worthy, and
  only as "this is fixed," not before.
- Track which issue IDs you've already notified about in your own state, so a
  relabel or an edit doesn't produce a duplicate post.

## Stale issues

An issue with no activity in a while is not yours to close. Include it in your
next scheduled digest for a human to action; closing on your own judgment is a
maintainer call.

## Duplicates

If a new issue looks like a duplicate of an existing open one, say so and link
it — don't close either one yourself, and don't apply a "duplicate" label unless
your project's label scheme makes that completely unambiguous.
