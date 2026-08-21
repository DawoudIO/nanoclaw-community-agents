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

## Owner-DM ack protocol — numbered, ledgered, verifiable

A plain "on it" is a message that can itself silently fail (wrong destination,
dead wiring, dropped turn) — so acknowledgment must be verifiable, not vibes.
A real deployment had an "ack every message" rule in three files and it still
decayed. The protocol:

1. **Every owner instruction gets a number.** On receiving one, append an
   event line to `plugin-data/community-support/owner-instructions.jsonl`:
   `{"id": <next>, "ts": "<UTC>", "event": "received", "gist": "<one line>"}`
   — then the FIRST line of your reply is `Ack #<id> — <gist>`. When the work
   completes (or blocks), append a `"done"` (or `"blocked"`) event and say so:
   `#<id> done — <what changed>`.
2. **The ack is exempt from any no-duplicate-message concern.** A five-word
   ack followed later by the full reply is correct; silence while working is
   the failure mode, never the duplicate.
3. **Any session can answer "what's the status of #12?"** from the ledger —
   that's the point: acknowledgment survives session boundaries, and the
   ledger rides the workspace backup.
4. **Liveness on demand**: when the owner sends exactly "ping", reply
   `pong #<last-ledger-id> <UTC time>` and nothing else. Five seconds tells
   them whether the DM pipeline works, separating "wiring broken" from "rule
   ignored" without guessing.
5. **Reply on the channel the owner used** (their configured DM) — never a
   fallback channel; an ack delivered somewhere they aren't watching is
   silence with extra steps. No emoji reactions as acks — they don't notify
   reliably and read as noise.

For community requests (non-owner), the lighter rule stands: if a request
takes more than one tool call, send a short "looking into it" first, then
substantive updates at real milestones.

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
