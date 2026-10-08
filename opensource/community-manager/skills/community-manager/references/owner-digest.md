# Writing the owner's daily digest

Craft rules for `owner-tldr`. They live here rather than in the task prompt
because they are stable, they are long, and the prompt is paid on every wake
while this is read only when actually writing a digest.

The task prompt states the contract in three lines and points here. If you are
writing the digest, read this.

## Why it lands at 07:00 their local time

The owner is awake and can act on it. A digest that arrives at 3am is read at
7am anyway, having spent a wake to be early — so write it as a **morning brief
covering what happened since yesterday**, not an end-of-day wrap-up.

That framing changes the wording. "Overnight, two PRs were approved" reads
correctly at breakfast. "Today we handled…" does not.

## The shape

Three parts, in this order, always.

**1. The verdict line.** First line, no exceptions. One of exactly three
words, then the single most important fact:

```
ALL CLEAR — 12 routine items, nothing needs you.
WATCHING  — csv-import asked 4 times this week, no docs page yet; one more week to confirm.
NEEDS YOU — PR #412 approved 34 days ago, still open.
```

The owner decides in one second whether to keep reading. `ALL CLEAR` means they
can stop — and it must be *safe* to stop, so never file something real under it.

**2. The exception — at most three items.** Not three per agent; three total.
Each answers four questions in as few words as possible: what changed (with the
comparison, not the bare number), what it means — or explicitly "unknown, needs
a human" — what to do, and who. More than three, write `+4 more, same shape`
rather than listing them. A list of nine is a queue dump, not a report.

**3. Everything else — one line.** `12 other routine items, nothing changed.`
Never enumerate what didn't change; the queue has it.

## Judgment, not aggregation

**This is the one task where you are explicitly asked to drop things.** A
task reporting "nothing notable" fourteen times is fourteen queue entries and
zero digest lines.

If nothing in the batch needs the owner, the correct output is one line:
`ALL CLEAR — 12 routine items, nothing needs you.` A digest that lists
everything has failed at its only job.

Rank by **what happens if the owner never sees it**. A question still
unanswered after a day outranks a routine docs-gap note. A degraded fetch
outranks both, because it means we are blind rather than fine.

Never organise the digest by task. The owner does not care which task noticed
something; they care what needs them. `by_source` is grouped to help you read
the batch, not as an output template.

## A late digest

`deferred_runs > 0` means previous digests never reached the owner and this
batch is the accumulation — usually the usage window running out. The gate is
bash and costs nothing, so it kept folding new entries in; there was simply no
budget to wake. **Nothing was lost. It was delayed.**

Say so in one clause, up front: *"covering 3 days (digest was delayed by usage
limits)."* The owner needs to know the gap was a delay and not a quiet period,
because those look identical from outside and only one of them is fine.

**A backlog is not permission to write more.** A three-day batch gets the same
≤3 items and the same ~200 words — arguably fewer, since older routine entries
have aged into irrelevance. Prefer "the two things that still matter from the
last 3 days" over a chronological catch-up. If something needed the owner two
days ago and still does, that is the verdict line.

## Length

Under ~200 words for the whole digest. If it is longer, you are aggregating
rather than judging — go back and cut to the three that matter.
