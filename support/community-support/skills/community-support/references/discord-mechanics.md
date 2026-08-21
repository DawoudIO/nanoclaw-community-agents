# Discord mechanics

Platform-specific behaviors that are easy to get subtly wrong. These come from
real operating experience, not the platform's own docs.

## Clickable links need a card, not a URL

This was settled by months of trial and error, so don't relitigate it: a raw
URL renders as dead text through the bot, and inline markdown hypertext
(`[text](url)`) renders as the literal brackets — **the only reliably
clickable link is a card with an action button**. One card can carry several
buttons; keep button labels short ("Open issue", "View PR"). This applies to
every link in every channel — bug reports, PR notifications, releases, blog
posts, all of it.

- **Replying in-context** to a message you received: send the card as your
  reply — it lands in that channel automatically.
- **Posting proactively** (nothing prompted you — you're pushing a scheduled
  report or an announcement): a plain message to the channel first, then the
  card, in that order. Some platforms only let you attach a rich card in a
  follow-up turn once the channel context is established from the first post.

## Approval requests — preview cards, one decision each

Approvals are where sloppiness costs the most, and the field-tested shape is:

1. **Show exactly what will happen** — the approval message is a preview card
   carrying the verbatim content or action (the post text, the recipients,
   the thing being deleted), never a description of it. The owner approves
   what they can see, not what you summarized.
2. **One decision per card.** Never bundle two asks into one approval ("strip
   the bad line AND resume the schedule") — a real standoff started exactly
   that way. Two decisions = two cards.
3. **State the approve word** so there's no ambiguity about what counts:
   "reply 'post it' to publish."
4. **Per-mechanism variants** (matching the publishing mechanics in the
   marketing workflow):
   - *Execute-on-approval*: preview card → owner replies the approve word →
     you act → **confirm with the resulting URL**, always.
   - *Intent-URL*: the card's button IS the approval — one click opens the
     pre-filled composer under the owner's account; nothing for you to
     execute.
   - *Copy-paste*: a "post this:" card with the exact text block; the owner
     pastes it themselves.
5. **Approvals are instructions** — they get ledger ids like everything else
   (Ack #N when requested, #N done with the result URL when executed).
6. **Post-publish hygiene**: once published, close the loop — delete the
   consumed draft, close its PR, log the outcome.

Platform-level approvals (a OneCLI request-hold) arrive as their own yes/no
prompt to the owner — that's the gateway's flow, not yours; don't duplicate
it with a second ask.

## Platform rules — not house style, Discord's own policy

These come from Discord's Developer Policy and Terms of Service, not
preference. Breaking them risks the bot getting banned platform-wide, which
takes the whole system down with it.

**Must do:**
- **Real bot application only.** Never a personal user token doing
  automation ("self-botting") — against Discord's Terms for any account,
  official bot app only. If a deployment is ever wired to something other
  than a registered bot application, stop and flag it.
- **Least-privilege permissions at invite time.** Grant only what's needed
  (send messages, embed links, attach files, read message history) — not
  Administrator, not broad moderation permissions. Add scopes later if a
  real need appears; don't provision for hypothetical ones.
- **Respect rate limits.** If you ever call the Discord API directly rather
  than through the platform's own send path: honor `Retry-After` /
  `X-RateLimit-*` response headers, back off exponentially on a 429, queue
  rather than burst. Never hardcode a rate-limit number — Discord's are
  dynamic and per-route.
- **Acknowledge component interactions (buttons) within ~3 seconds** or defer
  — an approval card's button click that isn't acked promptly reads as
  broken to the user, even if the actual work takes longer.
- **Data minimization.** Ledgers and memory keep what the JOB needs (an
  instruction's gist, a public action's URL) — not a running profile of any
  community member, not full message logs kept longer than support
  continuity requires. Never retain more than the bot needs to function.

**Must not do:**
- **No `@everyone` / `@here` / mass mentions**, ever, for any reason — the
  platform treats this as spam-adjacent regardless of intent, and it's
  disruptive to every member of a channel for one bot's message.
- **No unsolicited DMs to community members** — you already only DM your
  owner and redirect everyone else to a public channel (see
  `additional_context/channel-routing.md`); this is that same rule stated as
  what it is: a Discord Terms requirement, not a house preference.
- **No engagement manipulation** — never inflate reactions, follower counts,
  or apparent activity; never auto-join servers via scraped invites; growth
  content earns real engagement or it doesn't count (see the growth
  playbook's participate-don't-broadcast rule for the same principle).
- **Don't treat every on-topic mention in a busy human-to-human conversation
  as a cue to jump in.** Auto-reply in support channels means answering real
  questions and requests directed at getting help — not interjecting into
  every message that happens to mention the project while people are talking
  to each other. When in doubt, that's what mention-only tiers are for.

**Scale note**: a bot in 100+ Discord servers needs Discord's own bot
verification, which scrutinizes any privileged intent (reading messages the
bot wasn't directly mentioned in — needed for auto-reply support channels).
Fine for a single project's deployment; worth knowing if this template set
is ever run for many communities at once.

## Trust a destination only after a round trip

Hard-won wiring lore: destinations created automatically from inbound
messages carry a real adapter session and work; **manually-created
destinations can silently accept messages and never deliver them.** So:

- After any wiring/destination change, restart may be required before it
  takes effect — then **verify by round trip** (send a test message, confirm
  it visibly arrived) before relying on it for reports or escalations.
- Prune dead destinations instead of leaving them listed — a plausible-
  looking dead destination is how a report vanishes into the void while
  everything reports success.
- Keep the wiring set minimal; redundant wirings cause double-handling and
  ambiguity about which one actually delivers.

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

## The 2,000-character limit — long content ships as a Markdown file

Discord caps messages at ~2,000 characters (free tier). Never handle long
content by splitting it into a wall of consecutive messages, and never
truncate it silently. Anything that won't comfortably fit (budget ~1,800
characters to be safe) — full reports, long digests, multi-section answers,
logs — gets written to a `.md` file and **attached as a downloadable file**,
with a 2–3 line summary in the message body so the reader knows whether to
open it. Markdown is the format because it survives being downloaded, read
anywhere, and pasted onward with structure intact. This composes with the
reporting rule: channel gets the full report (as an attachment when long),
owner DM gets the TLDR + card link either way.

## Files, not paths

If the person you're replying to has no access to your own workspace/filesystem,
attach the actual file to the message — don't reference a path they can't open.

## Bilingual replies

When a message isn't in the project's primary language, reply in the sender's
language first, then a short version in the primary language below a blank
line — so the rest of the channel, which may not share that language, can still
follow the thread.
