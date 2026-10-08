# Report formats

Pre-packaged formats so every recurring report reads the same way regardless of
who ran it or when. Don't improvise a new layout per run.

## First decide WHERE a report goes — channel or owner

Most reports are **not for the owner at all.** They belong in the channel whose
readers care about them, and putting them in the owner's DM instead does double
damage: it buries them from the people who'd act on them, and it clutters the
one person this system exists to unburden.

Route by audience, not by which task produced it:

| Report | Destination | Cadence |
|---|---|---|
| Security reports | the security channel named in `channel-routing.md` **and** the owner DM — `escalation-paths.md` | when it fires — never batched |
| Release announcements (when the owner hands you one) | the announcements channel | when it fires |
| Docs gaps (`docs-gap-review`) | developer tier | its own schedule |
| **Escalations, decisions, system-broken, anything needing the owner** | **owner DM** | see the digest below |
| **Any process/fetch error** — a scripted task's gate reporting `fetch-failed`, an auth/token problem, a crash, or any other "this task itself is broken" condition | **owner DM — never a channel** | immediately, never batched into a digest |

**A report with a channel goes to that channel now, in full.** Do not queue it,
and never post the same content twice. Channel reports are the project talking
to its community; the digest is the system talking to its operator — different
audiences, different cadence.

**A process error is never channel content, even when it happens inside a task
whose successful output normally goes to a channel.** `docs-gap-review`'s
report goes to the developer channel — but if its gate reports
`status: fetch-failed`, that's not a docs finding, it's the system telling
the owner one of its own parts is broken, and it goes to the owner DM instead
of that channel. The distinction is what the message is ABOUT, not which task
produced it: a token that stopped working, a repo that 403s, an unhandled
crash are never something a channel's readers can act on — only the owner
can. Never post an error to the same channel a task's normal digest would use
"so people know why it's quiet" — quiet is not itself alarming, and a raw
error string in a public or team channel exposes internals (a repo name, a
stack trace, a token scope) that don't belong in front of that audience.

The owner is not cut out of channel reports, just not duplicated into: when a
channel report goes out, enqueue **one line** noting it happened (with a link
to the channel message where the platform supports it), so the daily TLDR can
say "docs-gap review posted, nothing needed" without restating it. The detail lives
where the people who act on it are.

Security is the exception in both directions: it goes to the security channel
**and** to the owner immediately, never batched — see `escalation-paths.md`.

## The digest queue — for OWNER-BOUND items only

**Do not relay owner-bound items as they arrive.** Your tasks fire on their
own schedules, and forwarding each one turns the owner's DM into a
notification stream.

This queue is **only** for what genuinely needs the owner: an escalation, a
decision, a system-broken finding, or a one-line note that a channel report
went out so the daily TLDR can mention it without repeating it. Everything with
a channel of its own is already delivered and does not belong here.

When something is owner-bound, append **one line** to
`plugin-data/community-manager/digest-queue.jsonl`:

```json
{"at": "2026-08-21T14:03:00Z", "source": "docs-gap-review", "severity": "info", "line": "docs-gap review posted to the developer channel, 2 candidates, nothing needed"}
```

- `at` — full ISO8601, not a bare date.
- `source` — the task that wrote it (`docs-gap-review`, `project-context`,
  …), or `self` from a conversation session.
- `severity` — `info` or `attention`. **Never `urgent`** (see below).
- `line` — one line. If you can't say it in one line, it probably belongs in
  a digest item, so write the one line and let
  `owner-tldr` decide.

The `owner-tldr` task turns the queue into a single daily TLDR. That task is
the **only** routine path to the owner.

### What bypasses the queue

Send immediately, and do **not** enqueue:

- Anything security- or abuse-shaped.
- An outage or credential failure that stops work now.
- Anything needing an owner decision before work can continue.
- A direct answer to something the owner asked you.

Everything else waits. If you find yourself wanting to send a routine finding
immediately because it feels important, that is exactly the judgment the
digest exists to make for you — enqueue it as `attention` and let the digest
rank it against everything else that day.

Queuing something as `urgent` is a contradiction: urgent things bypass the
queue. The gate reports any such entry as a process failure, because it means
the fast path didn't work when it should have.

### Why this also saves tokens, and why it survives a rate limit

Each relayed report is a model wake. Batching a day's reports into one digest
replaces roughly a dozen wakes with one — the largest single saving available
on the shared window, and it comes from removing work rather than degrading
it.

It is also **rate-limit-safe by construction**, which matters because the
window running out is exactly when you most want to know things. The gate is
bash and costs nothing, so it keeps running and keeps folding new entries into
the pending batch even while you have no budget to wake. The first digest
after the window reopens carries everything, labelled with how long it was
delayed. A usage limit delays the TLDR; it never loses it.

## Support conversation summary — batched daily, not per-conversation

After a support conversation in any support-tier channel resolves, do two
things:

**1. Append a topic row to the question ledger** (always, immediately):
one CSV row to `plugin-data/community-manager/question-ledger.csv`, with the
header `date,topic,channel` written only when you create the file:

```
2026-08-21T14:03:00Z,csv-import-fails,#support
```

Three rules, each load-bearing:
- **Full ISO8601 timestamps, never bare dates.** The gate compares dates as
  strings instead of parsing them, which works only because ISO8601 sorts
  lexicographically. A bare `2026-08-21` sorts before every timestamped row
  of that same day and silently falls outside windows it belongs in.
- **Reuse an existing slug** when the topic matches one you've logged before.
  `docs-gap-review` clusters these rows to find questions worth a docs page,
  and three differently-worded slugs for one question defeat it.
- **No commas in any field.** Kebab-case slugs and channel names have none
  naturally, and a comma would shift every field after it; replace one with
  `-` if it ever comes up.

**2. Summarize to the owner — as a daily batch, not a DM per conversation.**
A notification stream to the one person this system exists to unburden is a
failure mode, not a feature. Hold resolved-conversation summaries and send
one daily digest: a count line ("Handled N support conversations today:
<topic slugs>") plus the full four-line summary below **only** for
conversations that surfaced something — a docs gap, a probable bug, an
unhappy user, anything needing the owner's judgment. A routinely-handled
question appears as a slug in the count, nothing more.

```
**Support: <one-line topic>**
Who: <username/handle>
Channel: <channel>
Issue: <one or two sentences — what they were actually stuck on>
Resolution: <what fixed it, or "referred to GitHub issue #123">
GitHub: <issue URL, if one was created — omit the line if none>
```

Exception: anything security-shaped or urgent goes to the owner immediately
per `escalation-paths.md` — the batching rule is for routine wrap-ups only.

## Recurring channel reports (`docs-gap-review` and any task that posts on a schedule)

**One fixed name, always.** Every run of a recurring report posts under one
literal header — `Docs gap review`, say — never `Docs digest`, `Docs sweep`,
`Review — <date>`, or any other rewording. A reader scanning a busy channel
over weeks pattern-matches on the header; a title that drifts run to run
costs them re-reading it every single time, for zero information gain. Pick
the task's one name when you first write its prompt, then never vary it.

```
**<Report name> — <N> items, <M> need you**

<M items, each one line: what it is and why it needs a human, nothing more>
- csv-import-fails — asked 4 times in 2 weeks, no docs page covers it

<optional: one line naming what was skipped, if anything>
Skipped: <repo> (fetch truncated at 50, oldest updates not seen)

Routine, no action: <count> <category>, <count> <category>
```

If `M` is 0, stop after the header line — no "nothing needing action" essay
below it. If `N` is also 0, don't post at all; that cycle produced nothing a
reader benefits from seeing (this should already be the gate's own
`wakeAgent: false` outcome — a posted "0 items" message means the gate
fired when it shouldn't have, which is a bug in the task, not a report to
write around).

**State exceptions, not defaults.** Every one of these is true on almost
every run and costs a full sentence to restate as if it were news: "checked
against existing issue history, no duplicates," "nothing security-shaped,"
"no labelling gaps." Write NONE of them when they're true — their absence
IS the statement. Write the sentence only on the run where it's false: "#123
turned out to be a duplicate of #98, said so" or "#456 is security-shaped,
routed to the security channel and owner per policy." A reader who sees the
reassurance line every cycle stops reading it by the third repeat, so it
stops functioning as a check on the ones that matter.

**Batch routine noise into one count, never one bullet per item.** A
question already answered, a topic with one ask and no pattern, a bot PR —
none of these need a sentence identifying which specific item it was. "3
single-ask topics, 2 already covered by the docs — no action" is the whole
report for all five; five individual bullets saying the same "no action" is
not more informative, only longer.

**Only name a specific item when its judgment is what's being reported** —
a real docs gap, a security route, a stale question finally answered, a
genuine open question a reader should weigh in on.

If the full report exceeds Discord's ~2,000-character message limit, post it
as a downloadable `.md` attachment with the headline line in the message
body — never a multi-message wall, never silent truncation (see
`discord-mechanics.md`).

## Numbers always carry their window

Any report with a count states the time window and what changed since the
last one it's comparable to — a bare current count without a comparison point is
close to useless. "4 unanswered questions" says little; "4 unanswered
questions (was 1 last week)" says something.
