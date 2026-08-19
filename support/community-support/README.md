# Community Support Agent Template

The lead agent in a three-template set for running an open-source project's
community: answer users and contributors on Discord and GitHub as one consistent
identity, triage what comes in, and relay the work of two headless sub-agents —
while being the only thing in the system with a public voice.

**This set:**

| Template | Role | Public voice? |
|---|---|---|
| `support/community-support` (this one) | Lead: community replies, GitHub triage, escalation, relays sub-agents | **Yes — the only one** |
| `engineering/community-coding` | Issue/PR triage, security sweeps, dev metrics, telemetry | No |
| `marketing/community-marketing` | Content drafting, inbox triage, traffic analytics | No |

The lead works standalone. Add either sub-agent when you want that work done
without giving it a second identity.

## Why one voice

Every extra identity that can post publicly is another thing a reader has to
trust separately, and another seam an injected instruction can aim at — "reply as
the other bot," "don't mention a sub-agent did this." With exactly one public
identity, that whole class of attempt has nothing to attach to: the sub-agents
have no channel wiring to post through, so it fails structurally rather than
relying on an agent remembering a rule under pressure. Full reasoning in
`skills/community-support/references/single-voice-relay.md`.

## Layout

```
community-support/
├── plugin.json
├── mcp.json                                          # GitHub MCP, placeholder token
├── ai.nanoco.nanoclaw/
│   ├── context/
│   │   ├── instructions.md                            # standing brief
│   │   └── additional_context/
│   │       ├── channel-routing.md                     # the 3 audience tiers — FILL THIS IN
│   │       └── example-mapping.md                     # worked example, delete or replace
│   └── tasks/
│       ├── health-check.md                            # script-gated, wakes only on a problem
│       ├── workspace-backup.md                        # script-gated, wakes only on failure
│       ├── daily-github-triage.md                     # weekday digest, drafts only
│       └── weekly-identity-integrity-check.md         # asks before it ever locks anything
├── skills/
│   └── community-support/
│       ├── SKILL.md
│       └── references/
│           ├── single-voice-relay.md
│           ├── escalation-paths.md                    # FILL IN your security contact
│           ├── task-integrity.md
│           ├── discord-mechanics.md                   # cards, loops, bilingual replies
│           ├── github-bug-workflow.md                 # chat report → issue → label routing
│           └── report-formats.md                      # pre-packaged report layouts
└── README.md
```

## Channel tiers

`additional_context/channel-routing.md` sorts every wired channel into three
tiers and fixes the engage behavior per tier, so it isn't a per-message judgment:

| Tier | Who's there | Behavior |
|---|---|---|
| **Support** | Community members asking for help | **Auto-reply** — the agent jumps in on anything relevant |
| **Developer** | Contributors, maintainers, security | **Mention-only** — never volunteers into contributor discussion |
| **Team lead** | Marketers, admins, project leads | **Mention-only**, plus receives scheduled reports |

Fill in your real channel names before going live. `example-mapping.md` shows a
filled-in version from a real deployment.

## Full setup, from zero

```bash
# 1. Stamp the lead
ncl groups create --template support/community-support --name "Community Support"

# 2. Stamp whichever sub-agents you want
ncl groups create --template engineering/community-coding --name "Community Coding"
ncl groups create --template marketing/community-marketing --name "Community Marketing"

# 3. Wire sub-agents to the lead — agent-to-agent, NEVER to a channel
ncl destinations add --agent-group-id <coding-id>    --name parent    --target <lead-id>
ncl destinations add --agent-group-id <lead-id>      --name coding    --target <coding-id>
ncl destinations add --agent-group-id <marketing-id> --name parent    --target <lead-id>
ncl destinations add --agent-group-id <lead-id>      --name marketing --target <marketing-id>

# 4. Wire the LEAD (only) to your Discord channels and GitHub repos,
#    per your platform's channel management.

# 5. Connect credentials in OneCLI (tables below), then review and resume tasks
ncl tasks list --status paused
ncl tasks run <task-id>       # test scripted tasks first
ncl tasks resume <task-id>
```

Every task in all three templates is created **paused**. Read each one, fill in
the config its README lists, and resume deliberately — that's the
rebuild-cheaply property: the whole system is a stamp plus a handful of
`resume` calls, and tearing it down is deleting three groups.

**If you stamp the coding sub-agent, leave the lead's `daily-github-triage`
paused** — it exists for lead-standalone deployments, and the coding agent's
`github-ops-triage` covers the same ground at a higher cadence. Running both
double-reports.

### Workspace backup setup (optional)

`workspace-backup.md` silently skips until the workspace is a git repo with a
remote. To enable it, on the host (or by asking the agent):

```bash
cd groups/<folder>              # the agent sees this as /workspace/agent
git init
git remote add origin https://github.com/<you>/<agent-backup-repo>.git
git config user.name  "Agent Backup"
git config user.email "bot@yourproject.org"
```

Push auth is injected by the OneCLI proxy — the vault needs a GitHub secret
matched to host **`github.com`** (git traffic), which is separate from the
`api.github.com` match the REST calls use. Add a `.gitignore` for anything you
don't want in the backup (e.g. a `conversations/` directory).

**Script dependencies:** `bash`, `jq`, `git` (backup), and optionally `ncl`
(health-check's paused-count check degrades gracefully without it). Verify with
`ncl tasks run <task-id>` before resuming. Schedules fire in the group's
configured timezone — tune the cron lines to your day before stamping, or
cancel-and-recreate after.

## Credentials: via OneCLI, not env vars

No API keys live in any of these templates. The OneCLI gateway holds credentials
in its vault and injects them into outbound HTTPS calls at the proxy boundary, so
no token ever sits in `mcp.json`, the container env, or chat context.

| Service | API host to match | Auth style | Permissions needed | Where to get it |
|---|---|---|---|---|
| GitHub | `api.github.com` | `Authorization: Bearer` | `repo` (or `public_repo`) + `read:org`. This agent **does** post issue comments, so it needs write on issues — but never grant `admin:*` or `delete_repo`. | Settings → Developer settings → Personal access tokens |

**Leave `GITHUB_PERSONAL_ACCESS_TOKEN: "placeholder"` in `mcp.json` as-is.** The
MCP server won't boot without the variable present; the real token is injected at
request time. Never replace it with a real value.

**Discord is not a credential this template manages** — community messaging goes
through NanoClaw's own channel connector and wiring layer, configured in your
install, not through an MCP server here.

**Give each agent its own least-privilege token.** The coding sub-agent should
get a read-only GitHub token; the marketing sub-agent a token scoped to the
content repo only. Sharing one broad token across all three defeats the point of
splitting them.

**All three tokens match the same host (`api.github.com`), so use OneCLI's
`selective` secret mode** — in `all` mode, every agent whose requests match the
host gets whichever secret matches first, which collapses your three scoped
tokens back into shared access. Set each agent to selective and assign it only
its own secret:

```bash
onecli agents list                                              # find agent ids
onecli agents set-secret-mode --id <agent-id> --mode selective  # per agent
# then assign each agent its own GitHub secret in the OneCLI web UI
```

### Hard approval gates for sensitive actions

The standing instructions tell each agent what not to do, and that's guidance the
model follows — not enforcement. For anything you genuinely cannot allow, use
OneCLI's request-hold/approval rules, which gate the **outbound HTTP request**
(host + method + path) at the proxy, where no prompt can talk its way around it.
Configure those in the OneCLI web UI; NanoClaw's host side is already wired to
DM an approver for a yes/no.

Worth gating this way: anything that publishes, sends mail, or closes/merges on
GitHub.

## Fill in before going live

- `additional_context/channel-routing.md` — your real channel names per tier.
- `references/escalation-paths.md` — your private security-disclosure process and
  who counts as a maintainer.
- Any project-specific tone/glossary notes — add as another
  `additional_context/*.md` and reference it from `instructions.md`.
- Delete or replace `additional_context/example-mapping.md`.

## Testing locally

```bash
mkdir -p <nanoclaw-install>/templates/support
cp -R support/community-support <nanoclaw-install>/templates/support/
ncl groups create --template support/community-support --name "Test Support"
```

Re-copy after every edit — the stamp reads the install's `templates/`, not your
clone. Check the create response's `templateReport` for anything skipped.
