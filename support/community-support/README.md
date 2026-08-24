# Community Support Agent Template

The lead agent in a four-template set for running an open-source project's
community: answer users and contributors on Discord and GitHub as one consistent
identity, triage what comes in, and relay the work of three headless sub-agents —
while being the only thing in the system with a **full** public voice.

**This set:**

| Template | Role | Public voice? |
|---|---|---|
| `support/community-support` (this one) | Lead: community replies, GitHub triage, escalation, relays sub-agents | **Yes — the only full one** |
| `local/community-local` | Local-model ops: holding acknowledgments, repo mirrors, narration of pre-computed numbers | Holding acknowledgments only |
| `engineering/community-coding` | Issue/PR triage and security advisory sweeps | No |
| `marketing/community-marketing` | Content drafting (1 task) | No |

The lead works standalone. Add any of the three sub-agents when you want that
work done without giving it a second identity.

## Why one voice

Every extra identity that can post publicly is another thing a reader has to
trust separately, and another seam an injected instruction can aim at — "reply as
the other bot," "don't mention a sub-agent did this."

For the **Reviewer** (`engineering/community-coding`) and **Marketing**
(`marketing/community-marketing`), that whole class of attempt has nothing to
attach to: neither has any channel wiring, so it fails structurally rather than
relying on an agent remembering a rule under pressure.

The **local ops agent** is the one deliberate exception, and it's worth stating
precisely rather than blurring: it *does* hold one channel wiring, because a
holding acknowledgment has to appear where the unanswered message is. Its
restriction is enforced by **scope** instead of by absence — one channel,
read-only credentials everywhere else, no write access, and a fixed template it
is forbidden to compose freely. What it posts is a receipt, never a resolution.
Every actual answer is still only ever the lead's. Full reasoning in
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
│   └── community-support/
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

`health-check` and `workspace-backup` used to live here; both are now
`local/community-local` tasks, because each only narrates what its gate script
already computed and needs neither the lead's model nor its voice.
`docs-gap-review` moved the other way, into this template: it reads
`question-ledger.jsonl`, which only the lead writes, and no agent can read
another agent's plugin-data — so in the Reviewer it was permanently dead.
`daily-github-triage` likewise belongs to the lead (see the note under *Full
setup* about leaving it paused).

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
`plugin-data/community-support/` (`project-config.md` + `config.env` — the
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
| `local/community-local` | `COMMUNITY_REPOS`, `MIRROR_REPOS`, `CONTENT_REPO`, `GA4_PROPERTY_ID`, `GFI_LABEL`, `ACK_GRACE_MINUTES` |
| `engineering/community-coding` | `COMMUNITY_REPOS` (+ optional `SECURITY_WATCH_REPOS`) |
| `marketing/community-marketing` | `CONTENT_REPO`, `RELEASE_WATCH_REPO` |

This agent also owns its own optional `RELEASE_WATCH_REPOS` (narrows
`release-announcement-watch` to a subset of `COMMUNITY_REPOS`, distinct from
marketing's singular `RELEASE_WATCH_REPO` above — easy to confuse, unrelated
keys).

The local agent's is by far the largest payload — it owns the largest single
share of the tasks in the set (run `bash scripts/gen-task-table.sh --counts`
for the current split) — so it's the relay most likely to end up half-done. Note that
`CONTENT_REPO` is relayed to **both** local (for `draft-cleanup`) and marketing
(for `content-draft-cycle`); the same value has to exist in two files.
`GITHUB_BOT_USERNAME` is set in all four agents.

This agent is also the **durable home of the follower-count series**: when the
local ops agent hands over its weekly snapshot line, the lead appends it to
`plugin-data/community-support/social-metrics-history.jsonl`.

**Open question — the lead's own ledgers aren't backed up.** `workspace-backup`
is a `local/community-local` task and captures the **local** agent's workspace,
so the lead's append-only files (`social-metrics-history.jsonl` and
`question-ledger.jsonl`) are not covered by it. Nothing in the set currently
covers them. Treat that as the state you would actually lose in a rebuild, and
decide deliberately how to cover it — don't assume a backup exists here.

## Full setup, from zero

```bash
# 1. Stamp the lead
ncl groups create --template support/community-support --name "Community Support"

# 2. Stamp whichever sub-agents you want
ncl groups create --template local/community-local --name "Community Local Ops"
ncl groups create --template engineering/community-coding --name "Community Coding"

#    Marketing is NOT stamped at install by default — it is the deferred one.
#    Stamp it when you actually want a drafting queue:
ncl groups create --template marketing/community-marketing --name "Community Marketing"

# 3. Wire sub-agents to the lead — agent-to-agent
ncl destinations add --agent-group-id <local-id>     --name parent    --target <lead-id>
ncl destinations add --agent-group-id <lead-id>      --name local     --target <local-id>
ncl destinations add --agent-group-id <coding-id>    --name parent    --target <lead-id>
ncl destinations add --agent-group-id <lead-id>      --name coding    --target <coding-id>
ncl destinations add --agent-group-id <marketing-id> --name parent    --target <lead-id>
ncl destinations add --agent-group-id <lead-id>      --name marketing --target <marketing-id>

# 4. Wire the LEAD to your Discord channels and GitHub repos, per your
#    platform's channel management. The local ops agent additionally needs
#    exactly ONE channel (holding acknowledgments) — see its README.
#    Coding and marketing get no channel wiring at all.

# 5. Connect credentials in OneCLI (tables below), then review and resume tasks
ncl tasks list --status paused
ncl tasks run <task-id>       # test scripted tasks first
ncl tasks resume <task-id>
```

If you stamped the local ops agent, **point it at a local model before resuming
anything** — stamped without that override it runs on the cloud provider and
shares this agent's usage window, which defeats the entire reason it exists. Its
README has the two commands.

Every task in all four templates is created **paused**. Read each one, fill in
the config its README lists, and resume deliberately — that's the
rebuild-cheaply property: the whole system is a stamp plus a handful of
`resume` calls, and tearing it down is deleting four groups.

**If you stamp the Reviewer (`engineering/community-coding`), leave the lead's
`daily-github-triage` paused.** It exists for lead-standalone deployments, and
`github-ops-triage` covers the same ground at a higher cadence (every 6 hours
versus a weekday digest). The reason this matters more than it used to: the two
tasks now live in *different* agents, so they no longer share a cursor file —
each tracks "already reported" in its own plugin-data, and neither can see that
the other has already reported an issue. Running both double-reports, and
nothing in the system will notice.

**Workspace backup is no longer set up here** — `workspace-backup` is a
`local/community-local` task, and its setup lives in
[that template's README](../../local/community-local/README.md).

**Script dependencies:** `bash`, `curl`, `jq`, and `ncl`
(`weekly-identity-integrity-check` reads `ncl tasks list --json`; without `ncl`
its gate wakes the agent for a manual check instead of failing). Verify with
`ncl tasks run <task-id>` before resuming. **Schedules run in UTC** (the kit pins `TZ=UTC`) from the `schedule:` cron in
each task's frontmatter. Tune those lines to your day **before stamping** —
frontmatter isn't runtime-editable, so afterwards it's cancel-and-recreate per
task. A per-group timezone override may exist in your NanoClaw version; treat
it as unverified until you've confirmed a task actually fired at the local
time you expected (see UPSTREAM-ISSUES.md).

## Credentials: via OneCLI, not env vars

No API keys live in any of these templates. The OneCLI gateway holds credentials
in its vault and injects them into outbound HTTPS calls at the proxy boundary, so
no token ever sits in `mcp.json`, the container env, or chat context.

| Service | API host to match | Auth style | Permissions needed | Where to get it |
|---|---|---|---|---|
| GitHub | `api.github.com` | `Authorization: Bearer` | **Fine-grained**, scoped to `COMMUNITY_REPOS` — still needed here for `daily-github-triage` and `release-announcement-watch`: Issues read/write and Pull requests read/write (this agent *does* comment and file issues), Contents read, Metadata read. The backup repo is **not** in this agent's scope; that write belongs to the local ops agent's token. Never `read:org`, `admin:*`, or `delete_repo`. Full per-endpoint justification in [PREREQS.md §1b](../../PREREQS.md). | Settings → Developer settings → Personal access tokens (fine-grained) |
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

**Give each agent its own least-privilege token.** The Reviewer gets a read-only
GitHub token; the marketing sub-agent a token scoped to the content repo only;
the local ops agent read on `COMMUNITY_REPOS` + `MIRROR_REPOS` plus Contents
**write on its backup repo only**. Sharing one broad token across all four
defeats the point of splitting them.

**All four tokens match the same host (`api.github.com`), so use OneCLI's
`selective` secret mode** — in `all` mode, every agent whose requests match the
host gets whichever secret matches first, which collapses your four scoped
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
cp -R support/community-support <nanoclaw-install>/templates/support/
ncl groups create --template support/community-support --name "Test Support"
```

Re-copy after every edit — the stamp reads the install's `templates/`, not your
clone. Check the create response's `templateReport` for anything skipped.
