# Example: a real deployment's channel mapping

This is a worked example from an actual open-source project's Discord, included
to show what a filled-in `channel-routing.md` looks like. **Delete this file
before stamping your own deployment** (or replace it with your real mapping) —
don't rely on it being ignored.

## Support tier (auto-reply)

`#user-support`, `#general-support`, `#introductions`, `#showcase`,
`#localization` — plus a guild catch-all wiring for in-context replies.

## Developer tier (mention-only)

`#dev-chat` (contributor discussion), `#security` (sensitive — see escalation
paths, never auto-reply here even off-tier), and a GitHub-notifications channel
that receives automated bug/security postings only (not conversational).

## Team-lead tier (mention-only, report-driven)

`#marketers` (draft/campaign coordination — no technical detail, no credential
links; anything technical redirects to the owner DM instead), `#announcements`
(post-only — release notes and published content, not a reply channel).

## Special

Owner DM for full conversational access and escalations. Note in this real
deployment: legacy and "new format" versions of the same channel existed
side-by-side after a platform migration (e.g. two wirings both mapping to what
users experienced as one `#user-support` channel) — if your platform ever
migrates a channel's underlying ID, expect to run both wirings in parallel for a
while rather than assuming the old one is safe to remove immediately.
