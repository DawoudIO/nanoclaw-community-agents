# Community Marketing Agent Template

A headless marketing sub-agent for an open-source project: draft content through
a review-and-PR workflow, and hand every draft to a lead support agent instead
of publishing. **Drafting is all it does** — traffic analytics and follower
snapshots moved to `local/community-local`, which narrates pre-computed numbers
on a local model instead of spending a cloud turn on them.

> **This template is not stamped at install by default.** It is the deferred
> one: the lead, the local ops agent and the Reviewer cover the work a project
> needs on day one, and a drafting queue with nobody to review it is just
> another inbox. Stamp it when you actually want drafts — and if the host is
> memory-strained, leaving it unstamped is the recommended first lever.

Pairs with **`support/community-support`** (the lead); its siblings are
**`local/community-local`** and **`engineering/community-coding`**.

## Why headless

It drafts; a human approves; the lead agent's single public voice is what the
world hears. No publish permission, no channel wiring, no second identity that an
injected instruction could try to post through. See the lead template's
`references/single-voice-relay.md`.

## Layout

```
community-marketing/
├── plugin.json
├── mcp.json                                    # GitHub MCP (content repo PRs), placeholder token
├── ai.nanoco.nanoclaw/
│   ├── context/
│   │   └── instructions.md                      # standing brief: draft, never publish
│   └── tasks/                                   # 1 task, created paused
│       └── content-draft-cycle.md               # gated: wakes on a new release or weekly floor → draft → PR
├── skills/
│   └── marketing-ops/
│       ├── SKILL.md
│       └── references/
│           ├── content-workflow.md              # draft → PR → approve → publish
│           ├── analytics.md
│           ├── growth-playbook.md
│           └── reporting-to-lead.md
└── README.md
```

`social-metrics-snapshot`, `weekly-analytics-report` and `draft-cleanup` are now
`local/community-local` tasks. Each one is a script fetching numbers and an
agent saying what they mean in a sentence — the local model does that at no
subscription cost, and the follower series' durable copy still lives with the
lead either way.

## Stamp it

```bash
ncl groups create --template marketing/community-marketing --name "Community Marketing"
```

Wire it **to the lead agent only**:

```bash
ncl destinations add --agent-group-id <this-agent-id> --name parent --target <lead-agent-id>
ncl destinations add --agent-group-id <lead-agent-id> --name marketing --target <this-agent-id>
```

No channel wiring for this group.

## Configure before resuming the task

Its one scripted task reads one config file —
`groups/<folder>/plugin-data/community-marketing/config.env` on the host
(`/workspace/agent/plugin-data/community-marketing/config.env` to the agent).
Edit it directly or message the stamped agent to write it:

```bash
# groups/<folder>/plugin-data/community-marketing/config.env
CONTENT_REPO="owner/marketing"       # content-draft-cycle: where drafts and PRs land
RELEASE_WATCH_REPO="owner/product"   # optional — content-draft-cycle wakes on new
                                     # releases here (plus a weekly floor); unset =
                                     # weekly floor only
```

`GA4_PROPERTY_ID` is **no longer read here** — `weekly-analytics-report` is a
local-agent task, so that key belongs in
`plugin-data/community-local/config.env`. Setting it here does nothing.

`CONTENT_REPO`, on the other hand, is now needed in **both** files: this agent
uses it to open draft PRs, and the local agent uses it for `draft-cleanup`. Two
agents cannot share a config file — each reads only its own plugin-data — so the
same value has to be written twice. If cleanup stops reporting stale drafts, a
missing copy on the local side is the first thing to check.

Unset keys make the script exit clean (`wakeAgent: false, status:
"not-configured"`) rather than fail — leave an unconfigured task paused at no
cost. Also fill in the **Your project** block in
`ai.nanoco.nanoclaw/context/instructions.md` (content repo, brand
source) — the agent-owned task reads its targets from the live
`project-config.md` (relayed by the lead at onboarding) — the persona's
bracketed defaults are placeholders, never real config.

**Script dependencies:** `bash`, `curl`, `jq` in the container image — verify
with `ncl tasks run <task-id>` before resuming. **Schedules run in UTC** (the kit pins `TZ=UTC`); tune the `schedule:` cron
lines before stamping — see the lead template's README for why afterwards is
expensive.

## Credentials: via OneCLI, not env vars

| Service | API host to match | Auth style | Permissions needed | Where to get it |
|---|---|---|---|---|
| GitHub | `api.github.com` | `Authorization: Bearer` | **Fine-grained PAT scoped to the content repo only**: Contents (read/write) + Pull requests (read/write) — it commits drafts to branches and opens PRs, nothing else. Never a classic `repo` scope (that's account-wide), never admin, and don't reuse the coding agent's read-only token. | Settings → Developer settings → Personal access tokens (fine-grained, single repo) |

That is the only credential this agent needs. **No Google Analytics 4 access** —
it never calls GA4 any more; `weekly-analytics-report` and its Viewer-scoped
OAuth credential belong to `local/community-local`, so set that up in that
template instead.

**Leave `GITHUB_PERSONAL_ACCESS_TOKEN: "placeholder"` as-is** — the MCP server
needs the variable present; the real token is injected at request time.

**Social platforms are deliberately absent.** No Twitter/X, LinkedIn, Facebook,
or Instagram credential is wired here, because this agent doesn't publish. Posting
happens after human approval, by whoever holds those credentials. If you later
add a posting capability, put the approval gate in OneCLI (a hold-and-approve
rule on the outbound request) rather than trusting a prompt instruction — the
lead template's README explains that pattern.

## Costs

`content-draft-cycle` is the only task, and it is script-gated: it wakes on a
new release in `RELEASE_WATCH_REPO` or on its 7-day evergreen floor, whichever
comes first (a daily draft for a project with no daily news is just a review
queue pointed at the owner). Its cron runs on weekdays, but the gate is what
decides — in practice roughly four to six wakes a month.

**This agent has no ungated task**, so a quiet month costs a handful of API
calls and almost no agent turns. The two ungated wakes in the whole set belong
elsewhere: `inbox-check` (the lead) and `social-metrics-snapshot` (local).
