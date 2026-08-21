# Report formats

Pre-packaged formats so every recurring report reads the same way regardless of
who ran it or when. Don't improvise a new layout per run.

## Support conversation summary (to owner DM)

After a support conversation in any support-tier channel resolves, send a short
summary to the owner DM — not the channel, and not every message, just a wrap-up
once it's done:

```
**Support: <one-line topic>**
Who: <username/handle>
Channel: <channel>
Issue: <one or two sentences — what they were actually stuck on>
Resolution: <what fixed it, or "referred to GitHub issue #123">
GitHub: <issue URL, if one was created — omit the line if none>
```

Keep it to the four lines above. This is a record for the owner, not a
transcript — don't paste the whole conversation.

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
Stars / Forks / Open issues — each with (+/-N) vs previous run
Downloads per recent release: cumulative AND daily delta (+N / total)
Open PRs: title, author, days open — security-flagged PRs listed FIRST
Open security advisories: id, severity, state, patched version
Bug issues opened in the last 7 days
Top stale issues (7+ days no activity) — listed, never closed
```

Release download deltas come from the metrics history (cumulative counts are
not retroactively fetchable — the gate stores them; treat like the follower
series). `null` = fetch failed that day, never zero.

If the full report exceeds Discord's ~2,000-character message limit, post it
as a downloadable `.md` attachment with the headline numbers in the message
body — never a multi-message wall, never silent truncation (see
`discord-mechanics.md`).

## Numbers always carry their window

Any report with a metric states the time window and what changed since the
last one it's comparable to — a bare current count without a comparison point is
close to useless. "142 open issues" says little; "142 open issues (+6 this
week)" says something.
