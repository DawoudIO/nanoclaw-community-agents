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
│       ├── dev-metrics-report.md                 # scripted fetch, wakes only on notable change
│       ├── good-first-issue-health.md            # weekly, GFI-labeled onboarding funnel check
│       ├── repo-hygiene-audit.md                 # quarterly, community-profile completeness check
│       ├── posthog-weekly-review.md              # scripted fetch, wakes only on insight change
│       └── repo-mirror-sync.md                   # keeps local checkouts current, flags real changes
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
MIRROR_REPOS="owner/repo1 owner/repo2 owner/repo1.wiki"  # repo-mirror-sync;
                                                  # full repo map, not just
                                                  # triaged repos — falls back
                                                  # to COMMUNITY_REPOS if unset
POSTHOG_PROJECT_ID="12345"                       # posthog weekly review
POSTHOG_HOST="https://us.posthog.com"            # or https://eu.posthog.com
GFI_LABEL="good first issue"                     # optional — good-first-issue-health;
                                                  # only needed if your repo uses a
                                                  # different beginner-friendly label
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

**Schedules run in UTC** (the kit pins `TZ=UTC`) from each task's `schedule:`
cron. Tune them before stamping; afterwards, changing one means cancel and
recreate that task (`ncl tasks create --prompt … --recurrence …`) or edit the
template file and restamp. A per-group timezone override may exist in your
NanoClaw version — unverified, see UPSTREAM-ISSUES.md.

## Credentials: via OneCLI, not env vars

No API keys live in this template. The OneCLI gateway holds credentials in its
vault and injects them into outbound HTTPS calls at the proxy boundary.

| Service | API host to match | Auth style | Permissions needed | Where to get it |
|---|---|---|---|---|
| GitHub | `api.github.com` | `Authorization: Bearer` | **Fine-grained, read-only** — this agent never posts, so its token literally can't: Contents (read), Issues (read), Pull requests (read), all triaged repos. Add the **Dependabot alerts (read)** repository permission only if the security sweep is enabled. Never `read:org`, never any write scope, never a classic `repo`-scope PAT (that's inherently read/write). | github.com → Settings → Developer settings → Personal access tokens (fine-grained) |
| PostHog | `us.posthog.com` or `eu.posthog.com` | `Authorization: Bearer` | Personal API key, **read** scopes on insights/query only | PostHog → Settings → Personal API keys |

**Leave `GITHUB_PERSONAL_ACCESS_TOKEN: "placeholder"` in `mcp.json` as-is.** The
MCP server won't boot without the variable present; the real token is injected at
request time. Never replace it with a real value.

Least privilege is the point here: because the agent is designed never to write,
a read-only token both matches its job and removes the possibility of a
public-facing mistake even if an instruction slips through.

## Costs

All seven tasks are script-gated. `security-advisory-sweep`,
`github-ops-triage`, `repo-hygiene-audit`, and `repo-mirror-sync` wake the
model only when there's something new (or a fetch fails, which must be
surfaced); `good-first-issue-health` wakes weekly by design (its whole output
is the funnel state, whether or not it changed);
`dev-metrics-report` and `posthog-weekly-review` wake only when a number
actually moved, each with a heartbeat longer than its own cron so a fully
static stretch still proves life (7 days for the daily report, 28 for the
weekly review) — a quiet stretch costs a few API calls per run, not an agent
turn.
