# Narrating script-computed data

## The required shape — verdict, exception, rollup

Every report you write opens with a verdict line so the reader can decide in
one second whether to keep reading. Exactly one of three words, then the
single most important fact:

```
ALL CLEAR — 3 repos, nothing needs you.
WATCHING  — unanswered issues up to 5 (was 2); oldest 12 days.
NEEDS YOU — PR #412 approved 34 days ago, still open.
```

Then, **only if there is one**, the exception: at most three items, most
important first, each answering *what changed* (with its comparison),
*what it means* — or plainly "unknown, needs a human" — and *what to do*.
More than three, say `+N more, same shape` instead of listing them.

Then everything else in **one** line: `12 other metrics steady.`

Never enumerate what didn't change. `ALL CLEAR — nothing needs you.` is a
complete and good report; it must also be *safe* to stop there, so never file
something real under it.

Why this shape: a maintainer who starts skimming has silently turned the
system off, and the fastest way to train that habit is a report that looks
identical whether or not anything happened. Full reasoning and a
before/after: `docs/REPORTING-STANDARD.md` in the template repo.

## Rules

The gate fetched and computed; you explain. Rules:

- **Lead with the exception, never the inventory.** Counts go last.
- **Never repeat silently.** A finding you already reported says so and dates
  itself — "still waiting, unchanged since the 3rd" — or it doesn't appear.
  The same item reported fresh five days running is how a channel dies.
- **Cost the inaction, don't just count it.** "5 issues never answered" plus
  one clause on why that matters beats three more numbers.

- **Every number carries its window and its delta.** "142 open issues" says
  little; "142 (+6 this week)" says something.
- **`null` means the fetch failed — say "unavailable", never zero.** Never
  compute a delta against a null. If the same field is null twice running,
  say so: that's a token or policy problem worth a human's attention.
- **Name what moved sharply, and don't explain it unless you checked.**
  "Downloads up 40% — cause unverified" is honest and useful. Inventing a
  reason is the most common way a narration task goes wrong.
- **A quiet run is one line.** "No notable movement since <date>." Never pad
  a report to look thorough; on a local model extra words are extra risk.
- **Don't reformat the skeleton.** Where a report format is specified, follow
  it exactly so the reader can compare week to week.
