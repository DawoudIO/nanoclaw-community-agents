# Triage rules

## Read the whole thing first

Read the full issue body — including markdown tables, collapsed sections, and
attached logs — before forming a view. The single most common triage failure is
asking for information the reporter already gave.

## What to flag

- **Likely duplicate** — link the existing open issue. Don't label or close;
  say why you think it's the same and let a human confirm.
- **Missing repro basics** — no steps, no version, no environment. Draft the
  question your lead can ask; don't leave the issue thin and hope.
- **Possibly a security issue** — stop and read `security-handling.md` before
  writing anything into a public-visible place.
- **Stale** — aging with no reply. List it; never close it. Staleness is a
  maintainer's call, not a rule you enforce.
- **PR ready but waiting** — no blocking review, no activity, looks mergeable.
  This is the highest-value thing you can surface, because it's usually just
  waiting on someone remembering it exists.

## What not to do

- Don't apply labels unless the project's label scheme is completely
  unambiguous and your lead has explicitly delegated it.
- Don't nudge a contributor yourself. "Are you still working on this?" reads
  very differently from a bot than from a maintainer.
- Don't rank issues by your own sense of importance and present it as the
  project's priority. Report state; let humans prioritize.

## Cross-repo currency

A project is usually more than one repo — product, docs, site, marketing —
possibly combined, possibly separate (see the repo map in your standing brief).
`COMMUNITY_REPOS` should list all of them; triage watches them all, and
**keeping every function's repo current is part of the job**:

- When a behavior-changing PR merges or a release ships in the product repo,
  check whether the docs or site describe the old behavior. If they do, draft
  a docs/site issue (what changed, which page, what it should say) and hand it
  to your lead — a release is not "done" while its docs issue is open.
- Stale-docs findings that surface any other way (a support answer exposed an
  outdated page, a screenshot no longer matches) get the same treatment:
  draft the issue immediately, while the discrepancy is concrete.
- Same discipline for the site and marketing repos: outdated version numbers,
  dead links, features described that changed — draft, hand off.
