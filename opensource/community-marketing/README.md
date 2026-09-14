# Community Marketing Agent Template

A headless measurement sub-agent for an open-source project: it tracks how the
project's audience is growing — social follower counts and GA4 web traffic —
and reports the numbers to a lead agent. **Measuring is all it does.** It
writes no content and publishes nothing; posts, announcements and campaigns
are managed by the owner outside this system entirely.

Pairs with **`opensource/community-manager`** (the lead); its sibling is
**`opensource/community-coding`** (the Reviewer).

## Why it exists as its own agent

Two of the three things it owns are a different kind of data from everything
else in this set. Almost all agent state here is a rebuildable cache — lose it
and the next run recreates it. The follower series is not: Facebook, LinkedIn,
Instagram and YouTube each expose only the *current* count, so a day that goes
unrecorded can never be recovered by anyone, at any price. That makes "read the
number, write it down, never lose it" a real job with real consequences for
getting it wrong, and it is why this template's hard rules are about honest
nulls and append-only files rather than tone of voice.

## Why headless

It reports; the lead's single public voice is what the world hears. No publish
permission, no channel wiring, no second identity that an injected instruction
could try to post through. See the lead template's
`references/single-voice-relay.md`.

## Layout

```
community-marketing/
├── plugin.json
├── mcp.json                                    # GitHub MCP, placeholder token
├── setup-check.sh                              # mechanical "what isn't configured yet"
├── ai.nanoco.nanoclaw/
│   ├── context/
│   │   └── instructions.md                      # standing brief: measure, never write
│   └── tasks/                                   # created paused
│       ├── social-metrics-snapshot.md           # follower counts — the unrecoverable series
│       ├── weekly-analytics-report.md           # GA4 traffic, real windows and deltas
│       ├── ledger-publish.md                    # commits both series to the marketing repo
│       └── conversation-archive-prune.md        # pure housekeeping, never wakes the model
├── skills/
│   └── marketing-ops/
│       ├── SKILL.md
│       └── references/
│           ├── analytics.md
│           └── reporting-to-lead.md
└── README.md
```

Gate scripts are **not** authored here. They live in `scripts/tasks/marketing/*.sh`
(canonical, testable without an agent) and are injected into the task files by
`bash scripts/sync-tasks.sh`. Edit the `.sh`, never the `.md`.

## Stamp it

```bash
ncl groups create --template opensource/community-marketing --name "Community Marketing"
```

Wire it **to the lead agent only**:

```bash
ncl destinations add --agent-group-id <this-agent-id> --local-name parent --target-type agent --target-id <lead-agent-id>
ncl destinations add --agent-group-id <lead-agent-id> --local-name marketing-agent --target-type agent --target-id <this-agent-id>
```

No channel wiring for this group.

## Configure before resuming tasks

Config lives in one file —
`groups/<folder>/plugin-data/community-marketing/config.env` on the host
(`/workspace/agent/plugin-data/community-marketing/config.env` to the agent).
Edit it directly or message the stamped agent to write it:

```bash
# groups/<folder>/plugin-data/community-marketing/config.env
MARKETING_REPO="owner/marketing"    # ledger-publish: where the history series
                                    # are committed. Strongly recommended —
                                    # see the warning below.
GA4_PROPERTIES="123456789"          # optional — weekly-analytics-report.
                                    # One or more: "id" or "label:id,label:id"
LEDGER_BRANCH="agent-metrics"       # optional — the branch ledger-publish
                                    # writes to. Default shown; it is created
                                    # as an orphan branch, and the repo's
                                    # default branch is never touched.
```

Unset keys make each script exit clean (`wakeAgent: false, status:
"not-configured"`) rather than fail — an unconfigured task stays paused at no
cost.

> **`MARKETING_REPO` is the one worth not skipping.** Without it
> `ledger-publish` can't run, and the follower/traffic series live only inside
> this container. This system is meant to be rebuilt from the templates every
> few months, and nothing reimports container state — so leaving it unset means
> the trend line restarts at zero on every rebuild, permanently. Traffic
> numbers can be re-queried from GA4 inside its retention window; follower
> counts cannot be re-read from anywhere, ever.

Also fill in the **Your project** block in
`ai.nanoco.nanoclaw/context/instructions.md` (audience, social profile URLs) —
the agent reads its live targets from `project-config.md` relayed by the lead
at onboarding; the persona's bracketed defaults are placeholders, never real
config.

**Script dependencies:** `bash`, `curl`, `jq`, `git` in the container image —
verify with `ncl tasks run <task-id>` before resuming. **Cron lines are written
UTC-relative; the group's actual timezone decides the wall-clock fire
time** — `ncl groups config update --timezone <IANA id>` sets it live, no
recreate needed; unset, it defaults to the host machine's own timezone,
not UTC.

## Credentials: via OneCLI, not env vars

| Service | API host to match | Auth style | Permissions needed | Where to get it |
|---|---|---|---|---|
| GitHub (REST) | `api.github.com` | `Authorization: Bearer` | Fine-grained PAT scoped to the marketing repo only: Contents (read/write). Never a classic `repo` scope (that's account-wide), never admin. | Settings → Developer settings → Personal access tokens (fine-grained, single repo) |
| GitHub (git) | `github.com` | git credential | Push access to the marketing repo — `ledger-publish` pushes a branch. This is a **separate vault entry class** from the REST host above; wiring only `api.github.com` leaves the publish failing with `push-failed`. | same token, registered for the git host |
| Google Analytics 4 | `analyticsdata.googleapis.com` | OAuth bearer | **Viewer** on the property. `weekly-analytics-report` only ever calls `runReport` — a POST, but a read: it's a query verb that takes a JSON body. Do not enable `analyticsadmin.googleapis.com`; nothing here writes to GA4. | Google Cloud project → OAuth client, plus property access in GA4 admin |

**Leave `GITHUB_PERSONAL_ACCESS_TOKEN: "placeholder"` as-is** — the MCP server
needs the variable present; the real token is injected at request time.

**Social platform credentials are deliberately absent.** No Twitter/X,
LinkedIn, Facebook or Instagram credential is wired here, because this agent
reads public profile pages and posts nothing. There is no posting capability to
put an approval gate in front of, because there is no posting.

## Costs

Three of its four tasks are near-free. `ledger-publish` and
`conversation-archive-prune` are pure housekeeping that never wake the model on
success; `weekly-analytics-report` is a handful of GA4 queries on its schedule.
`social-metrics-snapshot` is the one **ungated** task here — the agent itself
has to open the profile pages, so it wakes every time it runs, by design. It
and the lead's `inbox-check` are the only two ungated wakes in the whole set.
