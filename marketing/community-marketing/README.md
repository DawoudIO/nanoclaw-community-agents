# Community Marketing Agent Template

A headless marketing sub-agent for an open-source project: draft content through
a review-and-PR workflow, triage the shared inbox, and narrate traffic
analytics — handing everything to a lead support agent instead of publishing.

Pairs with **`support/community-support`** (the lead) and
**`engineering/community-coding`** (the sibling).

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
│   └── tasks/
│       ├── inbox-check.md                       # 2×/day triage, read-and-draft only
│       ├── content-draft-cycle.md               # gated: wakes on a new release or weekly floor → draft → PR
│       ├── social-metrics-snapshot.md             # weekly follower counts — the one stateful asset (durable copy lives with the lead)
│       ├── weekly-analytics-report.md           # scripted GA4 fetch, agent narrates
│       └── draft-cleanup.md                     # scripted gate: only wakes on stale PRs
├── skills/
│   └── marketing-ops/
│       ├── SKILL.md
│       └── references/
│           ├── content-workflow.md              # draft → PR → approve → publish
│           ├── inbox-triage.md
│           ├── analytics.md
│           └── reporting-to-lead.md
└── README.md
```

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

## Configure before resuming tasks

Scripted tasks read one config file —
`groups/<folder>/plugin-data/community-marketing/config.env` on the host
(`/workspace/agent/plugin-data/community-marketing/config.env` to the agent).
Edit it directly or message the stamped agent to write it:

```bash
# groups/<folder>/plugin-data/community-marketing/config.env
GA4_PROPERTY_ID="123456789"          # weekly analytics report — your GA4 numeric property id
RELEASE_WATCH_REPO="owner/product"   # optional — content-draft-cycle wakes on new
                                     # releases here (plus a weekly floor); unset =
                                     # weekly floor only
CONTENT_REPO="owner/marketing"       # stale-draft cleanup
```

Unset keys make the script exit clean (`wakeAgent: false, status:
"not-configured"`) rather than fail — leave unconfigured tasks paused at no
cost. Also fill in the **Your project** block in
`ai.nanoco.nanoclaw/context/instructions.md` (content repo, brand source,
inbox) — the agent-owned tasks read their targets from the live
`project-config.md` (relayed by the lead at onboarding) — the persona's
bracketed defaults are placeholders, never real config.

**`inbox-check` needs an email tool this template does not ship.** No Gmail/
IMAP MCP server is bundled (which one is right depends on your provider).
Connect one — or your install's email channel — before resuming that task;
until then, leave it paused.

**Script dependencies:** `bash`, `curl`, `jq` in the container image — verify
with `ncl tasks run <task-id>` before resuming. **Schedules run in UTC** (the kit pins `TZ=UTC`); tune the `schedule:` cron
lines before stamping — see the lead template's README for why afterwards is
expensive.

## Credentials: via OneCLI, not env vars

| Service | API host to match | Auth style | Permissions needed | Where to get it |
|---|---|---|---|---|
| GitHub | `api.github.com` | `Authorization: Bearer` | **Fine-grained PAT scoped to the content repo only**: Contents (read/write) + Pull requests (read/write) — it commits drafts to branches and opens PRs, nothing else. Never a classic `repo` scope (that's account-wide), never admin, and don't reuse the coding agent's read-only token. | Settings → Developer settings → Personal access tokens (fine-grained, single repo) |
| Google Analytics 4 | `analyticsdata.googleapis.com` | OAuth 2.0 Bearer | **Viewer** on the GA4 property. Enable the *Google Analytics Data API* in the Cloud project. `analyticsadmin.googleapis.com` is **not** needed for reporting — don't enable it. | Google Cloud console → APIs & Services; property access in GA4 Admin |
| Shared inbox (e.g. Gmail) | `gmail.googleapis.com` | OAuth 2.0 Bearer | **Read-only** scope (`gmail.readonly`). This agent never sends — do not grant send or modify scopes. | Google Cloud console → OAuth consent + credentials |

**Leave `GITHUB_PERSONAL_ACCESS_TOKEN: "placeholder"` as-is** — the MCP server
needs the variable present; the real token is injected at request time.

**Social platforms are deliberately absent.** No Twitter/X, LinkedIn, Facebook,
or Instagram credential is wired here, because this agent doesn't publish. Posting
happens after human approval, by whoever holds those credentials. If you later
add a posting capability, put the approval gate in OneCLI (a hold-and-approve
rule on the outbound request) rather than trusting a prompt instruction — the
lead template's README explains that pattern.

## Costs

`weekly-analytics-report`, `draft-cleanup`, and `content-draft-cycle` are
script-gated: cleanup only wakes on newly-stale PRs, and content drafting only
wakes on a new release or its 7-day evergreen floor (a daily draft for a
project with no daily news is just a review queue pointed at the owner). The
agent-turn costs are `inbox-check` (2×/day) and `social-metrics-snapshot`
(weekly, ungated — it needs the browser/page reads).
