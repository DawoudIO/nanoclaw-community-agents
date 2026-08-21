# Report formats

Pre-packaged formats so every recurring report reads the same way regardless of
who ran it or when. Don't improvise a new layout per run.

## Support conversation summary — batched daily, not per-conversation

After a support conversation in any support-tier channel resolves, do two
things:

**1. Append a topic line to the question ledger** (always, immediately):
one JSON line to `plugin-data/community-support/question-ledger.jsonl` —
`{"date": "<full ISO8601 datetime, e.g. 2026-08-21T14:03:00Z>", "topic":
"<kebab-case-slug>", "channel": "<channel>"}`. Reuse an existing slug when
the topic matches one you've logged before — the `docs-gap-review` task
clusters these lines to find questions worth a docs page, and three
differently-worded slugs for the same question defeat it. Full timestamps,
not bare dates — the gate's date parsing requires them.

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

## Daily/weekly digest (from a scripted triage task)

```
**<Digest name> — <date>**

<One section per category that actually has something. Skip empty categories
entirely rather than writing "None" under each — a quiet day should look short,
not padded.>

**<Category>**
- <item> — <one-line why it matters>
```

If literally nothing needs attention, reply with one line saying so — never
expand a quiet day into a report that only exists to look thorough.

## Where reports go — full report to its channel, owner gets a TLDR

Every recurring report has a home channel by audience (dev reports → the
developer-tier channel, marketing/analytics → the team-lead channel, security
per `escalation-paths.md`). **The full report is posted there; the owner's DM
gets only a 2–3 bullet TLDR plus a card link to the channel message** — never
the full content twice. This keeps the owner DM scannable and puts the detail
where the audience that acts on it lives.

## Dev report skeleton (field-proven format)

```
📊 <Project> Dev Report — <date>

🟢 Ready to merge (approved, just waiting)
<PR #, title, author> — <link> — waiting Nd
(or: "none — nothing approved is sitting idle" if empty)

Stars / Forks / Open issues / Open PRs — each with (+/-N) vs previous run
Downloads per recent release: cumulative AND daily delta (+N / total)
Awaiting first response: N issues / N PRs never commented on (oldest: <date>)
Closed PRs (30d): merged vs. unmerged — ratio only if 5+ total
New contributors this week — named, not just counted
Return-nudge: <contributor> — first contribution <N>d ago, no second one yet
```

**"Ready to merge" leads the report, above the trend numbers** — see
`dev-metrics-report`'s own framing for why: a reviewed, approved PR sitting
unmerged means a contributor cleared every bar and nothing happened next,
which is worse than a slow first response. This is the one place per-PR
detail belongs directly in this report (unlike the items below), because
`dev-metrics-report` computes it itself, by number/title/author/link — it
isn't reconstructed from memory or duplicated from another task's output.

Every other line here comes from `dev-metrics-report`'s own script output —
nothing in this skeleton should ever be a number the agent had to guess or
reconstruct from memory. Release download deltas come from the metrics
history (cumulative counts are not retroactively fetchable — the gate stores
them; treat like the follower series). `null` = fetch failed that day, never
zero.

**Everything else per-PR/issue and security advisories are separate reports,
not extra lines bolted onto this one:**
- Narrative on *recently active* issues and PRs (duplicates, maintainer
  questions, security-shaped reports listed first) comes from the triage
  digest (`daily-github-triage`/`github-ops-triage`) — that's where per-item
  judgment already lives. Note the triage digest only sees items updated
  since its last run; it cannot see items that went quiet.
- Currently open security advisories are `security-advisory-sweep`'s job —
  it wakes the agent specifically when one needs judgment, which is a better
  signal than a static count sitting unread in a daily metrics message.
- The good-first-issue funnel — including *stale* beginner-friendly issues —
  is `good-first-issue-health`'s own weekly report, not a line here.
- There is deliberately **no general stale-issue sweep and no "bug issues
  opened this week" count**: no task computes them, so no report may claim
  them. The closest real signals are the awaiting-first-response backlog
  (this report) and the GFI staleness check (weekly). If the owner wants a
  broader stale-issue review, that's a task to propose, not a number to
  improvise.

Keep the dev report to what it's good at: the numbers (and the one
already-approved-PR list) that only make sense as a trend line.

If the full report exceeds Discord's ~2,000-character message limit, post it
as a downloadable `.md` attachment with the headline numbers in the message
body — never a multi-message wall, never silent truncation (see
`discord-mechanics.md`).

## Social follower report (from social-metrics-snapshot)

```
📈 Follower snapshot — <date>
<platform>: <count>  (WoW <+/-N>, MoM <+/-N or "not enough history yet">)
...
```

Same null-handling as any metric: a platform that failed to fetch this week
shows `null`, never last week's number repeated. MoM needs roughly a month of
prior snapshots (~5 weekly lines) before it means anything — until then, WoW
only, stated plainly rather than comparing against too short a baseline.

## Numbers always carry their window

Any report with a metric states the time window and what changed since the
last one it's comparable to — a bare current count without a comparison point is
close to useless. "142 open issues" says little; "142 open issues (+6 this
week)" says something.
