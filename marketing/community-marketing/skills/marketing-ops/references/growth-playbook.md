# Growth playbook — open-source projects grow two populations

Growth for an open-source project means two distinct audiences, and they want
opposite content. **Which of these are goals — and their priority — is owner
config, asked at onboarding, never assumed** (check project-config; if the
goals aren't recorded, ask your lead before planning any content):

1. **Users / adopters** — people who would run the product. They respond to:
   how-tos and tutorials, feature highlights framed as benefits, "set it up in
   10 minutes" content, migration stories from whatever they use now, real
   user showcases, release announcements in plain language.
2. **Developers / contributors** — people who would improve the product. They
   respond to: architecture and how-we-built-it posts, good-first-issue
   spotlights, contributor recognition (by name, with their merged work),
   release deep-dives with the technical why, "help wanted" calls scoped
   small enough to actually start.

Every draft names its goal, audience, and platform in the PR body. Content
serving neither goal is decoration — flag it as such and let the owner decide.

## Platform fit — match the audience to where it actually is

Post the same idea differently per platform, or skip platforms where the
audience isn't. Typical mapping (confirm against the project's own platform
list in config):

| Platform | Audience it reaches | What works |
|---|---|---|
| Project blog | Both — the canonical home | Long-form how-tos (they're also SEO), release posts, contributor interviews. Everything else links back here |
| X | Developers mostly | Short, specific, one idea; threads for release deep-dives; link posts back to the blog |
| LinkedIn | Decision-makers / org users | Benefit-led, professional register, why-it-matters over how-it-works |
| Facebook / Instagram | Org users and their communities | Screenshots, human stories, event-shaped announcements |
| Reddit / HN / dev.to / lobste.rs | Developers | **Participate, don't broadcast** — these punish self-promotion; share only genuinely substantive posts, engage in comments, never astroturf |
| YouTube | Users | Setup walkthroughs and feature tours; evergreen |

## Growth loops that cost nothing (start here before any campaign)

- **Support → content**: every solved support thread is a how-to draft — the
  question was real, so the search demand is real. This is the highest-ROI
  content source the project has, and the lead's support summaries are the
  feed.
- **Docs-as-marketing**: a docs page that answers a searched question grows
  users while cutting support load. When the same question hits support twice,
  propose the docs page.
- **Contributor recognition**: crediting contributors by name in release notes
  and posts is the cheapest developer-growth lever that exists. Never ship a
  release announcement without the names.
- **Good-first-issue pipeline**: coordinate with the coding agent — well-scoped
  starter issues, kept fresh, spotlighted on developer platforms on a rhythm.
- **Showcase amplification**: when a community member shows what they built,
  ask permission and amplify it. User stories convert better than features.
- **Every published blog post gets an announcements post** (drafted for the
  lead to publish): link + one-line hook + an ask to share and give feedback.
  Publishing without telling the community is content without distribution.

## Measure what growth means

Tie reports to the goals: users → traffic to docs/downloads (GA4), follower
series; developers → **new contributors per month and first-time-contributor
PRs** (countable from the GitHub API — ask the coding agent to include it in
dev metrics). A campaign that moved neither number gets said plainly in the
report, not spun.

Two more developer-growth signals already come from the coding agent's own
tasks, not from anything marketing needs to build: `dev-metrics-report`'s
return-nudge (a first-time contributor 20-30 days in with no second
contribution yet — research shows this is the highest-leverage window for a
personal follow-up) and `good-first-issue-health`'s weekly funnel check
(open, unassigned, stale beginner-friendly issues — a starved GFI pipeline is
a quiet growth leak). If growth content ever needs a "help wanted" push,
check that report first rather than guessing which issues need visibility.
