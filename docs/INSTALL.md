# Install runbook

## Quick start

**You need two things before you start: Docker Desktop running, and a
Discord server you admin.** Everything else — the GitHub token, the repo
list — the manager asks you for, one at a time, only when a task actually
needs it. There's no upfront checklist to collect first.

```bash
git clone https://github.com/DawoudIO/nanoclaw.git
git clone https://github.com/DawoudIO/nanoclaw-community-agents.git

cd nanoclaw-community-agents
bash scripts/install-templates.sh     # → ../nanoclaw/templates/

cd ../nanoclaw
./nanoclaw.sh
```

At the prompts: **"From local templates"**, then **`opensource/community-manager`**.
It is the only agent in this set, and the only thing with a public voice.

`nanoclaw.sh` builds or pulls the agent container, brings up the OneCLI
vault, and starts the service — directly, on your machine. There's no
sandbox VM to provision separately. Then DM the agent; it interviews you
for the rest, and tells you exactly what to add to OneCLI as each need
comes up.

**Re-run `bash scripts/install-templates.sh` after every `git pull` in this
repo**, and `--check` to see if the copy has drifted. A stale copy still
stamps — the old version, which reads as "the fix didn't work" rather than
as a stale copy. This is the most common way an install goes subtly wrong.

<details>
<summary>Why a copy step at all — NanoClaw has a template library built in</summary>

Everything else here uses NanoClaw's own machinery: `nanoclaw.sh` installs,
"From local templates" discovers, `ncl groups create --template` stamps.
The copy is the one gap.

The built-in library fetch can't reach this repo — `DEFAULT_TEMPLATES_SOURCE`
in `setup/templates.ts` is hardcoded to `nanocoai/nanoclaw-templates`, no
override. And pointing `NANOCLAW_TEMPLATES_DIR` at this repo — which looks
like the zero-copy answer — silently doesn't work: it's read from
`process.env` only, not from `.env`, and the launchd plist omits it. The
wizard would pick it up; the **background service wouldn't**, so anything
the service stamps later (a restamp after a template update) would look in
an empty `templates/` and fail, long after the step that appeared to work.

The clean fix is upstream making `DEFAULT_TEMPLATES_SOURCE` configurable;
then this script goes away.

</details>

## What the installer does, and what this runbook is for

Three actors do the work, and most of what follows belongs to the middle
one:

| `nanoclaw.sh` does | The manager does, in the interview | Only you can do |
|---|---|---|
| Container image, OneCLI vault, agent runtime | Wires the guild channels (§1) | Click through Discord bot creation |
| Service start, mounts, access rules | Persists its own config (§3) | Add each credential to OneCLI, when asked |
| One agent, from your chosen template | Verifies every credential (§2) | |
| One channel — your owner DM | Resumes + test-fires every task, one at a time (§4) | |
| Timezone detection | | |

So "do I have to do all this?" is mostly no. The manager does most of it and
reports back — you're needed for Discord's own portal (nothing else can
click through that for you) and for approving each credential as OneCLI
asks for it.

Two things worth knowing: the installer wires **only your owner DM** — every
other Discord channel is the manager's job in §1a. And Discord's bot token
lands in `.env`, **not** the vault — the vault holds provider auth and the
GitHub token the manager asks for as it goes.

Activation is deliberately not one "go" at the end (§4): a real install
batch-resumed everything, lost the step in the evening's noise, and nothing
ran for ~18 hours before anyone noticed.

**Re-running `./nanoclaw.sh` is safe** — it detects an existing install and
skips what's done; the template step becomes add-or-update, not a duplicate.

### Known snag: the "Terminal Agent" may not clean up

Setup creates a scratch agent (`ping_test`, shown as **Terminal Agent**) to
prove the install answers, then deletes it. That delete opens the central
DB directly while the service you just started holds it, so it can lose the
race:

```
▲ Couldn't clean up the test agent — it may still appear in your agent list.
```

Not just cosmetic: it stays in `ncl groups list` and answers on the CLI
channel, so `pnpm run chat` can land there instead of your real agent.
Remove it once setup is done:

```bash
pnpm exec tsx scripts/delete-cli-agent.ts --folder ping_test
```

Stop the service first if it fails again.

---

Below: stamp/wire the agent → connect Discord → configuration → go-live.
[OPERATIONS.md](OPERATIONS.md) covers everything after go-live.
[PREREQS.md](../PREREQS.md) has the credential-scope reference for when the
manager asks you for one.

## 1 · Stamp the agent and wire it

One agent, on a capable model, because everything it does is public-facing
judgment:

| Agent | Job | Model | Public voice? |
|---|---|---|---|
| **Manager** (`opensource/community-manager`) | Talks to your community: replies on Discord, first response on GitHub, escalation, docs-gap review, and a daily picture of what is released versus merged-but-unreleased | Claude Sonnet | **Yes** |

**Nothing here writes content.** If you want posts, announcements or campaign
copy, that stays with you and whoever you work with — this set answers and
reports.

To switch a job off, pause its task (`ncl tasks pause`) rather than deleting
the group, so config and memory survive.

Run from the nanoclaw checkout (`cd nanoclaw`, or conversationally via
`claude` in the same directory). `--name` is an internal `ncl`/dashboard
label only — unrelated to the Discord display name or the project name —
pick anything readable, e.g. `"AcmeCRM Manager"`.

```bash
# Stamp — check the response's templateReport for skipped parts, and note
# the group's id: the vault steps below need it.
./bin/ncl groups create --template opensource/community-manager    --name "Community Manager"
# Install jq host-side, before you DM the manager. setup-check.sh needs it,
# and the tasks parse JSON with it. It must happen here: install_packages
# rebuilds the image and restarts the container on approval, which would kill
# the welcome interview mid-conversation.
./bin/ncl groups config add-package --id <manager-id> --apt jq
# Run the SETUP interview on Haiku, not Sonnet. The interview is structured
# Q&A plus CLI calls — it does not need the manager's steady-state model, and
# onboarding is long enough (credentials, wiring, per-task activation) that
# the difference is real. Set it here so it lands in the same restart as jq,
# costing no extra one. §4 switches it to Sonnet once the interview is done.
./bin/ncl groups config update --id <manager-id> --model claude-haiku-4-5
./bin/ncl groups restart --id <manager-id> --rebuild
```

### 2a. Connect Discord

`/add-discord`, run the same way as the stamping commands above (bot
creation, invite, channel wiring). Invite with least-privilege permissions:
Send Messages, Embed Links, Attach Files, Read Message History — not
Administrator. **Before the first support-channel test, enable Message
Content privileged intent** (Bot → Privileged Gateway Intents) — without it
the bot answers @mentions but never auto-replies. This intent also affects
approval cards: a real, unfixed platform bug (UPSTREAM-ISSUES.md #20) makes
a Discord approval click resolve as Deny when interactions fall back to the
HTTP webhook path instead of the Gateway — which happens when the Gateway
listener is down, e.g. from this exact intent being off. If an approval
card ever rejects an obvious Approve click, check this setting first.

**Your own DM with the manager is the control plane — wire it first.** Set
sender scopes at wiring time: owner DM stays locked to known senders, but
every public channel gets `--sender-scope all` — otherwise each new
community member triggers a "new sender — allow?" prompt, defeating the
point of a public channel. Verify the round trip both ways, then DM the
manager — its `welcome` skill runs the interview (first question: your
GitHub repo) and persists config. Only then wire the public channels — the
manager's `welcome/SKILL.md` §5c has the exact commands.

`unanswered-watch` needs no wiring of its own. It reads the manager's own
channel-backed sessions, so once the support channels are wired it sees
them; a channel that is not wired is one it cannot watch.

**Name the Discord app to visibly match the GitHub bot account** you'll set
up when the manager asks for one (`acmecrm-bot` ↔ "AcmeCRM Bot") — one
agent speaks on both platforms, and a mismatch reads as two different bots.

After Discord is wired, everything runs through it — direct CLI access is
break-glass admin only, see below.

## Break-glass admin: driving the checkout directly

Running `claude` (or a plain shell) from the `nanoclaw` checkout gives
direct access to the install — files, `ncl`, the group workspaces. Reserve
it for a bad state: the owner DM broken, an agent stuck, wiring surgery, log
forensics. **This runs on your host, not inside any isolation boundary** —
full filesystem and Docker access, same as anything else you run locally.

**Helps:** operates on the system instead of negotiating with an agent;
works when Discord doesn't.

**Hurts:** every change is out-of-framework — pair it with a DM to the manager
afterward, or expect an ask-don't-lock question from the integrity gate. It
bypasses every gate (no request-holds, no ledger entry) — nothing stops a
typo. Habit decay is the real risk: routine config drifting into CLI edits
rebuilds the "who changed this?" problem single-voice exists to prevent.
**Discord for operations, CLI for surgery.**

**Hard rule: never restart or rebuild a container while an agent is
mid-conversation.** `ncl groups restart` kills the container under whatever
turn is in flight — on a real install, a restart issued mid-reply coincided
with the owner receiving the same message twice. **NanoClaw will not stop
you**: the guard `ALLOW`s any host-socket caller unconditionally
(`src/cli/guard.ts`) — there's no caller identity distinguishing you from a
CLI agent doing the same thing. Enforce it on the CLI side instead, in
`.claude/settings.local.json` (the local override — not the tracked
`settings.json`):

```json
{
  "permissions": {
    "deny": ["Bash(ncl groups restart:*)", "Bash(./bin/ncl groups restart:*)"]
  }
}
```

This stops a CLI *agent* from restarting on its own initiative; you can
still run it deliberately once you've confirmed nothing's in flight. This
doctrine is for **after go-live** — during setup (§1 above), CLI-driving is
the intended path, including the `--rebuild` the jq install needs.

**`/debug` is your first move**, not a separate install — built-in, walks
logs/env/mounts/MCP connectivity for you.

## Monitoring: clidash (do this once, here)

Also set up [`clidash`](https://nanoclaw.dev/skills/clidash) — a read-only
dashboard (groups/sessions/channels/users, message charts, log tails) from
`ncl`'s own output. No dependencies, no vault entry:

```bash
/add-clidash
cd tools/clidash && cp clidash.config.example.json clidash.config.json
node server.js   # binds 127.0.0.1:4690
```

Reach it the same way as the OneCLI dashboard (§3 has the Tailscale
command). The heavier `dashboard` skill (live push, token-usage numbers) is
a deliberate non-default — see
[SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md) — add it only if clidash can't
answer a real "which task is burning budget" question.

## Platform skills — the one authoritative list

Templates ship their own *agent* skills; **platform** skills are operator
actions and can't be declared by a template. This is the replay checklist
for a recreate — anything marked *modifies install* needs re-applying after
[OPERATIONS.md](OPERATIONS.md)'s refresh.

| Skill | Status | When | Modifies install? |
|---|---|---|---|
| `/add-discord` | **Required** | §1a | No |
| `/debug` | Built-in | Any time | No |
| `/add-clidash` | **Recommended** | Right after §1 | Copies `tools/clidash` |
| `/add-ollama-provider` | **Not used this phase** — see SKILLS-ADOPTION.md | Would route the agent to a host Ollama model | **Yes** — Dockerfile + `container.json` edits |
| `/add-ollama` (tool) | **Proposed, undecided** | Only if translation volume proves expensive | **Yes** — copies an MCP server, rebuilds image |
| `/add-dashboard` | **Deliberate non-default** | Only if clidash can't answer a real budget question | **Yes** — persistent process, `DASHBOARD_SECRET` |
| `/update-skills` | **Break-glass only** | Never in steady state | **Yes**, desyncs from `platform-baseline.json` |

Everything else in NanoClaw's skill catalog was reviewed and is either N/A
for this deployment or rejected with reasons — see
[SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md).

## 2 · Credentials — added when the manager asks, not upfront

**There is no `.env` file in this system, deliberately.** Secrets go in the
OneCLI vault; platform settings belong to the kit's `spec.yaml`; task
parameters (repo names, grace minutes — never secrets) live in
`plugin-data/community-manager/config.env`. Anything that asks you to put a key in
`.env` is violating this system's own rules — refuse it.

OneCLI's dashboard runs on port `10254`, bound to **your machine's own
loopback** — `http://127.0.0.1:10254` only resolves there. If you only ever
manage it from the same machine, that's it, skip the rest of this section.
Checking in from elsewhere: [Tailscale](https://tailscale.com) is the
recommended path — install on host and device, then route the port as raw
TCP (not HTTPS, to keep the plain-`http://` shape the dashboard expects):

```bash
tailscale serve --tcp=10254 tcp://localhost:10254 --bg
```

Verify with `tailscale serve status`, open `http://<tailscale-ip>:10254`
(never `funnel` — this dashboard holds credentials). The welcome interview
asks for this address once and reuses it for every future link. The model
credential lives in the same dashboard's **LLMs** tab.

**Version note**: OneCLI has its own release line. Transient 404s that
never clear may mean your gateway predates the API the SDK expects — see
`docs/onecli-upgrades.md` before assuming it's a template problem.

**When the manager asks for a GitHub token**, [PREREQS.md](../PREREQS.md)
has the exact URL. The scope to give it, so you don't have to work it out
live:

| Token | Needs | Never |
|---|---|---|
| Manager | `repo`/`public_repo` — comments, labels, issues; read on `COMMUNITY_REPOS` and `CONTEXT_REPOS` | `read:org`, `admin:*`, `delete_repo` |

If a future feature seems to need broader access, the fix is almost never
"widen this token" — it's a new, narrower, single-purpose credential.

**Set the agent to `selective` secret mode and assign it its own secret**,
so a second secret on the same host added later never collapses into a
shared one:

```bash
onecli agents list
onecli agents set-secret-mode --id <agent-id> --mode selective
```

Optionally add **request-hold approval rules** for anything you can never
allow unattended (publishing, sending mail) — gating at the proxy is
enforcement no prompt can bypass.

**Discord bot** needs, beyond the invite in §1a: nothing further in the
vault — its token lives in `.env`, not here.

**Optional egress lockdown**: `NANOCLAW_EGRESS_LOCKDOWN=true` forces all
agent traffic through the OneCLI gateway on a Docker `--internal` network
with no direct route out — off by default. See `src/egress-lockdown.ts` if
you want that hardening; nothing here requires it.

### OneCLI footprint

The exact list `onecli apps connections agent-access` (PREREQS.md §3) should
show once everything's added, and nothing more.

| Agent | Granted | Host | Used by |
|---|---|---|---|
| Manager | GitHub PAT | `api.github.com` | `github-first-response`, `project-context`, live replies, identity check |
| Manager | — (nothing) | — | `unanswered-watch`, `owner-tldr`, `docs-gap-review`, `weekly-identity-integrity-check`, `conversation-archive-prune` — local state only |

A row that doesn't exist here is a finding: the agent never appears against
any host but `api.github.com`, and holds no write grant on a repo outside
`COMMUNITY_REPOS`.

### Confirm identity, don't assume it

A scoped token isn't the same guarantee as the *right account* holding it —
paste a personal token by mistake and every action appears to come from the
owner. The welcome interview asks for the expected bot username up front
and **verifies it mechanically**: a real `GET /user` call after each token
registration confirms the login matches. Discord needs no equivalent check
— a bot token structurally can't resolve to a personal identity.

[PREREQS.md](../PREREQS.md) has the full audit/rotation runbook. Run it
once after setup and after any credential change.

### Optional: paid X auto-posting

Off by default — the welcome interview asks plainly, with real cost stated
("no free tier since Feb 2026, ~$0.20/post"). Default is a free intent-URL:
the agent drafts, a human clicks Post. If you opt in, put an **OneCLI
request-hold** on `api.x.com` so every post still needs a button-press —
never wire auto-posting as a silent capability.

## 3 · Configuration — one conversation, one file

**The default path is the conversation, not file edits.** After the owner
DM is wired (§1a), the manager's `welcome` skill interviews you and persists
everything as runtime config. You edit zero files for any of it.

### What lands in `config.env`

You answer once, in the owner DM; the manager writes the task parameters to
`plugin-data/community-manager/config.env`:

| Key | What it does |
|---|---|
| `COMMUNITY_REPOS` | the repos `github-first-response` watches, and the default for `CONTEXT_REPOS` |
| `CONTEXT_REPOS` *(optional)* | the repos `project-context` follows, when they differ from `COMMUNITY_REPOS` |
| `ACK_GRACE_MINUTES` | how long a support message may sit before `unanswered-watch` wakes the agent (default 5) |
| `CHAT_INVITE_URL` *(optional)* | the team chat invite `follow-up-nudge` offers a contributor who has gone quiet |
| `STALE_PR_DAYS` / `FOLLOWUP_DAYS` / `RENUDGE_DAYS` *(optional)* | `follow-up-nudge` thresholds; defaults 7 / 5 / 30 days |
| `GITHUB_BOT_USERNAME` | the bot account the agent verifies it is acting as |

**A missing key fails quietly.** It isn't an error: the gate exits
`not-configured` and goes back to sleep. Symptom: "stamped and never does
anything," which reads like a broken agent and is an unset key. Only
`ACK_GRACE_MINUTES` has a built-in default.

### The full question list

Nothing blocks you from starting — the interview infers what it can, and
"not now" is a complete answer to anything optional. Skim once, then talk
to the agent.

| # | Asked | Optional? |
|---|---|---|
| 1 | GitHub repo or org | **No** |
| 2 | What runs and why | Stated, not asked |
| 3 | Repo map: product/docs/site | Inferred + confirmed |
| 3b | Bot's GitHub username | **No** |
| 4 | Docs site URL, language, topic scope | Inferred where possible |
| 5 | Discord channels by tier | Required if using Discord |
| 6 | Maintainer list | Confirmed from the repo |
| 7 | Discord invite URL | Optional |
| 8 | Model | Not asked — Sonnet |
| 9 | OneCLI dashboard address | Asked once |
| 10 | Docs style | Assumed user manual, confirmed in one line |
| 11 | Audience, in your words | Optional — shapes how replies are pitched |

After this, the agent walks credential setup, verifies each with a real
call, and asks one explicit "go" before activating anything.

### Prefer a file over the live interview?

`onboarding-answers.example.json` is currently absent from the repo (see
SKILLS-ADOPTION.md); if present, copy it, fill in what you know, and the
manager reads it instead of interviewing — asking only about `null`s. Validate
first — it also refuses anything credential-shaped:

```bash
cp onboarding-answers.example.json onboarding-answers.json
$EDITOR onboarding-answers.json
bash scripts/check-onboarding.sh onboarding-answers.json
```

Then put it where the agent can see it (the container only sees its own
workspace):

```bash
cp /path/to/onboarding-answers.json groups/<manager-folder>/
```

DM the manager: *"my answers are in `/workspace/agent/onboarding-answers.json`"*
— it reads, echoes a summary back (check that it matches), asks about what's
missing, persists. Rebuilding later: this file + a copy of
`plugin-data/community-manager/` is the complete recovery set.

**Already installed conversationally?** Export the equivalent file instead
of redoing the interview:

```bash
bash scripts/export-answers.sh <nanoclaw-root> [out.json]
```

Two limits: `project-config.md` comes back verbatim as
`_project_config_raw` rather than parsed, and anything that's a credential
comes back `null` — the export fails rather than writing one out.

## 4 · Start it — the go-live sequence

The conversational path ends with credential verification and one explicit
"go" that resumes the verified tasks. The manual equivalent:

```bash
./bin/ncl tasks list --status paused
./bin/ncl tasks run <task-id>     # dry-run each gate
./bin/ncl tasks get <task-id>     # inspect the result
```

Resume order, safe → side-effect-adjacent:

1. **No credentials, no network first**: `unanswered-watch` (every 5 min —
   catches a support question that scrolled past), `owner-tldr` and
   `weekly-identity-integrity-check` (jq only), and
   `conversation-archive-prune`, which is pure filesystem housekeeping and
   never wakes a model.
2. **The GitHub-facing gates**, once `COMMUNITY_REPOS` is set:
   `github-first-response` and `project-context`. Run `project-context` once
   by hand and read `tasks get`: the first run reports `status: baseline` and
   leaves one row per repo in `plugin-data/community-manager/release-state.csv`.
   `docs-gap-review` is safe from day one; it stays quiet until support work
   fills its ledger.

Approved-but-unmerged PRs, stale good-first-issues and missing
community-health files are not scheduled tasks — run the project repo's
`repo-health` skill on demand when you want that check.

### The manager switches itself to Sonnet — expect one restart

Setup ran on Haiku (§1). Steady-state work is the opposite shape: judging
whether a stranger's bug report is a duplicate, writing the one public reply
the project makes, deciding what to escalate. That's the manager's standard
tier — and **the manager promotes itself, as the last act of the welcome
interview** (`welcome/SKILL.md` §10), once setup is genuinely complete and
its closing summary is delivered.

So on the conversational path you don't run anything here. What you should
see: a short "switching to Sonnet now, the session will drop for a few
seconds" message, then a brief silence, then a manager that answers again on
Sonnet. **A session that goes quiet right after setup is the expected
behavior, not a crash.** Config and memory live in plugin-data and survive
the restart.

If you took the manual path, or the agent couldn't reach `ncl`, do it
yourself — both lines, in that order:

```bash
./bin/ncl groups config update --id <manager-id> --model claude-sonnet-5
./bin/ncl groups restart --id <manager-id>
```

`config update` only writes the row — confirmed in
`src/cli/resources/groups.ts`, whose own help says changes "do NOT take
effect until you run `ncl groups restart`." Skip the restart and the config
reads Sonnet while every wake still bills Haiku, which is the failure mode
you'd never notice from the outside. No `--rebuild` (that's for package
changes).

Either way, confirm it landed before the smoke test — you want the smoke
test exercising the model that will actually answer people:

```bash
./bin/ncl groups config get --id <manager-id>     # model should read sonnet
```

Smoke-test: post in a support-tier channel (expect an unprompted reply),
@mention the manager in a dev-tier channel (expect a reply only because you
tagged it), and ask it what the latest release is (expect an answer read from
`release-state.csv`, not from memory). Test `unanswered-watch` once, the way
CHECKPOINTS.md item 12 describes — it only shows up when a live reply was
missed, so it is the behavior most likely to be quietly broken without
anything else looking wrong.

**"Resumed" is not "ready."** Walk the 13-point ready gate in
[CHECKPOINTS.md](CHECKPOINTS.md) before calling it live. Everything after
— token budget, the task reference, the update policy, teardown — is in
[OPERATIONS.md](OPERATIONS.md) and [UNINSTALL.md](UNINSTALL.md).
