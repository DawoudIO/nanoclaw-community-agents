# Report formats

Pre-packaged formats so every recurring report reads the same way regardless of
who ran it or when. Don't improvise a new layout per run.

## First decide WHERE a report goes — channel or owner

Most reports are **not for the owner at all.** They belong in the channel whose
readers care about them, and putting them in the owner's DM instead does double
damage: it buries them from the people who'd act on them, and it clutters the
one person this system exists to unburden.

Route by audience, not by which agent produced it:

| Report | Destination | Cadence |
|---|---|---|
| Dev metrics + contributor health (`project-health`, dev post) | developer tier (`#dev-*`) | weekly, on `project-health`'s post day |
| Security advisories | the security channel named in `channel-routing.md` | when it fires — never batched |
| Release announcements, published content | the announcements channel | when it fires |
| Traffic/analytics + follower counts (`project-health`, team-lead post), content drafts | team-lead tier | weekly, same post day — one message |
| Repo hygiene, docs gaps | developer tier | its own schedule |
| **Escalations, decisions, system-broken, anything needing the owner** | **owner DM** | see the digest below |
| **Any process/fetch error** — a scripted task's gate reporting `fetch-failed`, an auth/token problem, a crash, or any other "this task itself is broken" condition | **owner DM — never a channel** | immediately, never batched into a digest |

**A report with a channel goes to that channel now, in full.** Do not queue it,
and never post the same content twice. Channel reports are the project talking
to its community; the digest is the system talking to its operator — different
audiences, different cadence.

**A process error is never channel content, even when it happens inside a task
whose successful output normally goes to a channel.** `github-ops-triage`'s
digest goes to the developer channel — but if its gate reports
`status: fetch-failed`, that's not a triage finding, it's the system telling
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
say "dev report posted, nothing needed" without restating it. The detail lives
where the people who act on it are.

Security is the exception in both directions: it goes to the security channel
**and** to the owner immediately, never batched — see `escalation-paths.md`.

## The digest queue — for OWNER-BOUND items only

**Do not relay owner-bound items as they arrive.** Twenty-six tasks fire on
their own schedules, and forwarding each one turns the owner's DM into a
notification stream.

This queue is **only** for what genuinely needs the owner: an escalation, a
decision, a system-broken finding, or a one-line note that a channel report
went out so the daily TLDR can mention it without repeating it. Everything with
a channel of its own is already delivered and does not belong here.

When something is owner-bound, append **one line** to
`plugin-data/community-manager/digest-queue.jsonl`:

```json
{"at": "2026-08-21T14:03:00Z", "source": "local", "severity": "info", "line": "mirror sync: docs repo, 3 commits, nothing notable"}
```

- `at` — full ISO8601, not a bare date.
- `source` — the reporting agent: `helper`, or
  `self` for your own findings.
- `severity` — `info` or `attention`. **Never `urgent`** (see below).
- `line` — one line. If you can't say it in one line, it probably belongs in
  the ≤3 items the digest will carry, so write the one line and let
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

## Daily/weekly digest (from a scripted triage task)

**One fixed name, always.** Every run of `github-ops-triage` posts under the
literal string `GitHub triage` — never `Triage digest`, `Triage sweep`,
`Digest — <date>`, or any other rewording. A reader scanning a busy channel
over weeks pattern-matches on the header; a title that drifts run to run
costs them re-reading it every single time, for zero information gain. Same
rule for every other scripted-triage task — pick the task's one name when you
first write its prompt, then never vary it.

```
**GitHub triage — <N> items, <M> need you**

<M items, each one line: what it is and why it needs a human, nothing more>
- #1234 — <reporter> disputes <maintainer>'s fix; still open after 2 replies

<optional: one line naming what was skipped, if anything>
Skipped: <repo> (fetch truncated at 50, oldest updates not seen)

Routine, no action: <count> owner PRs, <count> dependabot/locale-bot, <count> already answered by first-response
```

If `M` is 0, stop after the header line — no "nothing needing action" essay
below it. If `N` is also 0, don't post at all; that cycle produced nothing a
reader benefits from seeing (this should already be the gate's own
`wakeAgent: false` outcome — a posted "0 items" message means the gate
fired when it shouldn't have, which is a bug in the task, not a digest to
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
dependabot bump, a locale-sync bot PR, a PR that only got automated-review
commentary, an issue that's the repo owner's own work — none of these need
a sentence identifying which specific PR number it was. "3 dependabot
bumps, 2 locale PRs, 1 owner-authored issue — no action" is the whole
report for all six; six individual bullets saying the same "no action" is
not more informative, only longer.

**Only name a specific item when its judgment is what's being reported** —
a real duplicate close, a security route, a stale item finally answered, a
genuine open question a reader should weigh in on. If first-response
already gave an item a thorough reply and nothing about that reply needs a
second look, it belongs in the routine count, not a named bullet — "already
answered by first-response" is itself a category, not a reason to narrate
each one.

## Dev report skeleton (field-proven format)

```
📊 <Project> Dev Report — <date>

Stars / Forks / Open issues / Open PRs — each with (+/-N) WoW and MoM from the daily rows
Downloads for the latest release: cumulative AND weekly delta (+N / total)
Awaiting first response: N issues never commented on (oldest: <date>)
Closed PRs (30d): merged vs. unmerged — ratio only if 5+ total
Contributor concentration: top author N% of M distinct authors (90d) — a finding only when M is large
New contributors this week — named, not just counted
Return-nudge: <contributor> — first contribution <N>d ago, no second one yet
```

This is what `project-health` posts on its weekly post day, from
`metrics-history.csv` plus that run's script output — nothing in this
skeleton should ever be a number the agent had to guess or reconstruct from
memory. Release download deltas come from the metrics history (cumulative
counts are not retroactively fetchable — the gate stores them; treat like the
follower series). `null` = fetch failed that day, never zero. Deltas are
labelled by real elapsed time, same rule as the follower report below.

**Everything per-PR/issue and security advisories are separate reports, not
extra lines bolted onto this one:**
- Narrative on *recently active* issues and PRs (duplicates, maintainer
  questions, security-shaped reports listed first) comes from the Helper's
  weekly `github-ops-triage` digest — that's where per-item judgment already
  lives. Note the triage digest only sees items updated since its last run;
  it cannot see items that went quiet.
- Currently open security advisories are `security-advisory-sweep`'s job —
  it wakes the agent specifically when one needs judgment, which is a better
  signal than a static count sitting unread in a metrics message.
- Approved-but-unmerged PRs, the good-first-issue funnel (including *stale*
  beginner-friendly issues) and missing community-health files are the
  **`repo-health` skill in the project repo** — point-in-time checks run on
  demand, not lines here. If asked, say exactly that: "that's a repo-health
  skill check, run it in the repo."
- There is deliberately **no general stale-issue sweep and no "bug issues
  opened this week" count**: no task computes them, so no report may claim
  them. The closest real signal is the awaiting-first-response backlog (this
  report). If the owner wants a broader stale-issue review, that's a task to
  propose, not a number to improvise.

Keep the dev report to what it's good at: the numbers that only make sense
as a trend line.

If the full report exceeds Discord's ~2,000-character message limit, post it
as a downloadable `.md` attachment with the headline numbers in the message
body — never a multi-message wall, never silent truncation (see
`discord-mechanics.md`).

## Social follower report (`project-health`, team-lead post)

**Send this in the same weekly message as the GA4 traffic report, not as a
second, separate one** — both are team-lead-tier, both come out of the same
`project-health` post-day run (see the routing table above), and a maintainer
reading one wants the other right next to it, not in a different message five
minutes apart.

```
📈 Follower snapshot — <date>
<platform>: <count>  (vs <N days> ago: <+/-N>, vs <~28-30 days> ago: <+/-N or "not enough history yet">)
...

Fastest-growing recently: <platform> (<+N> over <window>) — <one clause of
context if you have it, e.g. "the week the LinkedIn push went out">
```

**Label every delta by its actual elapsed time, never a fixed "WoW"/"MoM"
assumption** — the comparison row is whichever daily row is nearest, and printing
"WoW" on what's actually a 1-day delta is a real, observed mislabeling bug
(the numbers were fine, the label lied about the window). Only call
something "WoW"/"MoM" when the comparison line genuinely is ~7 or ~28-30
days back; otherwise say "vs N days ago" plainly.

Same null-handling as any metric: a platform that failed to fetch this
period shows `null`, never the prior number repeated. The longer-window
comparison needs enough history to mean anything (~a month's worth of
lines, whatever the actual cadence) — until then, the short-window
comparison only, stated plainly rather than comparing against too short a
baseline.

**Composition over any single delta, same as the GA4 report**: the
cross-platform comparison (which platform is actually growing vs. flat,
total reach across all of them) is worth more than any one platform's
isolated WoW number — manager with that, not with a per-platform list nobody
can compare at a glance. Where a spike lines up with a release or a
marketing push you can actually verify (not guess), say so — same rule as
GA4's own correlate-with-release-dates guidance, not a formal attribution
model.

## Numbers always carry their window

Any report with a metric states the time window and what changed since the
last one it's comparable to — a bare current count without a comparison point is
close to useless. "142 open issues" says little; "142 open issues (+6 this
week)" says something.
