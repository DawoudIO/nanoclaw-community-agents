# Community Manager Agent Template

One agent for running an open-source project's community: help Discord and
GitHub users with questions and answers, as one consistent identity, and
triage what comes in. It is the only thing in the system with a public
voice, and the only agent in the set.

## Why one voice

Every extra identity that can post publicly is one more thing a reader has
to trust, and one more target for an injected instruction — "reply as the
other bot," "don't mention a sub-agent did this." There is no second agent
here, so that class of attempt has nothing to aim at. Full reasoning in
`skills/community-manager/references/single-voice-relay.md`.

The cost of one agent is stated plainly in `unanswered-watch`: it runs on
the same usage window as the replies it watches over, so it catches a
question that scrolled past, not a window that has run out.

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
│   └── tasks/                                         # 9 tasks, all created paused
│       ├── unanswered-watch.md                        # every 5 min: a support message past the grace period
│       ├── github-first-response.md                   # every 5 min: new, unanswered issues and PRs
│       ├── project-context.md                         # daily: what changed, what is released vs merged
│       ├── follow-up-nudge.md                         # daily: check in on idle PRs and unanswered workarounds
│       ├── owner-tldr.md                              # the ONE daily digest to the owner
│       ├── docs-gap-review.md                         # nightly: opens a docs PR for any question the docs could not answer
│       ├── owner-instruction-watch.md                 # the dropped-ack watch the persona already promised
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
│           └── report-formats.md                      # pre-packaged report layouts
└── README.md
```

`project-context` is what keeps the answers true. Daily, it reads every repo
in `CONTEXT_REPOS` for the commits since yesterday, which `.agents/skills/**`
and docs files changed, the latest release tag against what is merged but
unreleased, and the open milestones, then writes
`plugin-data/community-manager/release-state.csv` so the agent answers "is X
released?" from a file. It wakes the model only on change.

**There is no health-check or workspace-backup task in this set, by design.**
A health check that cannot fix what it finds, reporting via a heartbeat whose
*absence* is the alarm, needs a human to notice a silence — and a dead
container cannot report its own death anyway. A whole-workspace backup is a
write-only cost when nothing ever restores from it, which is the case here:
the system is rebuilt from the templates and nothing reimports container
state. Every file this agent writes is a cache its task rebuilds on the next
run. Project metrics are collected by GitHub Actions in the project's own
repo, outside this agent.

## Channel tiers

`additional_context/channel-routing.md` sorts every wired channel into three
tiers and fixes the engage behavior per tier, so it isn't a per-message judgment:

| Tier | Who's there | Behavior |
|---|---|---|
| **Support** | Community members asking for help | **Auto-reply** — jumps in on real questions/requests; doesn't interject into cross-talk that merely mentions the project (see `channel-routing.md`) |
| **Developer** | Contributors, maintainers, security | **Mention-only** — never volunteers into contributor discussion |
| **Team lead** | Marketers, admins, project leads | **Mention-only**, plus receives release announcements |

Fill in your real channel names before going live. `example-mapping.md` shows a
filled-in version from a real deployment.

## Configuration is conversational — the `welcome` skill

On the owner's first DM, the `welcome` skill runs setup end to end:

1. Verifies the DM round trip.
2. Asks for the project's GitHub repo, scopes the goals, infers and confirms
   the rest.
3. Persists everything to `plugin-data/community-manager/`
   (`project-config.md` + `config.env`).
4. Walks credential setup with real verification calls.
5. Gates task activation on your explicit go.

**Every FILL-THIS-IN marker in this template is an optional pre-stamp
default** — the conversational config in plugin-data always wins at
runtime.

Scripts read only `config.env`; a key missing there is a task that silently
never runs. These are all of them:

| Key | Required | Read by |
|---|---|---|
| `COMMUNITY_REPOS` | yes | `github-first-response`, `project-context` (when `CONTEXT_REPOS` is unset), `setup-check.sh` |
| `CONTEXT_REPOS` | optional, defaults to `COMMUNITY_REPOS` | `project-context` — the repos whose daily changes the agent should follow, usually all of them including docs and marketing |
| `ACK_GRACE_MINUTES` | optional, default `5` | `unanswered-watch` — bare integer minutes a support message may sit unanswered |
| `CHAT_INVITE_URL` | optional | `follow-up-nudge` — the team chat invite offered to a contributor who has gone quiet; unset means no invite is offered |
| `STALE_PR_DAYS`, `FOLLOWUP_DAYS`, `RENUDGE_DAYS` | optional, defaults `7`, `5`, `3` | `follow-up-nudge` — days a PR may sit idle, days of silence after a posted workaround, and the minimum gap between check-ins on the same item |
| `OWNER_TZ` | optional, default `UTC` | `owner-tldr` — IANA zone, so the digest lands at 07:00 owner-local (`TLDR_LOCAL_HOUR` to move it) |
| `GITHUB_BOT_USERNAME` | yes | `setup-check.sh`'s identity check — without it the check passes for any account, including the owner's own |

**What the manager would lose in a rebuild:**

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

# 3. Wire the manager to your Discord channels, per your platform's channel
#    management — see welcome/SKILL.md 5c for the exact commands.
#    unanswered-watch reads the manager's own sessions, so no extra wiring.

# 4. Connect credentials in OneCLI (tables below), then review and resume tasks
ncl tasks list --status paused
ncl tasks run <task-id>       # test scripted tasks first
ncl tasks resume <task-id>

# 5. The manager promotes ITSELF to Sonnet as the last act of the welcome
#    interview (welcome/SKILL.md §10) and restarts to apply it — expect one
#    short session drop, not a crash. These two lines are the manual
#    fallback only. BOTH are needed: config update just writes the row, the
#    restart is what applies it, or it reads Sonnet and still bills Haiku.
ncl groups config update --id <manager-id> --model claude-sonnet-5
ncl groups restart --id <manager-id>
```

Every task is created **paused**. Read each one, fill in the config above,
and resume deliberately — that's the rebuild-cheaply property: the whole
system is a stamp plus a handful of `resume` calls, and tearing it down is
deleting one group.

**There is no triage digest.** `github-first-response` is the fast path — it
comments on new, unanswered issues — and the agent answers what comes in.
Nothing summarizes the week, deliberately: a digest would report the same
issues a second time from a second cursor file.

**There is no workspace backup anywhere in this set, by design.** See the note
under *Configuration* above: everything is meant to be rebuilt.

**Script dependencies:** `bash`, `curl`, `jq`, and `ncl`. Verify with `ncl
tasks run <task-id>` before resuming.
(`weekly-identity-integrity-check` reads `ncl tasks list --json` and
`unanswered-watch` reads the agent's own sessions through `ncl` — without
it, the first wakes the agent for a manual check and the second reports
`degraded` instead of failing.)

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
| GitHub | `api.github.com` | `Authorization: Bearer` | **Fine-grained**, scoped to `COMMUNITY_REPOS` plus `CONTEXT_REPOS`, plus Contents **write** on the docs repo only (`docs-gap-review` opens docs PRs on a `docs/*` branch, never the default branch): Issues read/write (`github-first-response` comments on new issues; live replies comment and file issues from chat bug reports), Pull requests read/write (live replies comment on PRs), Contents read (`project-context` reads skills, docs and `compare`), Metadata read. Never `read:org`, `admin:*`, or `delete_repo`. Full per-endpoint justification in [PREREQS.md §1b](../../PREREQS.md). | Settings → Developer settings → Personal access tokens (fine-grained) |

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

**Use OneCLI's `selective` secret mode** even with one agent — in `all`
mode, any agent whose requests match the host gets whichever secret matches
first, so a token added later for anything else on `api.github.com` would
silently reach this agent too:

```bash
onecli agents list                                              # find agent ids
onecli agents set-secret-mode --id <agent-id> --mode selective
# then assign the agent its GitHub secret in the OneCLI web UI
```

### Hard approval gates for sensitive actions

Standing instructions tell the agent what not to do — that's guidance the
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
