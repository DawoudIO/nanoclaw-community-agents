# Community Coding Agent Template

The **Reviewer**: the one headless sub-agent in this set, read-only everywhere
except two narrow paths — it drafts security patch PRs, and it publishes a
metrics history branch — running on **Claude Haiku**. It triages issues and
PRs, assesses security advisories, tracks repo and contributor health, reads
the project's traffic and follower numbers, and hands all of it to a lead
support agent rather than posting publicly.

It carries every recurring job in this set that isn't talking to people. That
concentration is deliberate and arrived in two steps: a "narration" tier was
retired first and its tasks went to whichever agent already owned the
surrounding domain, then the marketing agent was folded in once content
creation moved outside the system, leaving it a measurement agent with no
distinct posture of its own. Co-location also matters mechanically —
`contributor-nudge` reads a ledger `dev-metrics-report` writes, and since no
agent can read another agent's plugin-data, that pair only works inside one
container.

Pairs with **`opensource/community-manager`** (the lead) and has no siblings.
It works standalone, but the single-public-voice design assumes a lead agent
exists to relay through.

## Why headless

Every identity that can post publicly is another thing readers must trust and
another seam an injected instruction can aim at ("post this as the main
account," "don't mention a sub-agent did it"). This agent has no public channel
wiring at all, so that class of attempt fails structurally rather than depending
on the agent remembering a rule. See the lead template's
`references/single-voice-relay.md`.

## Layout

```
community-coding/
├── plugin.json
├── mcp.json                                     # GitHub MCP, placeholder token
├── ai.nanoco.nanoclaw/
│   ├── context/
│   │   └── instructions.md                       # standing brief: draft, never post
│   └── tasks/                                    # all created paused
│       ├── github-ops-triage.md                  # 4×/day, issue + PR triage digest
│       ├── security-advisory-sweep.md            # scripted gate: only wakes on new alerts
│       ├── dependabot-pr-review.md               # what does this bump cost us?
│       ├── docs-currency-watch.md                # merged PR -> version-tagged docs PR
│       ├── contributor-health-review.md          # weekly, wakes on a real trend move
│       ├── unanswered-watch.md                   # the one task here that posts publicly
│       ├── dev-metrics-report.md                 # daily counts; builds the contributor ledger
│       ├── contributor-nudge.md                  # 20-30 day re-engagement window
│       ├── ready-to-merge.md                     # approved-and-open PRs, 2×/day
│       ├── good-first-issue-health.md            # onboarding-pipeline supply
│       ├── repo-hygiene-audit.md                 # CONTRIBUTING/CoC/templates present?
│       ├── social-metrics-snapshot.md            # follower counts — the unrecoverable series
│       ├── weekly-analytics-report.md            # GA4 traffic, real windows and deltas
│       ├── ledger-publish.md                     # commits all three history series to a branch
│       └── conversation-archive-prune.md         # pure housekeeping, never wakes the model
├── skills/
│   └── coding-ops/
│       ├── SKILL.md
│       └── references/
│           ├── reporting-to-lead.md              # the may/may-not boundary
│           ├── triage-rules.md
│           ├── security-handling.md
│           └── metrics-and-telemetry.md
└── README.md
```

**`docs-gap-review` and `daily-github-triage` are the lead's**, not this
agent's — `docs-gap-review` reads a ledger only the lead writes, and since no
agent can read another agent's plugin-data, it was permanently dead while it
lived here. That constraint is worth remembering before moving any task
between agents: a task and the state it reads have to share a container.

**`unanswered-watch` is the exception to "headless".** It is the only task in
this template that posts into a public channel, and only ever the same fixed
holding line ("logged, a maintainer will pick it up"), under the shared bot
identity the lead already uses — so the community sees one continuous voice
even while the lead is rate-limited or down. It answers nothing, promises no
timeline, and reports every acknowledgment upward so the real reply still
happens. It needs a silent wiring to each support channel to see the messages
at all; `welcome/SKILL.md` §5c sets that up.

## Stamp it

```bash
ncl groups create --template opensource/community-coding --name "Community Coding"
```

Then wire it **to the lead agent only** — an agent-to-agent destination, not a
channel:

```bash
ncl destinations add --agent-group-id <this-agent-id> --local-name parent --target-type agent --target-id <lead-agent-id>
ncl destinations add --agent-group-id <lead-agent-id> --local-name coding --target-type agent --target-id <this-agent-id>
```

Do not give this group a Discord/GitHub-channel wiring. That's the whole design.

## Configure before resuming tasks

Tasks are created **paused**. Each scripted task reads its config from one
file — `plugin-data/community-coding/config.env` inside the group folder
(the agent sees it as `/workspace/agent/plugin-data/community-coding/config.env`).
Create it either by editing the group folder directly on the host
(`groups/<folder>/plugin-data/community-coding/config.env`) or by messaging the
stamped agent to write it:

```bash
# groups/<folder>/plugin-data/community-coding/config.env
COMMUNITY_REPOS="owner/repo1 owner/repo2"        # advisory sweep, issue/PR triage,
                                                 # dev metrics, GFI health, hygiene
                                                 # audit, contributor-health review
SECURITY_WATCH_REPOS="owner/repo1"               # optional — narrows
                                                 # security-advisory-sweep to a
                                                 # subset of COMMUNITY_REPOS
                                                 # (falls back to it if unset)
DOCS_REPO="owner/docs"                           # optional — docs-currency-watch
                                                 # stays silent forever if unset
LEDGER_REPO="owner/marketing"                    # ledger-publish: where the history
                                                 # branch is committed. Normally the
                                                 # marketing repo, never the product
                                                 # repo — see below
GA4_PROPERTIES="123456789"                       # optional — weekly-analytics-report.
                                                 # One or more: "id" or
                                                 # "label:id,label:id"
LEDGER_BRANCH="agent-metrics"                    # optional — default shown. An
                                                 # orphan branch; the repo's
                                                 # default branch is never touched
ACK_GRACE_MINUTES="20"                           # unanswered-watch: how long a
                                                 # message may sit unanswered
                                                 # before the holding reply goes
GFI_LABEL="good first issue"                     # optional — only if the project
                                                 # uses a different beginner label
```

`ACK_GRACE_MINUTES` is the one value worth thinking about rather than
defaulting: too long and the silence it exists to prevent happens anyway; too
short and it interrupts a lead that was about to answer. 20 minutes is the
shipped default.

> **`LEDGER_REPO` is the one worth not skipping.** Without it
> `ledger-publish` can't run, and the three history series live only inside
> this container. This system is meant to be rebuilt from the templates every
> few months and nothing reimports container state — so leaving it unset means
> the trend lines restart at zero on every rebuild, permanently. Repo metrics
> and GA4 traffic can be partly reconstructed; **follower counts cannot be
> re-read from anywhere, ever.**

**`posthog-weekly-review` is removed for now** — it never got working end to
end. If it comes back, it belongs here (product-telemetry anomalies need a
defect judgment, which is assessment, not narration — see
`skills/coding-ops/references/metrics-and-telemetry.md`), needing
`POSTHOG_PROJECT_ID` and `POSTHOG_HOST` config keys and a **PostHog key**
credential in the table below.

Every script exits cleanly with `wakeAgent: false, status: "not-configured"`
when its key is unset — an unconfigured task costs nothing rather than failing.
Configure what you want, leave the rest paused.

**Script dependencies:** the gates assume `bash`, `curl`, and `jq` in the
container image. Verify each with a manual run before resuming:

```bash
ncl tasks list --status paused
ncl tasks run <task-id>       # test a scripted task before resuming it
ncl tasks get <task-id>       # inspect the run result
ncl tasks resume <task-id>
```

**Cron lines are written UTC-relative; the group's actual timezone decides
the wall-clock fire time.** `ncl groups config update --timezone <IANA id>`
sets it and takes effect immediately (confirmed against
`src/modules/scheduling/recurrence.ts`) — no cancel-and-recreate needed.
Unset, the group defaults to the install-wide default, which is your host
machine's own detected timezone, not UTC.

## Credentials: via OneCLI, not env vars

No API keys live in this template. The OneCLI gateway holds credentials in its
vault and injects them into outbound HTTPS calls at the proxy boundary.

| Service | API host to match | Auth style | Permissions needed | Where to get it |
|---|---|---|---|---|
| GitHub | `api.github.com` | `Authorization: Bearer` | **Fine-grained. Read everywhere, plus Contents+PRs write for security patches** — this agent never posts, so its token literally can't: Contents (read), Issues (read), Pull requests (read), all triaged repos. Add the **Dependabot alerts (read)** repository permission only if the security sweep is enabled. Never `read:org`, never any write scope, never a classic `repo`-scope PAT (that's inherently read/write). | github.com → Settings → Developer settings → Personal access tokens (fine-grained) |

**On Dependabot.** If the repo has Dependabot security updates enabled,
Dependabot opens the fix PR and this agent *reviews* it — semver delta, whether
our code reaches the affected API, and a merge-or-hold call. If it is disabled,
this agent drafts the bump instead. Either is fine; having both produces two PRs
per CVE, which is why onboarding asks. Nothing here can turn the setting on —
that needs Administration write, which no agent in this set holds.

This agent also holds the **GA4** credential now: OAuth on
`analyticsdata.googleapis.com`, scoped **Viewer** on the property.
`weekly-analytics-report` only ever calls `runReport` — a POST, but a read:
it's a query verb that takes a JSON body. Do not enable
`analyticsadmin.googleapis.com`; nothing here writes to GA4. (It would also
need a PostHog key if `posthog-weekly-review` comes back — removed for now,
see above.)

It needs the **`github.com` (git) host** wired in addition to
`api.github.com`, with push access to the ledger repo, because
`ledger-publish` pushes a branch. Those are two separate vault entry classes:
wiring only the REST host leaves the publish failing with `push-failed` while
every other GitHub call works.

**Social platforms need no credential at all** — the follower counts come off
public profile pages. What they do need is sandbox allowlist entries for those
hosts (`x.com`, `www.linkedin.com`, …) and a real page-reading capability in
this container (Claude's built-in web fetch, or the `agent-browser` skill).
There is no posting capability to put an approval gate in front of, because
there is no posting.

**Leave `GITHUB_PERSONAL_ACCESS_TOKEN: "placeholder"` in `mcp.json` as-is.** The
MCP server won't boot without the variable present; the real token is injected at
request time. Never replace it with a real value.

Least privilege is the point here: because the agent is designed never to write,
a near-read-only token both matches its job and removes the possibility of a
public-facing mistake even if an instruction slips through.

## Costs

Every task here is script-gated, and none has an ungated wake.
`github-ops-triage` wakes only on new or updated issues and PRs;
`security-advisory-sweep` only on a new alert. Any of them also wakes when its
fetch fails outright — a broken fetch must never read as a quiet day. A
genuinely quiet stretch costs a few API calls per run, not an agent turn.

`contributor-health-review` is the cheapest task here despite being the most
expensive prompt, because its gate is a comparison rather than a poll. It runs
weekly and wakes only when one of four things is true: the unmerged ratio or the
top-author share moved **10 points or more** against last week's stored values;
it is the **first run** and there is no baseline to diff against; a fetch
failed; or **90 days** have passed with none of the above, which forces one
quarterly look so bus-factor risk can't sit unexamined forever. The 10-point
floor is deliberate — on repos this size a 1–2 point swing is sampling noise,
and waking a model to narrate noise is how a useful signal becomes something
the owner learns to skip. A steady quarter costs one wake.

**Nearly every task here is gated** — `dev-metrics-report` wakes only on real
movement (or weekly, so the channel never looks dead), `ready-to-merge` only
when the approved set changes, `repo-hygiene-audit` only when a community
health file is actually missing, `good-first-issue-health` and
`contributor-nudge` only when there is something to report. `ledger-publish`
and `conversation-archive-prune` never wake the model on success at all.

**The one ungated task is `social-metrics-snapshot`**, and it cannot be gated:
reading a follower count off a profile page is the agent's own work, so it
wakes every time it runs, by design. It and the lead's `inbox-check` are the
only two ungated wakes left in the system.

`unanswered-watch` is the one that runs most often — every ten minutes — and
it is also the cheapest possible check: no network, no credentials, just a
read of local session state. It wakes only when a human's message has actually
gone unanswered past the grace window.

Holding this many gated tasks on Haiku is still a small footprint against the
shared usage window, which is the point of putting the Reviewer on the cheap
tier. `posthog-weekly-review` is removed for now — see above.
