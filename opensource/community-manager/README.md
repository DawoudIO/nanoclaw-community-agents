# Community Manager Agent Template

The manager agent in a two-template set for running an open-source project's
community: answer users and contributors on Discord and GitHub as one consistent
identity, triage what comes in, and relay the work of one headless sub-agent —
while being the only thing in the system with a **full** public voice.

**This set:**

| Template | Role | Public voice? |
|---|---|---|
| `opensource/community-manager` (this one) | Manager: community replies, GitHub triage, escalation, relays sub-agents | **Yes — the only full one** |
| `opensource/community-helper` | The Helper: issue/PR triage, security advisories, repo and contributor health, and every number the project tracks | Holding acknowledgments only |

The manager works standalone. Add the Helper when you want that work done
without giving it a second identity.

## Why one voice

Every extra identity that can post publicly is one more thing a reader has
to trust, and one more target for an injected instruction — "reply as the
other bot," "don't mention a sub-agent did this."

- **The Helper has no channel wiring**, except one case below — this class
  of attempt fails structurally, not by an agent remembering a rule under
  pressure.
- **The one exception is `unanswered-watch`.** It holds a channel wiring
  because a holding acknowledgment has to appear where the unanswered
  message is — but its scope is fixed tight:

  | Constraint | Value |
  |---|---|
  | Where it can post | Support channels only |
  | Identity it posts as | The manager's own bot — no reader sees a new party |
  | What it can say | One fixed line, never composed freely |

  What it posts is a receipt, never a resolution — every real answer is
  still only the manager's. Full reasoning in
  `skills/community-manager/references/single-voice-relay.md`.
- **That exception lives on a different agent on purpose:** an agent
  sharing the manager's usage window can't also be the thing that covers
  for that window running out.

## Layout

```
community-manager/
├── plugin.json
├── mcp.json                                          # GitHub MCP, placeholder token
├── setup-check.sh                                    # run via Bash: mechanical setup self-check
├── token-audit.sh                                    # run via Bash: zero-token usage/cost breakdown
├── ai.nanoco.nanoclaw/
│   ├── context/
│   │   ├── instructions.md                            # standing brief
│   │   └── additional_context/
│   │       ├── channel-routing.md                     # the 3 audience tiers — FILL THIS IN
│   │       └── example-mapping.md                     # worked example, delete or replace
│   └── tasks/                                         # 7 tasks, all created paused
│       ├── daily-github-triage.md                     # weekday digest, drafts only — standalone-mode fallback
│       ├── docs-gap-review.md                         # script-gated, proposes docs pages for repeat questions
│       ├── github-first-response.md      # every 10 min: new, unanswered
│       ├── owner-tldr.md                # the ONE daily digest to the owner
│       ├── inbox-check.md                             # 2×/day shared-inbox triage, read-and-draft only
│       ├── weekly-identity-integrity-check.md         # asks before it ever locks anything
│       └── conversation-archive-prune.md              # pure housekeeping, never wakes the model
├── skills/
│   ├── welcome/                               # first-contact onboarding interview (see below)
│   └── community-manager/
│       ├── SKILL.md
│       └── references/
│           ├── single-voice-relay.md
│           ├── escalation-paths.md                    # FILL IN your security contact
│           ├── task-integrity.md
│           ├── discord-mechanics.md                   # cards, loops, bilingual replies
│           ├── github-bug-workflow.md                 # chat report → issue → label routing
│           ├── inbox-triage.md                        # shared-inbox handling rules
│           └── report-formats.md                      # pre-packaged report layouts
└── README.md
```

`docs-gap-review` lives here for a mechanical reason worth remembering before
moving any task between agents: it reads `question-ledger.csv`, which only
the manager writes, and no agent can read another agent's plugin-data — so in the
Helper it was permanently dead. `daily-github-triage` likewise belongs to the
manager (see the note under *Full setup* about leaving it paused).

**There is no health-check or workspace-backup task in this set, by design.**
A health check that cannot fix what it finds, reporting via a heartbeat whose
*absence* is the alarm, needs a human to notice a silence — and a dead
container cannot report its own death anyway. A whole-workspace backup is a
write-only cost when nothing ever restores from it, which is the case here:
the system is rebuilt from the templates and nothing reimports container
state. What covers the real risk instead is narrower: `ledger-publish` (on the
Helper) commits the three series that genuinely cannot be rebuilt into a
branch of the project's repo.

## Channel tiers

`additional_context/channel-routing.md` sorts every wired channel into three
tiers and fixes the engage behavior per tier, so it isn't a per-message judgment:

| Tier | Who's there | Behavior |
|---|---|---|
| **Support** | Community members asking for help | **Auto-reply** — jumps in on real questions/requests; doesn't interject into cross-talk that merely mentions the project (see `channel-routing.md`) |
| **Developer** | Contributors, maintainers, security | **Mention-only** — never volunteers into contributor discussion |
| **Team lead** | Marketers, admins, project leads | **Mention-only**, plus receives scheduled reports |

Fill in your real channel names before going live. `example-mapping.md` shows a
filled-in version from a real deployment.

## Configuration is conversational — the `welcome` skill

On the owner's first DM, the `welcome` skill runs setup end to end:

1. Verifies the DM round trip.
2. Asks for the project's GitHub repo, scopes the goals, infers and confirms
   the rest.
3. Persists everything to `plugin-data/community-manager/`
   (`project-config.md` + `config.env` — the latter carries
   `COMMUNITY_REPOS` for the standalone triage gate).
4. Relays each stamped sub-agent's config into *its own* `config.env`.
5. Walks credential setup with real verification calls.
6. Gates task activation on your explicit go.

**Every FILL-THIS-IN marker in this template is an optional pre-stamp
default** — the conversational config in plugin-data always wins at
runtime.

The relay is not a convenience: an agent can only read
`plugin-data/<its-own-name>/`, so every key has to be written into the owning
agent's file — this is the one relay to get right:

| Sub-agent | Keys the manager relays |
|---|---|
| `opensource/community-helper` | `COMMUNITY_REPOS`, `ACK_GRACE_MINUTES`, `LEDGER_REPO`, `GA4_PROPERTIES` (+ optional `SECURITY_WATCH_REPOS`, `DOCS_REPO`, `GFI_LABEL`, `LEDGER_BRANCH`) |

There is only one relay now, and it carries nearly every key in the system —
the Helper owns most of the tasks (run `bash scripts/gen-task-table.sh --counts`
for the current split), so an unrelayed key here is the single largest source
of "stamped and never does anything."

This agent also owns its own `COMMUNITY_REPOS` plus an optional
`RELEASE_WATCH_REPOS`, which narrows the release-announcement skill to a
subset of it. `GITHUB_BOT_USERNAME` is set in both agents.

`inbox-check` is opt-in and off by default: its gate needs
**`INBOX_ENABLED="true"`** before it will fire at all, which is the right
default for the many projects with no shared inbox — unset, the task costs
nothing forever instead of reporting a permanent 401 twice a day. Optional:
`INBOX_QUERY` (default `is:unread newer_than:7d`), `INBOX_MAX_RESULTS`
(25), `INBOX_RETRY_HOURS` (24), `INBOX_MAX_RETRIES` (2). The gate hands over
**message IDs only** — never subjects, senders, or bodies: a shared inbox is
where vulnerability disclosures arrive, and every gate's JSON is mirrored to
a local telemetry log, so mail content there would persist to disk outside
the agent's context. The agent reads the mail itself through its email MCP.

**The manager keeps no copy of the metrics series.** The Helper owns those
files and publishes them itself — two ledgers of the same numbers in two
containers would drift apart, and then nobody knows which is right. The
manager reports the numbers it's handed and stores none of them.

**What the manager would still lose in a rebuild:**

| File | What it holds | Why it's not published |
|---|---|---|
| `question-ledger.csv` | Repeat-question ledger behind `docs-gap-review` | Contains community members' words |
| `owner-instructions.jsonl` | Ack ledger | Contains the owner's private direction |

Treat both as genuinely disposable: `docs-gap-review` simply starts
observing again after a rebuild, and the ack ledger only needs to
outlive a session, not a repave.

## Full setup, from zero

```bash
# 1. Stamp the manager
ncl groups create --template opensource/community-manager --name "Community Manager"

# 2. Run the setup interview on Haiku — it's Q&A and CLI calls, not judgment
#    work, and onboarding is long. Set it before you DM, together with the jq
#    install so both land in one restart (see docs/INSTALL.md §1).
ncl groups config update --id <manager-id> --model claude-haiku-4-5

# 3. Stamp the Helper, if you want its work done (stays on Haiku for good)
ncl groups create --template opensource/community-helper --name "Community Helper"

# 4. Wire it to the manager — agent-to-agent
ncl destinations add --agent-group-id <helper-id>    --local-name parent --target-type agent --target-id <manager-id>
ncl destinations add --agent-group-id <manager-id>      --local-name helper --target-type agent --target-id <helper-id>

# 5. Wire the MANAGER to your Discord channels and GitHub repos, per your
#    platform's channel management. The Helper additionally needs a SILENT
#    wiring to each support channel so unanswered-watch can see messages and
#    post its holding line — see welcome/SKILL.md 5c for the exact commands.

# 6. Connect credentials in OneCLI (tables below), then review and resume tasks
ncl tasks list --status paused
ncl tasks run <task-id>       # test scripted tasks first
ncl tasks resume <task-id>

# 7. The manager promotes ITSELF to Sonnet as the last act of the welcome
#    interview (welcome/SKILL.md §11) and restarts to apply it — expect one
#    short session drop, not a crash. These two lines are the manual
#    fallback only. BOTH are needed: config update just writes the row, the
#    restart is what applies it, or it reads Sonnet and still bills Haiku.
ncl groups config update --id <manager-id> --model claude-sonnet-5
ncl groups restart --id <manager-id>
```

Every task in both templates is created **paused**. Read each one, fill in
the config its README lists, and resume deliberately — that's the
rebuild-cheaply property: the whole system is a stamp plus a handful of
`resume` calls, and tearing it down is deleting two groups.

**If you stamp the Helper, leave the manager's `daily-github-triage`
paused.** `daily-github-triage` exists for manager-standalone deployments;
`github-ops-triage` covers the same ground at a higher cadence (every 6
hours versus a weekday digest). Running both double-reports every issue,
silently:

- They live in *different* agents now, so they don't share a cursor file.
- Each tracks "already reported" only in its own plugin-data.
- Neither can see that the other already reported an issue.

**There is no workspace backup anywhere in this set, by design.** See the note
under *Configuration* above: the only state worth preserving is published by
`ledger-publish` on the Helper, and everything else is meant to be rebuilt.

**Script dependencies:** `bash`, `curl`, `jq`, and `ncl`. Verify with `ncl
tasks run <task-id>` before resuming.
(`weekly-identity-integrity-check` reads `ncl tasks list --json` —
without `ncl`, its gate wakes the agent for a manual check instead of
failing.)

**Cron lines are written UTC-relative; the group's actual timezone decides
the wall-clock fire time.** `ncl groups config update --timezone <IANA id>`
sets it and takes effect immediately, before or after stamping — no
cancel-and-recreate needed (confirmed against
`src/modules/scheduling/recurrence.ts` and its test). Unset, the group
defaults to the install-wide default: your host machine's own detected
timezone, not UTC.

## Credentials: via OneCLI, not env vars

No API keys live in any of these templates. The OneCLI gateway holds credentials
in its vault and injects them into outbound HTTPS calls at the proxy boundary, so
no token ever sits in `mcp.json`, the container env, or chat context.

| Service | API host to match | Auth style | Permissions needed | Where to get it |
|---|---|---|---|---|
| GitHub | `api.github.com` | `Authorization: Bearer` | **Fine-grained**, scoped to `COMMUNITY_REPOS` — still needed here for `daily-github-triage` and the release-announcement skill: Issues read/write and Pull requests read/write (this agent *does* comment and file issues), Contents read, Metadata read. The ledger repo is **not** in this agent's scope; that write belongs to the Helper's token. Never `read:org`, `admin:*`, or `delete_repo`. Full per-endpoint justification in [PREREQS.md §1b](../../PREREQS.md). | Settings → Developer settings → Personal access tokens (fine-grained) |
| Shared inbox (e.g. Gmail) *(optional)* | `gmail.googleapis.com` | OAuth 2.0 Bearer | **Read-only** (`gmail.readonly`) for `inbox-check`. This agent never sends mail — the send is always a human's, so do not grant send or modify scopes. An inbox is a support channel, which is why it belongs to the agent that owns support escalation. | Google Cloud console → OAuth consent + credentials |

**Leave `GITHUB_PERSONAL_ACCESS_TOKEN: "placeholder"` in `mcp.json` as-is.** The
MCP server won't boot without the variable present; the real token is injected at
request time. Never replace it with a real value.

**Discord's bot token isn't something you add to the vault by hand** —
`/add-discord` registers it as part of wiring the bot, not through this
template's `mcp.json`. It still shows up in the OneCLI dashboard, though —
on a real deployment it lands in the **Custom** tab as a generic secret
(host `discord.com`, `Authorization` header), the same vault every other
credential here uses. That's NanoClaw's own internal plumbing for its
Discord adapter — not a step you perform yourself.

**Give each agent its own least-privilege token:**

| Agent | Token scope |
|---|---|
| Manager | Comments and files issues — the only one that does |
| Helper | Read-only across `COMMUNITY_REPOS`, plus Contents+PRs write for draft security patches and Contents write on the ledger repo |

Sharing one broad token across both defeats the point of splitting them.

**Both tokens match the same host (`api.github.com`), so use OneCLI's
`selective` secret mode** — in `all` mode, every agent whose requests match the
host gets whichever secret matches first, which collapses your scoped tokens
back into shared access. Set each agent to selective and assign it only its own
secret:

```bash
onecli agents list                                              # find agent ids
onecli agents set-secret-mode --id <agent-id> --mode selective  # per agent
# then assign each agent its own GitHub secret in the OneCLI web UI
```

### Hard approval gates for sensitive actions

Standing instructions tell each agent what not to do — that's guidance the
model follows, not enforcement. For anything you genuinely cannot allow,
use OneCLI's request-hold/approval rules instead: they gate the **outbound
HTTP request** itself (host + method + path) at the proxy, where no prompt
can talk its way around it.

Configure those in the OneCLI web UI. NanoClaw's host side is already wired
to deliver a real button card — not a chat reply — to an approver:
click-to-decide, not type-to-decide.

Worth gating this way: anything that publishes, sends mail, or closes/merges on
GitHub.

## Optional pre-stamp defaults (the welcome interview covers all of these)

- `additional_context/channel-routing.md` — your real channel names per tier.
- `references/escalation-paths.md` — your private security-disclosure process and
  who counts as a maintainer.
- Any project-specific tone/glossary notes — add as another
  `additional_context/*.md` and reference it from `instructions.md`.
- Delete or replace `additional_context/example-mapping.md`.

## Testing locally

```bash
mkdir -p <nanoclaw-install>/templates/support
cp -R opensource/community-manager <nanoclaw-install>/templates/support/
ncl groups create --template opensource/community-manager --name "Test Support"
```

Re-copy after every edit — the stamp reads the install's `templates/`, not your
clone. Check the create response's `templateReport` for anything skipped.
