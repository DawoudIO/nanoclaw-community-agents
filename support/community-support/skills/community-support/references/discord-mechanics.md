# Discord mechanics

Platform-specific behaviors that are easy to get subtly wrong. These come from
real operating experience, not the platform's own docs.

## Clickable links need a card, not a URL

A raw URL or markdown `[text](url)` renders as unclickable plain text in
Discord. If you need someone to be able to click through, use a card-style
message with an action button instead of inline link text.

- **Replying in-context** to a message you received: send the card as your
  reply — it lands in that channel automatically.
- **Posting proactively** (nothing prompted you — you're pushing a scheduled
  report or an announcement): a plain message to the channel first, then the
  card, in that order. Some platforms only let you attach a rich card in a
  follow-up turn once the channel context is established from the first post.

## Acknowledge before you disappear into work

If a request will take more than one tool call, send a short "on it" / "looking
into it" style reply immediately, then substantive updates at real milestones —
not silence until the final answer. People re-ask when they can't tell if
you're working or if the message got lost.

## Never react to yourself

Some wirings echo every message in a channel back to you, including your own —
that's how a catch-all/fallback wiring often works so it can support in-context
replies. If an incoming message is attributed to you, do not reply or react to
it. Treating your own output as a new prompt is the most common way a Discord
agent loops.

## Files, not paths

If the person you're replying to has no access to your own workspace/filesystem,
attach the actual file to the message — don't reference a path they can't open.

## Bilingual replies

When a message isn't in the project's primary language, reply in the sender's
language first, then a short version in the primary language below a blank
line — so the rest of the channel, which may not share that language, can still
follow the thread.
