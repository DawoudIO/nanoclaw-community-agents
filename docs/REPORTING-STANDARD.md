# Reporting standard — how to not become noise

Every scheduled task in this set ends by writing something a human reads in a
channel. That is where the whole system succeeds or fails: a maintainer who
starts skimming these reports has effectively turned the system off, and
nobody will tell you when it happens.

This is the standard every report follows. It exists because the first draft
of these agents produced technically-correct reports that were **flat** — the
same shape every time, leading with inventory, never saying whether you
needed to care.

## The diagnosis

Six things make an automated report ignorable. Ours had all six.

1. **Uniform shape regardless of importance.** A week where nothing happened
   looked exactly like a week with a security finding. If the reader can't
   tell those apart at a glance, they stop glancing.
2. **Inventory first, exception last.** Reports opened with stars, forks, and
   counts, and buried the one actionable item in paragraph four.
3. **No verdict.** Nothing ever said "you can skip this." Every report
   demanded to be read in full to discover it didn't matter.
4. **Deltas with no threshold.** "Stars +12" is not information. Information
   is "stars +12, which is 4× the weekly norm" — or silence.
5. **Unlabelled repeats.** The same stale PR reported five days running,
   each time as if new. This is the fastest way to train a reader to ignore
   a channel.
6. **No action, no owner.** A finding with nobody named and nothing to do is
   a fact, not a report.

## The required shape

Three parts, in this order, always.

### 1. The verdict line — first line, no exceptions

One of exactly three words, then the single most important fact:

```
ALL CLEAR — 3 repos, nothing needs you.
WATCHING — unmerged-PR ratio up to 0.31 (was 0.18); one more week to confirm.
NEEDS YOU — PR #412 approved 34 days ago, still open.
```

The reader decides in one second whether to keep reading. `ALL CLEAR` means
they can stop, and it must be *safe* to stop — never bury something real
under it.

### 2. The exception — only if there is one

At most **three** items, most important first. Each one answers four
questions in as few words as possible:

- **What changed** (with the comparison, not the bare number)
- **What it means** — or explicitly "unknown, needs a human"
- **What to do** — one concrete action
- **Who** — the person or role, if it isn't the owner

If there are more than three, say so (`+4 more, same shape`) rather than
listing them. A list of nine is not a report, it's a queue dump.

### 3. Everything else — one line, rolled up

```
12 other metrics steady. Full numbers in the ledger.
```

Never enumerate what didn't change. The ledger has it if anyone wants it.

## The rules that keep it honest

**Thresholds, not deltas.** A number is only worth reporting if it crossed a
threshold stated *in advance*, in the gate script. If a task has no
threshold, it has no business waking anyone. Where the threshold is
arbitrary, say so once and pick a number — `contributor-health-review` uses
10 points, and says why.

**No number without a comparison.** "5 issues awaiting first response" is
noise. "5 awaiting first response, oldest 12 days, was 2 last week" is a
signal. If there is no prior value, say `baseline` and draw no conclusion.

**Cost the inaction, don't just count it.** The point of an unanswered issue
isn't the count, it's that response delay is the strongest predictor of
whether a contributor comes back. One clause of *why it matters* beats three
more numbers.

**Never repeat silently.** A finding already reported says so and dates
itself: *"still waiting, unchanged since the 3rd."* Better still, don't
re-report at all — resurface on a slower cadence. `ready-to-merge` wakes on
change and otherwise resurfaces weekly, so a month-old PR is mentioned about
four times rather than sixty.

**A quiet run is one line.** The strongest temptation in an automated report
is padding to look thorough. Resist it — extra
words are extra chances to be wrong. `ALL CLEAR — nothing needs you.` is a
complete, good report.

**Say "unavailable", never zero.** A failed fetch that reports `0` is worse
than no report: it corrupts the trend and reads as good news. Every gate here
returns `null` on failure for exactly this reason, and `degraded_repos` names
what couldn't be read.

**One action, one owner.** If nothing is actionable, the verdict line is
`ALL CLEAR` and the report is over.

**Say which you are doing: relaying a list, or making a call.** Some tasks
hand you a list the search already decided (`ready-to-merge`,
`good-first-issue-health`) and some hand you numbers that mean nothing until
someone interprets them (`contributor-health-review`). "Unmerged ratio moved
from 0.18 to 0.31" is a reading; "because contribution quality is dropping"
is a diagnosis — and if you have not actually checked, say the cause is
unverified rather than asserting it. A confident wrong diagnosis costs more
than an honest handoff.

## Before and after

A real `dev-metrics-report` output, and the same data under this standard:

**Before** — 140 words, no verdict, exception buried:

> Repository metrics for acme/crm. Stars: 937 (+12). Forks: 558 (+3). Open
> issues: 42 (+1). Open PRs: 7 (-1). Latest release v5.2.0 with 1000
> downloads. New contributors this week: none. Awaiting first response: 5
> issues, oldest since 2026-06-01, and 2 PRs. Closed PRs over 30 days: 20
> merged, 4 unmerged, ratio 0.17. Contribution concentration: 3 distinct
> authors over 90 days, top author "maintainer" at 67%, 2 candidates with 5+
> merged PRs. No degraded repos this run.

**After** — 45 words, verdict first, one action:

> **NEEDS YOU** — 5 issues have never had a reply; the oldest has been
> waiting 81 days.
>
> First response is the strongest predictor of whether someone comes back,
> and this is up from 2 last week. Suggest triaging the oldest three today.
>
> 8 other metrics steady (stars +12, forks +3). Full numbers in the ledger.

The second one is shorter, and it is the only one a busy maintainer will
actually act on. Note what happened to the concentration numbers: they moved
to `contributor-health-review` on the Reviewer, because they needed a
judgment that belongs in its own task — so they no longer dilute this report
at all.

## Reviewing the reports themselves

Once a month, ask of each recurring report: **has it caused an action since
last month?** A report that has never once changed what anyone did is not
neutral — it is training the channel to ignore the next one. Either raise its
threshold, slow its cadence, or pause it.

Keep count honestly. `bash scripts/gen-task-table.sh` lists every task and
its cadence; the ones to scrutinise first are the ones that fire most often.
