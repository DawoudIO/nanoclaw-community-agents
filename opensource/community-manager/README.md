# Community Manager Agent Template

The lead agent in a three-template set for running an open-source project's
community: answer users and contributors on Discord and GitHub as one consistent
identity, triage what comes in, and relay the work of two headless sub-agents —
while being the only thing in the system with a **full** public voice.

**This set:**

| Template | Role | Public voice? |
|---|---|---|
| `opensource/community-manager` (this one) | Lead: community replies, GitHub triage, escalation, relays sub-agents | **Yes — the only full one** |
| `opensource/community-coding` | The Reviewer: issue/PR triage, security advisories, repo and contributor health | Holding acknowledgments only |
| `opensource/community-marketing` | Measurement: follower counts and web traffic. Writes no content | No |

The lead works standalone. Add either sub-agent when you want that work done
without giving it a second identity.

## Why one voice

Every extra identity that can post publicly is another thing a reader has to
trust separately, and another seam an injected instruction can aim at — "reply as
the other bot," "don't mention a sub-agent did this."

For the **Reviewer** (`opensource/community-coding`) and **Marketing**
(`opensource/community-marketing`), that whole class of attempt has nothing to
attach to: neither has any channel wiring, so it fails structurally rather than
relying on an agent remembering a rule under pressure.

The **Reviewer**'s `unanswered-watch` is the one deliberate exception, and it's
worth stating precisely rather than blurring: it *does* hold a channel wiring,
because a holding acknowledgment has to appear where the unanswered message is.
Its restriction is enforced by **scope** instead of by absence — the support
channels only, the same bot identity so no reader sees a new party, and a fixed
template it is forbidden to compose freely. What it posts is a receipt, never a
resolution. Every actual answer is still only ever the lead's. Full reasoning in
`skills/community-manager/references/single-voice-relay.md`.

The reason that exception lives on a *different* agent at all: an agent sharing
the lead's usage window cannot be the thing that covers for that window running
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
the lead writes, and no agent can read another agent's plugin-data — so in the
Reviewer it was permanently dead. `daily-github-triage` likewise belongs to the
lead (see the note under *Full setup* about leaving it paused).

`health-check` and `workspace-backup` used to live in this set and are now
**gone entirely**, not moved. The health check could never fix anything it
found, and its "the system is alive" signal was a weekly heartbeat whose
*absence* the owner had to notice — a dead container cannot report its own
death. The backup wrote a daily copy of a container's workspace that nothing
ever read back: this set is rebuilt from the templates every few months and
nothing reimports container state. What replaced the backup is narrower and
actually load-bearing: `ledger-publish` (on the Reviewer and Marketing) commits
only the series that genuinely cannot be rebuilt into a branch of the project's
marketing repo.

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

| Sub-agent | Keys the lead relays |
|---|---|
| `opensource/community-coding` | `COMMUNITY_REPOS`, `ACK_GRACE_MINUTES`, `MARKETING_REPO` (+ optional `SECURITY_WATCH_REPOS`, `DOCS_REPO`, `GFI_LABEL`, `LEDGER_BRANCH`) |
| `opensource/community-marketing` | `MARKETING_REPO`, `GA4_PROPERTIES` (+ optional `LEDGER_BRANCH`) |

The Reviewer's is by far the larger payload — it owns most of the tasks in the
set (run `bash scripts/gen-task-table.sh --counts` for the current split) — so
it's the relay most likely to end up half-done.

This agent also owns its own optional `RELEASE_WATCH_REPOS`, which narrows
`release-announcement-watch` to a subset of `COMMUNITY_REPOS`.
`GITHUB_BOT_USERNAME` is set in all three agents.

**`MARKETING_REPO` is relayed to both sub-agents**, because each publishes its
own unrecoverable series to a branch there and two agents cannot share a config
file. The same value has to exist in two files; if one publish is silently
missing later, a half-done relay is the first thing to check.

**The lead keeps no copy of the metrics series.** An earlier version had it
appending the follower counts into its own
`social-metrics-history.jsonl` as a second durable copy; that is deliberately
gone. The marketing agent owns that file and publishes it itself, because two
ledgers of the same numbers in two containers drift apart and then nobody knows
which is right.

**What the lead would still lose in a rebuild**: `question-ledger.jsonl` (the
repeat-question ledger behind `docs-gap-review`) and `owner-instructions.jsonl`
(the ack ledger). Neither is published anywhere, deliberately — both contain
community members' words and the owner's private direction, which don't belong
in a repo branch. Treat them as genuinely disposable: `docs-gap-review` simply
starts observing again after a rebuild, and the ack ledger only needs to
outlive a session, not a repave.

## Full setup, from zero

```bash
# 1. Stamp the lead
ncl groups create --template opensource/community-manager --name "Community Manager"

# 2. Stamp whichever sub-agents you want
ncl groups create --template opensource/community-coding --name "Community Coding"

#    Marketing is NOT stamped at install by default — it is the deferred one.
#    Stamp it when you want the follower/traffic series tracked:
ncl groups create --template opensource/community-marketing --name "Community Marketing"

# 3. Wire sub-agents to the lead — agent-to-agent
ncl destinations add --agent-group-id <coding-id>    --local-name parent --target-type agent --target-id <lead-id>
ncl destinations add --agent-group-id <lead-id>      --local-name coding --target-type agent --target-id <coding-id>
ncl destinations add --agent-group-id <marketing-id> --local-name parent --target-type agent --target-id <lead-id>
ncl destinations add --agent-group-id <lead-id>      --local-name marketing-agent --target-type agent --target-id <marketing-id>

# 4. Wire the LEAD to your Discord channels and GitHub repos, per your
#    platform's channel management. The Reviewer additionally needs a SILENT
#    wiring to each support channel so unanswered-watch can see messages and
#    post its holding line — see welcome/SKILL.md 5c for the exact commands.
#    Marketing gets no channel wiring at all.

# 5. Connect credentials in OneCLI (tables below), then review and resume tasks
ncl tasks list --status paused
ncl tasks run <task-id>       # test scripted tasks first
ncl tasks resume <task-id>
```

Every task in all three templates is created **paused**. Read each one, fill in
the config its README lists, and resume deliberately — that's the
rebuild-cheaply property: the whole system is a stamp plus a handful of
`resume` calls, and tearing it down is deleting three groups.

**If you stamp the Reviewer (`opensource/community-coding`), leave the lead's
`daily-github-triage` paused.** It exists for lead-standalone deployments, and
`github-ops-triage` covers the same ground at a higher cadence (every 6 hours
versus a weekday digest). The reason this matters more than it used to: the two
tasks now live in *different* agents, so they no longer share a cursor file —
each tracks "already reported" in its own plugin-data, and neither can see that
the other has already reported an issue. Running both double-reports, and
nothing in the system will notice.

**There is no workspace backup anywhere in this set, by design.** See the note
under *Configuration* above: the only state worth preserving is published by
`ledger-publish` on the two sub-agents, and everything else is meant to be
rebuilt.

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
| GitHub | `api.github.com` | `Authorization: Bearer` | **Fine-grained**, scoped to `COMMUNITY_REPOS` — still needed here for `daily-github-triage` and `release-announcement-watch`: Issues read/write and Pull requests read/write (this agent *does* comment and file issues), Contents read, Metadata read. The marketing repo is **not** in this agent's scope; that write belongs to the sub-agents' tokens. Never `read:org`, `admin:*`, or `delete_repo`. Full per-endpoint justification in [PREREQS.md §1b](../../PREREQS.md). | Settings → Developer settings → Personal access tokens (fine-grained) |
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

**Give each agent its own least-privilege token.** The Reviewer gets a token
that is read-only across `COMMUNITY_REPOS`, plus Contents+PRs write for
security patches and Contents write on the marketing repo for
`ledger-publish`; the marketing sub-agent gets one scoped to the marketing repo
only. Sharing one broad token across all three defeats the point of splitting
them.

**All three tokens match the same host (`api.github.com`), so use OneCLI's
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
