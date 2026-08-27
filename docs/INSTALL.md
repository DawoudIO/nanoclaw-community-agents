# Install runbook

## Quick start

**You need two things before you start: Docker Desktop running, and a
Discord server you admin.** Everything else — GitHub tokens, GA4, Gmail —
the lead agent asks you for, one at a time, only when a task actually needs
it. There's no upfront checklist to collect first.

```bash
git clone https://github.com/DawoudIO/nanoclaw.git
git clone https://github.com/DawoudIO/nanoclaw-community-agents.git

cd nanoclaw-community-agents
bash scripts/install-templates.sh     # → ../nanoclaw/templates/

cd ../nanoclaw
./nanoclaw.sh
```

At the prompts: **"From local templates"**, then **`opensource/community-manager`** —
always, and only. It's the one agent that's never optional and the only one
with a public voice; it stamps the other three itself during the welcome
interview, once it knows which jobs you want. Stamping a sub-agent first
leaves you with an agent nobody can talk to.

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
wizard would pick it up; the **background service wouldn't**, and the
service is what stamps sub-agents mid-interview. Those stamps would look in
an empty `templates/` and fail, long after the step that appeared to work.

The clean fix is upstream making `DEFAULT_TEMPLATES_SOURCE` configurable;
then this script goes away.

</details>

## What the installer does, and what this runbook is for

Three actors do the work, and most of what follows belongs to the middle
one:

| `nanoclaw.sh` does | The lead does, in the interview | Only you can do |
|---|---|---|
| Container image, OneCLI vault, agent runtime | Stamps the other three agents (§1) | Click through Discord bot creation |
| Service start, mounts, access rules | Wires their destinations + guild channels (§1) | Add each credential to OneCLI, when asked |
| One agent, from your chosen template | Relays each sub-agent's config (§3) | |
| One channel — your owner DM | Verifies every credential; sets up its own backup (§2, §3) | |
| Timezone detection | Resumes + test-fires every task, one at a time (§4) | |

So "do I have to do all this?" is mostly no. The lead does most of it and
reports back — you're needed for Discord's own portal (nothing else can
click through that for you) and for approving each credential as OneCLI
asks for it.

Two things worth knowing: the installer wires **only your owner DM** — every
other Discord channel is the lead's job in §1a. And Discord's bot token
lands in `.env`, **not** the vault — the vault holds provider auth and the
per-agent tokens the lead asks for as it goes.

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

Below: stamp/wire the agents → connect Discord → configuration → go-live.
[OPERATIONS.md](OPERATIONS.md) covers everything after go-live.
[PREREQS.md](../PREREQS.md) has the credential-scope reference for when the
lead asks you for one.

## 1 · Stamp the agents and wire them

Four agents, split by **model tier**, not subject — capable models where
judgment is needed, cheapest tier where reliability matters more than
capability:

| Agent | Job | Model | Public voice? | Required? |
|---|---|---|---|---|
| **Lead** (`opensource/community-manager`) | Talks to your community: replies, triage, escalation, release watch, docs review, relays the sub-agents | Claude Sonnet | **Yes — the only one** | Always |
| **Secretary** (`opensource/community-secretary`) | Script-computed metrics, mirror sync, workspace backup, holding acknowledgments when the lead is rate-limited | Claude Haiku | Holding acknowledgments only — a receipt, never a resolution | Optional, **add second** — takes the bulk of recurring work off the lead |
| **Coding** (`opensource/community-coding`) | Issue/PR triage, security advisories, Dependabot review, docs-currency, maintainer load. Read-only + two narrow draft-PR paths | Claude Haiku | No — headless | Optional; lead does lighter triage standalone otherwise |
| **Marketing** (`opensource/community-marketing`) | Content drafts via PR | Claude | No — headless | Optional, **not stamped by default** |

(`docs-gap-review` sits with the lead, not coding, because it reads the
lead's own `question-ledger.jsonl` — an agent can't read another's
`plugin-data/`.)

**Not a one-way door.** Stamp just the lead today; add others later. To
disable an agent, pause its tasks (`ncl tasks pause`) rather than deleting
the group, so config/memory survive. To add one later: stamp, wire its
destination pair (below), DM the lead to relay config (§3) — same process
at hour one or month six.

Run from the nanoclaw checkout (`cd nanoclaw`, or conversationally via
`claude` in the same directory). `--name` is an internal `ncl`/dashboard
label only — unrelated to the Discord display name or the project name —
pick anything readable, e.g. `"AcmeCRM Manager"`.

```bash
# Stamp — check each response's templateReport for skipped parts, and note
# each group's id: the wiring and vault steps below need them.
./bin/ncl groups create --template opensource/community-manager    --name "Community Manager"
./bin/ncl groups create --template opensource/community-secretary  --name "Community Secretary"
./bin/ncl groups create --template opensource/community-coding     --name "Community Coding"
# Marketing is optional and not stamped by default:
./bin/ncl groups create --template opensource/community-marketing  --name "Community Marketing"

# Install jq on every agent, host-side, before you DM the lead. Every
# template's setup-check.sh needs it, and the lead's own tasks parse JSON
# with it. For the LEAD this must happen here: install_packages rebuilds
# the image and restarts the container on approval, which would kill the
# welcome interview mid-conversation. Sub-agents are headless, so the lead
# can install jq on them itself while stamping — these two lines are only
# needed if you pre-stamped a sub-agent above.
./bin/ncl groups config add-package --id <lead-id> --apt jq
./bin/ncl groups restart --id <lead-id> --rebuild
# …and once per sub-agent you stamped above, with its own <id>.

# Wire sub-agents to the lead — agent-to-agent, NEVER to a channel. One pair
# per sub-agent: `parent` on the child pointing at the lead, a named
# destination on the lead pointing back. A missing pair doesn't error — the
# sub-agent's reports just reach nobody.
./bin/ncl destinations add --agent-group-id <secretary-id>  --local-name parent           --target-type agent --target-id <lead-id>
./bin/ncl destinations add --agent-group-id <lead-id>       --local-name secretary        --target-type agent --target-id <secretary-id>
./bin/ncl destinations add --agent-group-id <coding-id>     --local-name parent           --target-type agent --target-id <lead-id>
./bin/ncl destinations add --agent-group-id <lead-id>       --local-name coding           --target-type agent --target-id <coding-id>
./bin/ncl destinations add --agent-group-id <marketing-id>  --local-name parent           --target-type agent --target-id <lead-id>
./bin/ncl destinations add --agent-group-id <lead-id>       --local-name marketing-agent  --target-type agent --target-id <marketing-id>
```

Sub-agents are headless — `parent` is their **only** outbound path, which is
why every sub-agent task addresses the lead, never the owner (a report
addressed to the owner from a sub-agent goes nowhere; this was a real bug in
three tasks, now fixed).

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

**Your own DM with the lead is the control plane — wire it first.** Set
sender scopes at wiring time: owner DM stays locked to known senders, but
every public channel gets `--sender-scope all` — otherwise each new
community member triggers a "new sender — allow?" prompt, defeating the
point of a public channel. Verify the round trip both ways, then DM the
lead — its `welcome` skill runs the interview (first question: your
GitHub repo), persists config, and relays sub-agent values. Only then wire
the public channels: the lead gets all of them; the reviewer and marketing
get none, by design.

**The secretary is the one exception to "no sub-agent has channel
identity."** It gets one channel wiring, through the *same* Discord bot —
one public identity, two agents allowed to speak, very different scopes:
one channel, read-only elsewhere, no write access, a template-only reply
it's forbidden to compose freely. A receipt, never a resolution.
**Unverified**: whether two groups can wire to the same Discord channel in
your NanoClaw version — test it; fall back to a dedicated channel if not.

**Name the Discord app to visibly match the GitHub bot account** you'll set
up when the lead asks for one (`acmecrm-bot` ↔ "AcmeCRM Bot") — this is the
only agent with a public voice on both platforms, and a mismatch reads as
two different bots.

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

**Hurts:** every change is out-of-framework — pair it with a DM to the lead
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
| `/add-ollama-provider` | **Not used this phase** — see SKILLS-ADOPTION.md | Would route the secretary to a host Ollama model | **Yes** — Dockerfile + `container.json` edits |
| `/add-ollama` (tool) | **Proposed, undecided** | Only if translation volume proves expensive | **Yes** — copies an MCP server, rebuilds image |
| `/add-dashboard` | **Deliberate non-default** | Only if clidash can't answer a real budget question | **Yes** — persistent process, `DASHBOARD_SECRET` |
| `ncl groups config add-mount` | **Recommended once all four are stamped** | Shared repo mirror — see `community-secretary/README.md` | Config + operator-side mount allowlist |
| `/update-skills` | **Break-glass only** | Never in steady state | **Yes**, desyncs from `platform-baseline.json` |

Everything else in NanoClaw's skill catalog was reviewed and is either N/A
for this deployment or rejected with reasons — see
[SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md).

## 2 · Credentials — added when the lead asks, not upfront

**There is no `.env` file in this system, deliberately.** Secrets go in the
OneCLI vault; platform settings belong to the kit's `spec.yaml`; task
parameters (repo names, label text — never secrets) live in each agent's
`plugin-data/<agent>/config.env`. Anything that asks you to put a key in
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

**When the lead asks for a GitHub token** (one per agent it needs — never
one shared token), [PREREQS.md](../PREREQS.md) has the exact URL. The scope
to give each one, so you don't have to work it out live:

| Token | Needs | Never |
|---|---|---|
| Lead | `repo`/`public_repo` — comments, labels, issues | `read:org`, `admin:*`, `delete_repo` |
| Secretary | `COMMUNITY_REPOS` + `MIRROR_REPOS`: Contents/Issues read, PRs read, Contents write on backup repo only | Write anywhere else; issue/PR comment rights |
| Coding | `COMMUNITY_REPOS` only, read-only (+ Dependabot alerts) | Any write scope; `MIRROR_REPOS` |
| Marketing | Content repo only, Contents + PRs read/write | Write on any other repo |
| Backup (optional) | Push to the one backup repo | Nothing beyond it |

If a future feature seems to need broader access, the fix is almost never
"widen this token" — it's a new, narrower, single-purpose credential.

**Set every agent to `selective` secret mode and assign each its own
secret**, as they're added. All four GitHub tokens match the same host — in
the default `all` mode, every agent gets whichever secret matches first,
collapsing your scoped tokens back into one shared token:

```bash
onecli agents list
onecli agents set-secret-mode --id <agent-id> --mode selective   # ×4
```

Optionally add **request-hold approval rules** for anything you can never
allow unattended (publishing, sending mail) — gating at the proxy is
enforcement no prompt can bypass.

**Discord bot** needs, beyond the invite in §1a: nothing further in the
vault — its token lives in `.env`, not here.

**GA4** (only if you want `weekly-analytics-report`): enable the Google
Analytics Data API, OAuth credentials, grant **Viewer** on the property,
note the numeric property ID. Don't enable the Admin API.

**Gmail** (only if you want `inbox-check`): Gmail API, OAuth with
`gmail.readonly` only — this agent never sends. Bring your own Gmail/IMAP
MCP server.

**Optional egress lockdown**: `NANOCLAW_EGRESS_LOCKDOWN=true` forces all
agent traffic through the OneCLI gateway on a Docker `--internal` network
with no direct route out — off by default. See `src/egress-lockdown.ts` if
you want that hardening; nothing here requires it.

### Per-agent OneCLI footprint

Organized by agent instead of by credential — the exact list `onecli apps
connections agent-access` (PREREQS.md §3) should show once everything's
added, and nothing more.

| Agent | Granted | Host | Used by |
|---|---|---|---|
| Lead | GitHub PAT | `api.github.com` | triage, docs-gap-review, release watch, identity check, live replies |
| Lead | Gmail OAuth *(optional)* | `gmail.googleapis.com` | `inbox-check` |
| Secretary | GitHub PAT | `api.github.com` | metrics, GFI health, hygiene audit, draft cleanup |
| Secretary | same PAT, git protocol *(private repos only)* | `github.com` | `repo-mirror-sync` |
| Secretary | Backup push secret *(optional)* | `github.com` | `workspace-backup` |
| Secretary | GA4 OAuth *(optional)* | `analyticsdata.googleapis.com` | `weekly-analytics-report` |
| Secretary | — (public reads only) | `x.com`, `www.linkedin.com`, etc. | `social-metrics-snapshot` |
| Secretary | — (nothing) | — | `unanswered-watch`, `health-check` — local state only |
| Coding | GitHub PAT | `api.github.com` | ops triage, advisory sweep, Dependabot review, docs-currency, contributor health |
| Marketing | GitHub PAT | `api.github.com` | `content-draft-cycle` |

Note where analytics landed: on the **secretary**, not marketing or coding
— judgment work stayed on the metered agents, narration moved to the
cheapest tier. A row that doesn't exist here is a finding: the reviewer and
marketing never appear against Discord, GA4, or social hosts, and the
secretary never appears with a write grant outside its one backup repo.

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

## 3 · Configuration — one conversation, three files

**The default path is the conversation, not file edits.** After the owner
DM is wired (§1a), the lead's `welcome` skill interviews you and persists
everything as runtime config. You edit zero files for any of it.

### The relay

You answer once, in the owner DM; the lead pushes each sub-agent's
parameters over the destination pairs from §1:

| Sub-agent | Keys relayed into `config.env` |
|---|---|
| **Secretary** | `COMMUNITY_REPOS`, `MIRROR_REPOS`, `CONTENT_REPO`, `GA4_PROPERTY_ID`, `GFI_LABEL`, `ACK_GRACE_MINUTES` |
| **Coding** | `COMMUNITY_REPOS` (+ optional `SECURITY_WATCH_REPOS`) |
| **Marketing** | `CONTENT_REPO`, `RELEASE_WATCH_REPO` |
| **Lead** (own) | (+ optional `RELEASE_WATCH_REPOS` — plural, distinct from Marketing's singular key) |

Plus `GITHUB_BOT_USERNAME`, held by all four.

**Check the secretary relay specifically — it fails quietly.** It's the
largest payload, and a missing key isn't an error: the gate exits
`not-configured` and goes back to sleep. Symptom: "stamped and never does
anything," which reads like a broken agent and is an unrelayed key.
`ACK_GRACE_MINUTES` alone has a built-in default (20 min); nothing else
does.

**One thing lives outside the conversation:**

| What | Where | When |
|---|---|---|
| Workspace backup git init/remote/identity | Secretary's group folder | After stamping, host-side |

### The full question list

Nothing blocks you from starting — the interview infers what it can, and
"not now" is a complete answer to anything optional. Skim once, then talk
to the agent.

| # | Asked | Optional? |
|---|---|---|
| 1 | GitHub repo or org | **No** |
| 2 | Which of the four jobs are goals | **No** |
| 3 | Repo map: product/docs/site/marketing | Inferred + confirmed |
| 4 | Docs site URL, language, topic scope | Inferred where possible |
| 5 | Discord channels by tier | Required if using Discord |
| 6 | Security disclosure contact + maintainer list | Required if security is a goal |
| 7 | Social platforms + posting mechanism per one | Optional |
| 8 | Discord invite URL | Optional |
| 9 | GA4 property id | Optional |
| 10 | Model per agent | Defaults offered |
| 11 | GitHub Actions → Discord notifications | Optional |
| 12 | OneCLI dashboard address | Asked once |
| 13 | Docs style (current-state vs version-history) | Enforced on every draft |
| 14 | Audience + tone, in your words | **No** — marketing needs this |
| 15 | Workspace backup repo | Optional but survives a recreate |
| 16 | Bot's GitHub username | **No** |
| 17 | Human backstop for when you're unreachable | **Asked always** — recorded as open risk if none |

After this, the agent walks credential setup, verifies each with a real
call, offers to set up backup itself, and asks one explicit "go" before
activating anything.

### Prefer a file over the live interview?

`onboarding-answers.example.json` is currently absent from the repo (see
SKILLS-ADOPTION.md); if present, copy it, fill in what you know, and the
lead reads it instead of interviewing — asking only about `null`s. Validate
first — it also refuses anything credential-shaped:

```bash
cp onboarding-answers.example.json onboarding-answers.json
$EDITOR onboarding-answers.json
bash scripts/check-onboarding.sh onboarding-answers.json
```

Then put it where the agent can see it (the container only sees its own
workspace):

```bash
cp /path/to/onboarding-answers.json groups/<lead-folder>/
```

DM the lead: *"my answers are in `/workspace/agent/onboarding-answers.json`"*
— it reads, echoes a summary back (check that it matches), asks about what's
missing, persists. Rebuilding later: this file + your `plugin-data/` backup
is the complete recovery set.

**Already installed conversationally?** Export the equivalent file instead
of redoing the interview:

```bash
bash scripts/export-answers.sh <nanoclaw-root> [out.json]
```

Two limits: each agent's `project-config.md` comes back verbatim as
`_project_config_raw` rather than parsed, and anything that's a credential
comes back `null` — the export fails rather than writing one out.

## 4 · Start it — the go-live sequence

The conversational path ends with credential verification, backup setup,
and one explicit "go" that resumes the verified tasks. The manual
equivalent:

```bash
./bin/ncl tasks list --status paused
./bin/ncl tasks run <task-id>     # dry-run each gate
./bin/ncl tasks get <task-id>     # inspect the result
```

(Marketing's tasks won't appear unless you stamped that template — a lower
count than `gen-task-table.sh`'s total is expected, not missing.)

Resume order, safe → side-effect-adjacent:

1. **Outage safety net first** — no credentials, no network: `unanswered-watch`
   (secretary, every 10 min — the reason the secretary exists), `health-check`
   (secretary), `weekly-identity-integrity-check` and `owner-tldr` (lead —
   jq only).
2. **Backup** (`workspace-backup`) — after §3's git setup.
3. **Lead's live response**: `github-first-response`, `release-announcement-watch`
   — safe once `COMMUNITY_REPOS` is set. `docs-gap-review` is safe from day
   one; it stays quiet until support work fills its ledger.
4. **Secretary's gates**, once §3's relay has landed: `repo-mirror-sync`,
   `dev-metrics-report`, `good-first-issue-health`, `repo-hygiene-audit`,
   `draft-cleanup`, `ready-to-merge`, `weekly-analytics-report`.
   `contributor-nudge` needs `dev-metrics-report`'s ledger to run twice
   first. Each exits `not-configured` silently if its key is missing —
   resume, then check they did something.
5. **Coding**: `github-ops-triage`, `security-advisory-sweep`,
   `dependabot-pr-review`, `docs-currency-watch`, `contributor-health-review`.
6. **Ungated tasks last** — nothing stops them burning a wake on an
   unconfigured service: `social-metrics-snapshot` (only once a
   page-reading tool is confirmed in the secretary's container — Claude's
   built-in web fetch or [`agent-browser`](https://nanoclaw.dev/skills/agent-browser))
   and the lead's `inbox-check` (only once an email MCP is connected).
7. **Marketing** (if stamped): `content-draft-cycle`.
8. **Never run both** the lead's `daily-github-triage` and the coding
   agent's `github-ops-triage` — the former is the lead's standalone
   fallback; running both double-reports every issue. Pause it when you
   stamp coding.

Smoke-test: post in a support-tier channel (expect an unprompted reply),
@mention the lead in a dev-tier channel (expect a reply only because you
tagged it), DM the lead to ping every sub-agent (exercises all three
destination pairs — a silent sub-agent means a missing destination, not a
broken agent). If you stamped the secretary, test the holding
acknowledgment path once — it's the one behavior that only shows up when
the lead can't answer.

**"Resumed" is not "ready."** Walk the 15-point ready gate in
[CHECKPOINTS.md](CHECKPOINTS.md) before calling it live. Everything after
— token budget, the task reference, the update policy, teardown — is in
[OPERATIONS.md](OPERATIONS.md) and [UNINSTALL.md](UNINSTALL.md).
