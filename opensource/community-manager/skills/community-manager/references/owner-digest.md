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

Five parts, in this order, always. This is the format the owner confirmed —
"this is the TLDR that I need every AM" — after rejecting a terser version
that hid what had happened overnight.

**1. The verdict line.** First line, no exceptions. One of exactly three
words, then the single most important fact:

```
ALL CLEAR — 12 routine items, nothing needs you.
WATCHING  — csv-import asked 4 times this week, no docs page yet; one more week to confirm.
NEEDS YOU — PR #412 approved 34 days ago, still open.
```

The owner decides in one second whether to keep reading. `ALL CLEAR` means they
can stop — and it must be *safe* to stop, so never file something real under it.

**2. What each task did — one line per task that has something to share.**
Named, concrete, with the numbers and the item ids:

```
GitHub — replied first to 5 follow-up items on owner/repo: #10298, #8631, #8694, #9502, #9510. No security items, no degraded repos.
```

A task that ran and found nothing gets no line at all — the owner's words:
"identity integrity check is not important if there is nothing to share".
The verdict line carries "quiet". A task that did not run is not mentioned
either, unless it was supposed to (see "wiring problem" below).

**3. The GitHub items you touched — full lines for the top few, a light list
for the rest.** The owner reads these to know what went on while they were
asleep. Each line comes from the real issue or PR — read it, never infer
from the title:

```
#10298 — bug: Family/Person editors default to the first country when none is set. Assigned, milestone 7.8.0.
#8631 — feature request: ship a container image as a release asset. Open since April, no assignee.
Also touched: #8694 locale question · #9502 docs typo · #9510 reverse-proxy config, marked Stale — want details on any of these?
```

Full line = kind (bug / feature request / docs gap / question / PR), what
it is, state, and what you did (posted a workaround, asked for details,
welcomed a first-timer). Light list = number and three or four words. There
is no fixed count for either; the test is "could the owner read this on a
phone in a minute". If they ask for details on one, that is a normal
conversation — answer from the thread.

**4. Bugs you caught or fixed** in your own gates, prompts or config —
specifics, so the owner can carry them into the next restamp. "Found and
fixed: the hash gate compared against the wrong file; logged for restamp."

**5. Close on an explicit ending.** Either `Nothing needs your attention
right now.` or a short list of named actions, each with its item id.

## What the owner needs to know at 07:00 — in this order

Rank every candidate line by this list; the digest reads top-down in the
same order, and an empty section is simply absent.

1. **What needs them today.** A security report that arrived. A question you
   could not answer. A decision only a maintainer can make. A contributor
   waiting on a maintainer's review for a week or more. **A reply you posted
   but were not sure about** — name it and ask them to check; a wrong public
   answer in the project's voice is the costliest thing you can do, and the
   owner would rather read one "please check #412" than find it later.
2. **Whether you were blind overnight.** Usage window exhausted (and for how
   long), a repo you could not read, a task that should have run and did not.
   The owner must know when "quiet" might not be real.
3. **What their users will notice.** A release shipped or is close (milestone
   closed/open counts), a merged change that alters behaviour a user can see,
   the same question asked by several people this week.
4. **Who showed up.** New issues and PRs, one line each, and first-time
   contributors by name — a newcomer is the one thing a maintainer most wants
   to not miss.
5. **What you did in their name.** Replies, welcomes, requirement asks,
   workarounds posted, check-ins sent. Full lines for the notable ones, a
   light list for the rest, "want details?" at the end.
6. **What is coming due.** Workarounds awaiting a reply, PRs idling toward a
   check-in, anything you promised a user a maintainer would look at.

## Judgment, not aggregation

**What still gets dropped:** routine telemetry, repeated "ran, nothing"
entries beyond the one shared line, anything already reported yesterday and
unchanged, and queue plumbing. **What never gets dropped:** a GitHub item you
acted on (every one gets its FYI line), a bug you caught, anything degraded,
and anything that needs the owner.

If nothing in the batch did anything, the digest is two lines: the verdict
and the closing line.

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

**A backlog is not a chronological catch-up.** Merge the days: one line per
task covering the whole span, one FYI line per GitHub item (not per day it
was touched), and the current state of each. If something needed the owner
two days ago and still does, that is the verdict line.

## Length

Length follows what happened, but never a wall of text: a few full lines,
then a light list, then "want details?". A quiet night is two lines. Padding,
repetition and "nothing to report" lines are the failures — not the count.
