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

Every extra identity that can post publicly is another thing a reader has to
trust separately, and another seam an injected instruction can aim at — "reply as
the other bot," "don't mention a sub-agent did this."

The **Helper** (`opensource/community-helper`) has no channel wiring beyond
the one narrow case below, so that whole class of attempt has almost nothing to
attach to — it fails structurally rather than relying on an agent remembering a
rule under pressure.

The **Helper**'s `unanswered-watch` is the one deliberate exception, and it's
worth stating precisely rather than blurring: it *does* hold a channel wiring,
because a holding acknowledgment has to appear where the unanswered message is.
Its restriction is enforced by **scope** instead of by absence — the support
channels only, the same bot identity so no reader sees a new party, and a fixed
template it is forbidden to compose freely. What it posts is a receipt, never a
resolution. Every actual answer is still only ever the manager's. Full reasoning in
`skills/community-manager/references/single-voice-relay.md`.

The reason that exception lives on a *different* agent at all: an agent sharing
the manager's usage window cannot be the thing that covers for that window running
out.

## Layout

```
community-manager/
├── plugin.json
├── mcp.json                                          # GitHub MCP, placeholder token
├── ai.nanoco.nanoclaw/
│   ├── context/
│   │   ├── instructions.md                            # standing brief
│   │   └── additional_context/
│   │       ├── channel-routing.md                     # the 3 audience tiers — FILL THIS IN
│   │       └── example-mapping.md                     # worked example, delete or replace
│   └── tasks/                                         # 7 tasks, all created paused
│       ├── daily-github-triage.md                     # weekday digest, drafts only — standalone-mode fallback
│       ├── release-announcement-watch.md              # script-gated, posts new stable releases to announcements
│       ├── docs-gap-review.md                         # script-gated, proposes docs pages for repeat questions
│       ├── github-first-response.md      # every 10 min: new, unanswered
│       ├── owner-tldr.md                # the ONE daily digest to the owner
│       ├── inbox-check.md                             # 2×/day shared-inbox triage, read-and-draft only
│       └── weekly-identity-integrity-check.md         # asks before it ever locks anything
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
moving any task between agents: it reads `question-ledger.jsonl`, which only
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

On the owner's first DM, the `welcome` skill runs setup end to end: verifies
the DM round trip, asks for the project's GitHub repo, scopes the goals,
infers and confirms the rest, persists everything to
`plugin-data/community-manager/` (`project-config.md` + `config.env` — the
latter carries `COMMUNITY_REPOS` for the standalone triage gate), relays each
stamped sub-agent's config into *its own* `config.env`, walks credential setup
with real verification calls, and gates task activation on your explicit go.
**Every FILL-THIS-IN marker in this template is an optional pre-stamp default** —
the conversational config in plugin-data always wins at runtime.

The relay is not a convenience: an agent can only read
`plugin-data/<its-own-name>/`, so every key has to be written into the owning
agent's file, and there are three relays to get right:

| Sub-agent | Keys the manager relays |
|---|---|
| `opensource/community-helper` | `COMMUNITY_REPOS`, `ACK_GRACE_MINUTES`, `LEDGER_REPO`, `GA4_PROPERTIES` (+ optional `SECURITY_WATCH_REPOS`, `DOCS_REPO`, `GFI_LABEL`, `LEDGER_BRANCH`) |

There is only one relay now, and it carries nearly every key in the system —
the Helper owns most of the tasks (run `bash scripts/gen-task-table.sh --counts`
for the current split), so an unrelayed key here is the single largest source
of "stamped and never does anything."

This agent also owns its own `COMMUNITY_REPOS` plus an optional
`RELEASE_WATCH_REPOS`, which narrows `release-announcement-watch` to a subset
of it. `GITHUB_BOT_USERNAME` is set in both agents.

**The manager keeps no copy of the metrics series.** The Helper owns those
files and publishes them itself. Two ledgers of the same numbers in two
containers drift apart, and then nobody knows which is right — so the manager
reports the numbers it is handed and stores none of them.

**What the manager would still lose in a rebuild**: `question-ledger.jsonl` (the
repeat-question ledger behind `docs-gap-review`) and `owner-instructions.jsonl`
(the ack ledger). Neither is published anywhere, deliberately — both contain
community members' words and the owner's private direction, which don't belong
in a repo branch. Treat them as genuinely disposable: `docs-gap-review` simply
starts observing again after a rebuild, and the ack ledger only needs to
outlive a session, not a repave.

## Full setup, from zero

```bash
# 1. Stamp the manager
ncl groups create --template opensource/community-manager --name "Community Manager"

# 2. Stamp the Helper, if you want its work done
ncl groups create --template opensource/community-helper --name "Community Helper"

# 3. Wire it to the manager — agent-to-agent
ncl destinations add --agent-group-id <helper-id>    --local-name parent --target-type agent --target-id <manager-id>
ncl destinations add --agent-group-id <manager-id>      --local-name helper --target-type agent --target-id <helper-id>

# 4. Wire the MANAGER to your Discord channels and GitHub repos, per your
#    platform's channel management. The Helper additionally needs a SILENT
#    wiring to each support channel so unanswered-watch can see messages and
#    post its holding line — see welcome/SKILL.md 5c for the exact commands.

# 5. Connect credentials in OneCLI (tables below), then review and resume tasks
ncl tasks list --status paused
ncl tasks run <task-id>       # test scripted tasks first
ncl tasks resume <task-id>
```

Every task in both templates is created **paused**. Read each one, fill in
the config its README lists, and resume deliberately — that's the
rebuild-cheaply property: the whole system is a stamp plus a handful of
`resume` calls, and tearing it down is deleting two groups.

**If you stamp the Helper (`opensource/community-helper`), leave the manager's
`daily-github-triage` paused.** It exists for manager-standalone deployments, and
`github-ops-triage` covers the same ground at a higher cadence (every 6 hours
versus a weekday digest). The reason this matters more than it used to: the two
tasks now live in *different* agents, so they no longer share a cursor file —
each tracks "already reported" in its own plugin-data, and neither can see that
the other has already reported an issue. Running both double-reports, and
nothing in the system will notice.

**There is no workspace backup anywhere in this set, by design.** See the note
under *Configuration* above: the only state worth preserving is published by
`ledger-publish` on the Helper, and everything else is meant to be rebuilt.

**Script dependencies:** `bash`, `curl`, `jq`, and `ncl`
(`weekly-identity-integrity-check` reads `ncl tasks list --json`; without `ncl`
its gate wakes the agent for a manual check instead of failing). Verify with
`ncl tasks run <task-id>` before resuming. **Cron lines are written
UTC-relative; the group's actual timezone decides the wall-clock fire
time.** `ncl groups config update --timezone <IANA id>` sets it and takes
effect immediately (confirmed against
`src/modules/scheduling/recurrence.ts` and its test) — no
cancel-and-recreate needed, before or after stamping. Unset, the group
defaults to the install-wide default, which is your host machine's own
detected timezone, not UTC.

## Credentials: via OneCLI, not env vars

No API keys live in any of these templates. The OneCLI gateway holds credentials
in its vault and injects them into outbound HTTPS calls at the proxy boundary, so
no token ever sits in `mcp.json`, the container env, or chat context.

| Service | API host to match | Auth style | Permissions needed | Where to get it |
|---|---|---|---|---|
| GitHub | `api.github.com` | `Authorization: Bearer` | **Fine-grained**, scoped to `COMMUNITY_REPOS` — still needed here for `daily-github-triage` and `release-announcement-watch`: Issues read/write and Pull requests read/write (this agent *does* comment and file issues), Contents read, Metadata read. The ledger repo is **not** in this agent's scope; that write belongs to the Helper's token. Never `read:org`, `admin:*`, or `delete_repo`. Full per-endpoint justification in [PREREQS.md §1b](../../PREREQS.md). | Settings → Developer settings → Personal access tokens (fine-grained) |
| Shared inbox (e.g. Gmail) *(optional)* | `gmail.googleapis.com` | OAuth 2.0 Bearer | **Read-only** (`gmail.readonly`) for `inbox-check`. This agent never sends mail — the send is always a human's, so do not grant send or modify scopes. An inbox is a support channel, which is why it belongs to the agent that owns support escalation. | Google Cloud console → OAuth consent + credentials |

**Leave `GITHUB_PERSONAL_ACCESS_TOKEN: "placeholder"` in `mcp.json` as-is.** The
MCP server won't boot without the variable present; the real token is injected at
request time. Never replace it with a real value.

**Discord's bot token isn't something you add to the vault by hand** — `/add-discord`
registers it as part of wiring the bot, not through this template's `mcp.json`.
That said, don't be surprised to see it show up in the OneCLI dashboard anyway:
on a real deployment it lands in the **Custom** tab as a generic secret (host
`discord.com`, `Authorization` header), the same vault every other credential
here uses — that's NanoClaw's own internal plumbing for its Discord adapter,
not a step you perform yourself.

**Give each agent its own least-privilege token.** The manager's is the only one
that comments and files issues; the Helper's is read-only across
`COMMUNITY_REPOS` plus Contents+PRs write for draft security patches and
Contents write on the ledger repo. Sharing one broad token across both defeats
the point of splitting them.

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

The standing instructions tell each agent what not to do, and that's guidance the
model follows — not enforcement. For anything you genuinely cannot allow, use
OneCLI's request-hold/approval rules, which gate the **outbound HTTP request**
(host + method + path) at the proxy, where no prompt can talk its way around it.
Configure those in the OneCLI web UI; NanoClaw's host side is already wired to
deliver a real button card (not a chat reply) to an approver — click-to-decide,
not type-to-decide.

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
