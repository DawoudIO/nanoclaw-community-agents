# Community Coding Agent Template

A headless GitHub/codebase-ops sub-agent for an open-source project: triage
issues and PRs, assess security advisories, compute dev metrics and review
telemetry — and hand all of it to a lead support agent rather than posting
publicly.

Pairs with **`support/community-support`** (the lead) and
**`marketing/community-marketing`** (the sibling). It works standalone, but the
single-public-voice design assumes a lead agent exists to relay through.

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
│   └── tasks/
│       ├── github-ops-triage.md                  # 4×/day, issue + PR triage digest
│       ├── security-advisory-sweep.md            # scripted gate: only wakes on new alerts
│       ├── dev-metrics-report.md                 # scripted fetch, agent narrates deltas
│       └── posthog-weekly-review.md              # scripted fetch, agent narrates telemetry
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

## Stamp it

```bash
ncl groups create --template engineering/community-coding --name "Community Coding"
```

Then wire it **to the lead agent only** — an agent-to-agent destination, not a
channel:

```bash
ncl destinations add --agent-group-id <this-agent-id> --name parent --target <lead-agent-id>
ncl destinations add --agent-group-id <lead-agent-id> --name coding --target <this-agent-id>
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
COMMUNITY_REPOS="owner/repo1 owner/repo2"        # advisory sweep + dev metrics
POSTHOG_PROJECT_ID="12345"                       # posthog weekly review
POSTHOG_HOST="https://us.posthog.com"            # or https://eu.posthog.com
```

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

**Schedules** fire in the group's configured timezone — set it at stamp time or
via group config. To change a schedule after stamping, cancel and recreate the
task (`ncl tasks create --prompt … --recurrence …`), or edit the template file
and restamp.

## Credentials: via OneCLI, not env vars

No API keys live in this template. The OneCLI gateway holds credentials in its
vault and injects them into outbound HTTPS calls at the proxy boundary.

| Service | API host to match | Auth style | Permissions needed | Where to get it |
|---|---|---|---|---|
| GitHub | `api.github.com` | `Authorization: Bearer` | **Read-only is enough** for triage and metrics: `repo` (or `public_repo` for public-only) + `read:org`. Add `security_events` **read** only if you want the Dependabot-alert sweep. Do **not** grant write/admin — this agent never posts. | github.com → Settings → Developer settings → Personal access tokens |
| PostHog | `us.posthog.com` or `eu.posthog.com` | `Authorization: Bearer` | Personal API key, **read** scopes on insights/query only | PostHog → Settings → Personal API keys |

**Leave `GITHUB_PERSONAL_ACCESS_TOKEN: "placeholder"` in `mcp.json` as-is.** The
MCP server won't boot without the variable present; the real token is injected at
request time. Never replace it with a real value.

Least privilege is the point here: because the agent is designed never to write,
a read-only token both matches its job and removes the possibility of a
public-facing mistake even if an instruction slips through.

## Costs

All four tasks are script-gated. `security-advisory-sweep` and
`github-ops-triage` wake the model only when there are new alerts or new/updated
items (or a fetch fails, which must be surfaced); `dev-metrics-report` wakes
daily by design to narrate the numbers; a quiet day on the other gates costs a
few API calls, not an agent turn.
