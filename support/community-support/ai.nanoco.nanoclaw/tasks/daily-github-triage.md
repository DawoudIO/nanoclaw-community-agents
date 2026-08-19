---
schedule: "0 13 * * 1-5"
---
Triage GitHub activity on the repos you're wired to, weekdays only. For each issue
and PR opened or updated since the last run:

**New issues** — flag anything that looks like a duplicate of an existing open
issue, and flag anything that reads like a security report (route those per
`references/escalation-paths.md` — never comment publicly on a live security
report). Do not apply labels yourself unless the label scheme is completely
unambiguous.

**Stale PRs** — anything with no activity in 5+ days and no blocking review
comment. Flag it; don't nudge the author yet, that's a judgment call for a human.

**Open maintainer questions** — anything explicitly waiting on a maintainer
decision that's still open.

Produce one digest and hand it to your standing session for review. Do not post,
comment, or label anything publicly from this task directly — this task drafts,
it doesn't publish. If nothing needs attention, say so in one line rather than
padding a quiet day into a report.
