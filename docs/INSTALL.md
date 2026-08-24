# Install runbook

The full path from nothing to a live system: prerequisites → keys → sandbox →
stamp/wire → configuration → go-live. Read [PREREQS.md](../PREREQS.md) first
for the credential story; [OPERATIONS.md](OPERATIONS.md) covers everything
after go-live.

Setup is a conversation, not a form — you'll DM the stamped agent and it
interviews you. If you'd rather see the whole question set before you start,
jump to §6's prep sheet below.

## 0 · Prerequisites — what you need before starting

### Apps / accounts

| You need | Why | Required? |
|---|---|---|
| **Docker Desktop with `sbx`** (Docker Sandboxes) | The micro-VM everything runs in | Required |
| **A Discord server you admin** (Manage Server permission) | To create/invite the bot and wire channels | Required |
| **A GitHub account for the bot** — make a dedicated service account (e.g. `yourproject-bot`), not your personal one | All GitHub work appears as this identity; you'll cut 4 scoped tokens from it | Required |
| **Google Cloud project + GA4 property access** | `weekly-analytics-report` task | Optional |
| **A shared project inbox** (e.g. Gmail) | the lead's `inbox-check` task | Optional |

Skipping an optional service costs nothing: its task ships paused and its
script gate exits `not-configured` even if resumed.

### Disk and memory — a rough budget, not a measured one

Nobody has published exact numbers for this stack, so treat this as a
planning budget and verify once it's running: **10–15 GB free disk** (the VM
image, the nested NanoClaw/OneCLI/Postgres images, the agent containers, plus
your repo clones and mirrors) and **a few GB of RAM** while it's up (Postgres,
the gateway, and up to four agent containers, though idle/gated agents use
very little).

(A local-model provider for the local agent — e.g. Ollama — was evaluated and
set aside for now; see [SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md). All four
agents currently run cloud-side, so there's no separate host-model RAM budget
to plan against.)

After first boot, get real numbers instead of guessing further:

```bash
docker system df                       # actual image/volume disk usage
docker stats                            # live memory/CPU per container
```

If memory is tight, the levers in order: pause optional tasks, run one agent
container at a time. Deleting an agent is the last resort, not the first.

### Tokens / keys — how to get each one

Collect these before setup; you'll register them in OneCLI in step 4. **Never
paste any of them into the sandbox, a template file, or a chat with an agent** —
they go into the OneCLI vault through its dashboard, and the proxy injects them
into outbound requests. **[PREREQS.md](../PREREQS.md)** has the exact URL for
each one, the CLI alternative to the dashboard, and — just as important — how
to audit and rotate them later without guessing whether a change "took".

**There is no `.env` file in this system — deliberately.** If you're coming
from a bare-metal NanoClaw install that kept keys in one: don't carry it
forward. Secrets go in the vault (above); platform settings belong to the
kit's `spec.yaml` and first-boot wizard; task parameters (repo names,
project IDs, label text — never secrets) live in each agent's
`plugin-data/<agent>/config.env`. Anything — a doc, a tool, an agent — that
asks you to create a `.env` containing a key is violating this system's own
rules; refuse it.

**GitHub — four tokens from the bot account, one per agent** (github.com →
Settings → Developer settings → Personal access tokens). One token per agent
is the point: four tokens are what make the per-agent least-privilege table in
§4 enforceable at all, and they all match the same API host, which is why §4
also switches every agent to `selective` secret mode.

1. **Lead token** (classic): scope `repo` (or `public_repo` for public-only
   projects) — this one comments on issues, so it needs write on issues/PRs.
   **Not `read:org`**: nothing here reads org membership or teams (listing an
   org's repos, which the welcome interview does, needs no such scope) —
   dropped as an unjustified grant. Never `admin:*`, never `delete_repo`.
2. **Local token** (fine-grained): the widest *repo list* of the fine-grained
   three, and close to the narrowest *permissions* — it covers
   `COMMUNITY_REPOS` **plus**
   `MIRROR_REPOS` (mirroring is this agent's job, not the reviewer's) with
   Contents/Issues **read**, Pull requests **read** (`draft-cleanup` only
   looks at stale drafts, it doesn't touch them), and **Contents write on the
   backup repo and nothing else** (`workspace-backup`). A fine-grained
   token's repo list gates everything the token does, including reads of
   public data, so a mirror repo left off the list shows up as
   `repo-mirror-sync` quietly never syncing that one.
3. **Coding token** (fine-grained): `COMMUNITY_REPOS` only, **read-only**
   (Contents/Issues/PRs read; add Dependabot alerts read for the advisory
   sweep). **No `MIRROR_REPOS`** — mirroring moved to the local agent, so
   listing the mirror set here is now surplus access with no task behind it.
   A classic `repo`-scope PAT is inherently read/write — don't use one
   here; this agent never posts, so give it a token that *can't*.
4. **Marketing token** (fine-grained): Fine-grained tokens → limit to the
   **content repo** → Contents + Pull requests read/write. It opens draft
   PRs and nothing else. **If the brand/strategy source or the release-watch
   repo (content-draft-cycle's `RELEASE_WATCH_REPO`) is a *different* repo
   from the content repo, add that repo too** — a fine-grained PAT's repo
   scope is an allowlist covering everything that token does, including
   reads of otherwise-public data. Leaving a second repo off the list is the
   #1 cause of "why did this silently never trigger" — `setup-check.sh`
   (§3's monitoring step, or run anytime) catches it as
   `brand_source_access`/`release_watch_repo_access: unreachable`.
   Marketing is not stamped by default (see step 3), so skip this token
   entirely until you actually stamp it.
5. If you enable workspace backup, the push goes to `github.com` (git) — a
   **separate vault host match** from `api.github.com` (REST), so it's one
   more vault entry regardless. `workspace-backup` belongs to the **local**
   agent, so this is the local token's `github.com` counterpart: reuse that
   token, or better, cut a fifth one scoped to just the backup repo so a
   push credential and a read credential aren't the same string.

**GA4** (optional): In Google Cloud console, enable the **Google Analytics Data
API** on a project and create OAuth credentials for it. In GA4 Admin, grant the
account **Viewer** on the property. Note the numeric **property ID** (Admin →
Property settings). You do *not* need the Admin API — don't enable it.

**Gmail** (optional): enable the Gmail API, OAuth consent with the
**`gmail.readonly`** scope only — this agent never sends. You'll also need a
Gmail/IMAP MCP server of your choice (not bundled; provider-dependent).

**Discord**: no key to collect up front — the kit ships an `/add-discord` skill
that walks bot creation and invite during setup (step 3). **Invite with
least-privilege permissions** (Send Messages, Embed Links, Attach Files, Read
Message History — not Administrator, not broad moderation scopes); add more
later only if a real need appears. This is a Discord policy expectation, not
just good hygiene — see `discord-mechanics.md`'s platform-rules section.
**Name the Discord application to visibly match the GitHub bot account**
(e.g. `acmecrm-bot` on GitHub ↔ "AcmeCRM Bot" as the Discord display name) —
this is the only agent with a public voice on both platforms, and a
mismatched pair of names reads as two different bots to your community.

---

## 1 · Start the sandbox

Pin the image by **digest**, taken from
[`platform-baseline.json`](../platform-baseline.json) — the exact `sha256`
this template set was last verified against:

```bash
DIGEST=$(jq -r .image_digest ../platform-baseline.json 2>/dev/null || jq -r .image_digest platform-baseline.json)
sbx run --name nanoclaw --kit "docker.io/sbx/nanoclaw-kit@${DIGEST}" nanoclaw
```

(The trailing `nanoclaw` is the kit's app argument — keep it as-is. This is
the **prebuilt image**, pulled directly — not the git-kit-source form.)

A digest pull is content-addressed: the same `sha256` is byte-for-byte the
same tested package everywhere, so what you run is exactly what was verified
— not whatever a floating tag points at today. The full update policy
(including the hard rule: **never `git pull` NanoClaw inside a running
sandbox** — there is no in-place upgrade path and it corrupts the deployment)
is in [OPERATIONS.md → Staying up to date](OPERATIONS.md).

**Why this tag, not the git-kit-source path** (`--kit
"git+https://github.com/docker/sbx-kits-contrib.git#dir=nanoclaw"`, which is
the OTHER alternative — also still available, see below): that git-sourced
kit's own `spec.yaml` pins `nanoco/nanoclaw:sbx-claude-alpha`, and checking
the registry directly, **every tag `nanoco/nanoclaw` has ever published is
`alpha.N`** (through `alpha.10` as of this check) — there is no non-alpha
release of that image at all yet. `sbx/nanoclaw-kit:latest` — a Docker Hub
namespace distinct from `nanoco`, date-tagged (`20260820-<sha>`, pushed the
same day as this check) rather than alpha-labeled — is the one path that
avoids the "alpha" tag string, so that's now the default here.

**The honest limit of this check**: a tag name without "alpha" in it is not
the same claim as "the underlying NanoClaw software has graduated past
pre-1.0." I could not confirm from the registry alone what `sbx/nanoclaw-kit`
builds from internally, and since `nanoco/nanoclaw` — the actual upstream
project — has no non-alpha release at all, treat this whole stack as pre-1.0
regardless of which kit path you use. If that maturity level matters for your
deployment, that's worth confirming directly with the maintainers rather than
inferring further from tag names.

**Alternatives, both still valid**: the git-kit-source form above (same
underlying alpha image, resolved via the kit's own spec instead of a direct
pull), or a local clone `--kit ./nanoclaw` — the local route is also how you
edit the network allowlist, see step 5.

What this buys you, security-wise — and why it's the recommended host:

- **Micro-VM boundary.** NanoClaw's host process, OneCLI (dashboard + gateway +
  Postgres), and every nested per-session agent container run inside one VM
  with its own inner Docker daemon — nothing touches your host's daemon.
- **Default-deny egress.** Only hosts on the kit's allowlist are reachable
  (Docker registries, OneCLI, Anthropic, GitHub, npm, the chat platforms).
  Everything else gets `502 Bad Gateway` from the sandbox itself — enforcement
  lives *outside* anything an agent can influence.
- **No raw keys inside.** Credentials live in the OneCLI vault and are injected
  into outbound HTTPS at the proxy; the kit's own instructions forbid pasting
  keys.

First boot asks before pulling nested images (a few minutes), then runs
NanoClaw setup. **At the provider prompt, Claude accepts a subscription, an
OAuth token, or an Anthropic API key.** A subscription avoids per-token cost
but shares ONE usage window with your own Claude Code sessions — including the
break-glass session you would need to repair a broken deployment. This is the
most consequential choice in the install; read
[OPERATIONS.md → Model budget](OPERATIONS.md) first. **Note the port
mappings `sbx run` prints**: OneCLI dashboard (`10254`) is where you'll
register credentials; gateway is `10255`; webhook is `3000`. Keep this session
open; NanoClaw stops when it closes.

## 2 · Load the templates into the sandbox

The install's templates directory is `/home/agent/nanoclaw/templates/` inside
the VM.

**Decide your schedule timezone NOW — this is the one thing that is
genuinely expensive to change later.** Task schedules are cron lines in each
task file's frontmatter, the kit pins `TZ=UTC`, and frontmatter is not
runtime-editable — so after stamping, changing a time means cancel-and-recreate
per task. The shipped times (see OPERATIONS.md → "Shipped times") are UTC. If
UTC doesn't suit the owner's working day, edit the `schedule:` lines in your
local copy of the task files (run `bash scripts/gen-task-table.sh --counts`
for the current total) **before** the stamp step below — it's a one-minute
edit now versus one recreate per non-UTC-friendly task later. Everything else is collected
conversationally after wiring; pre-stamp file fill-ins are optional defaults,
and personas mount read-only once stamped.

(The welcome interview asks about timezone too, but only to record and confirm
it — by then this cheap window has closed, which is exactly why the decision
belongs here.)

Don't count or transcribe those crons by hand. From your local copy of this
repo, `bash scripts/gen-task-table.sh` prints the authoritative
task/agent/schedule table straight from the task files' frontmatter — so
what you're editing against is what actually ships, not a table someone
retyped. `--counts` gives just the headline numbers, and `--check` fails if
these docs have drifted from the files. **One rule when you retime anything:
no two tasks may share a cron minute** — a 16 GB host can't absorb two
simultaneous wakes, and `unanswered-watch` owns the round `*/10` minutes
deliberately, so retime around it rather than into it.

**A — from a git staging repo** (github.com is already allowlisted):

```bash
sbx exec nanoclaw bash -lc '
  git clone --depth 1 https://github.com/<you>/<staging-repo>.git /tmp/tpl &&
  mkdir -p /home/agent/nanoclaw/templates &&
  cp -R /tmp/tpl/support /tmp/tpl/local /tmp/tpl/engineering /tmp/tpl/marketing /home/agent/nanoclaw/templates/'
```

**B — stream your local copy over exec stdin** (no repo needed):

```bash
sbx exec nanoclaw mkdir -p /home/agent/nanoclaw/templates
tar -C /path/to/nanoclaw-templates -cf - support local engineering marketing \
  | sbx exec -i nanoclaw tar -C /home/agent/nanoclaw/templates -xf -
```

## 3 · Stamp the agents and wire them

**What each one actually does — read this before naming or skipping any:**

The four agents are split by **model tier**, not by subject: capable models
where judgment is needed, a free local model where reliability matters more
than capability.

| Agent | Job | Model | Public voice? | Required? |
|---|---|---|---|---|
| **Lead** (`support/community-support`) | Talks to your community on Discord and GitHub: answers questions, triages bugs, escalates security/abuse, watches releases, reviews docs gaps, and relays the three sub-agents' work | Claude Sonnet | **Yes — the primary, full voice** | Always — nothing works without it |
| **Local ops** (`local/community-local`) | The narration tier: script-computed metrics/analytics/telemetry, keeps the repo mirrors fresh, runs the workspace backup, and posts holding acknowledgments when the lead is rate-limited or down | Claude Haiku (cloud; a local-model provider was tried and set aside for now — [SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md)) | Holding acknowledgments only — a receipt, never a resolution | Optional but **strongly recommended, and the one to add second.** It takes the bulk of the recurring, mechanical work off the lead |
| **Coding** (`engineering/community-coding`) | Issue/PR triage and security-advisory review — 2 tasks, read-only, drafts everything for the lead. **Not** metrics, telemetry, or docs gaps: metrics/telemetry moved to local ops, and `docs-gap-review` moved to the lead | Claude Haiku | No — headless, no channel wiring at all | Optional. The lead does its own lighter-weight triage standalone if this isn't stamped |
| **Marketing** (`marketing/community-marketing`) | Content drafts via PR, in the audience's language — 1 task | Claude | No — headless, no channel wiring at all | Optional, and **not stamped by default.** Skip it until you actually want content drafted |

Why `docs-gap-review` sits with the lead and not the reviewer, since it reads
like reviewer work: it consumes `question-ledger.jsonl`, which only the lead
writes, and an agent cannot read another agent's `plugin-data/`. On the
engineering side it was permanently dead — always zero input, never a finding.

**You don't have to stamp all four now, and this isn't a one-way door.**
Stamp just the lead today and add the others later — the lead works standalone.
If you're adding exactly one, add **local ops**: it takes the bulk of the
recurring, mechanical work off the lead so Sonnet-class judgment is spent
only where it's needed. To **disable** an agent later: pause all its tasks
(`ncl tasks list --status active` on its group, then `ncl tasks pause` each
— or just stop resuming new ones) rather than deleting the group, so its
config and memory stay intact if you re-enable it. To **add** one later:
stamp it fresh, wire its destination to the lead exactly as below, and DM
the lead to relay config (see §6's relay table for which keys each one
needs) — same process, whether done at hour one or month six.

Run inside the sandbox (`sbx exec -it -w /home/agent/nanoclaw nanoclaw bash`,
or drive it conversationally via `sbx exec -it -w /home/agent/nanoclaw
nanoclaw claude`):

**`--name` is never asked in the welcome interview — it's yours to set here,
and only here matters where.** It's purely an internal `ncl`/dashboard label
(what you see in `ncl groups list`), unrelated to the Discord bot's display
name (set when you create the bot application) and unrelated to the
project name the welcome interview infers from the GitHub repo. **Pick a
name for each one now** — the examples below (`"Community Support"` etc.)
are placeholders, not requirements; something like `"AcmeCRM Support"` /
`"AcmeCRM Local Ops"` / `"AcmeCRM Coding"` / `"AcmeCRM Marketing"` makes
`ncl groups list` readable once you have more than one project's agents
running. Nothing but a human looking at that list ever reads this string.

```bash
# Stamp — check each create response's templateReport for skipped parts,
# and note each group's id from the response: the destination wiring below
# and the OneCLI selective-mode step need them.
./bin/ncl groups create --template support/community-support     --name "Community Support"
./bin/ncl groups create --template local/community-local         --name "Community Local Ops"
./bin/ncl groups create --template engineering/community-coding  --name "Community Coding"
# Marketing is OPTIONAL and not stamped by default — run this line only if you
# actually want content drafted now. Its token (§0) is needed only if you do.
./bin/ncl groups create --template marketing/community-marketing --name "Community Marketing"

# Wire sub-agents to the lead — agent-to-agent both ways, NEVER to a channel.
# One pair per sub-agent: `parent` on the child pointing at the lead, and a
# named destination on the lead pointing back. A missing pair doesn't error —
# the sub-agent's reports just reach nobody.
./bin/ncl destinations add --agent-group-id <local-id>     --name parent    --target <lead-id>
./bin/ncl destinations add --agent-group-id <lead-id>      --name local     --target <local-id>
./bin/ncl destinations add --agent-group-id <coding-id>    --name parent    --target <lead-id>
./bin/ncl destinations add --agent-group-id <lead-id>      --name coding    --target <coding-id>
./bin/ncl destinations add --agent-group-id <marketing-id> --name parent    --target <lead-id>
./bin/ncl destinations add --agent-group-id <lead-id>      --name marketing --target <marketing-id>
```

Sub-agents are headless and this `parent` destination is their **only**
outbound path — which is why every sub-agent task addresses the *lead*, never
the owner. A sub-agent has no owner DM, so a report addressed to the owner
goes nowhere at all (this was a real bug in `health-check`,
`workspace-backup` and `unanswered-watch`, now fixed). Lead-owned tasks may
address the owner directly; that's correct for them.

The local agent stamps on the cloud default (Haiku) same as the others —
no separate host model provider to wire up for this phase.

(Credential registration is step 4 — the welcome interview below runs before
it by design, so its verification pass will first report services as unwired;
it walks you through the vault entries and re-verifies. That's expected, not
broken.)

Then connect Discord: in the sandbox's Claude Code session, run
`/add-discord` and follow it (bot creation, invite, channel wiring). Invite
the bot with the **least-privilege permission set from §4's table** (Send
Messages, Embed Links, Attach Files, Read Message History) — *you* need
Manage Server rights on the guild to do the inviting; the *bot* never gets
them. And before the first support-channel test: enable the **Message
Content privileged intent** in the Discord developer portal (Bot → Privileged
Gateway Intents) — it isn't part of the invite screen, and without it the bot
joins fine, answers @mentions, and silently never auto-replies in support
channels. **The first wiring is your own DM with the
lead — the control plane; nothing works without it.** Set sender scopes at
wiring time: the owner DM stays locked to known senders, but **every public
channel wiring gets the open sender scope** (`--sender-scope all`) — otherwise
each new community member triggers a "new sender — allow?" approval prompt,
which defeats the point of a public support channel. Verify the round trip in
both directions, then DM the lead: its `welcome` skill runs the onboarding —
first question is the project's GitHub repo, from which it infers a proposed
config, confirms with you, persists it as runtime config in `plugin-data/`,
and relays the sub-agents' values over their destinations. (Pre-stamp file
fill-ins still work as defaults; the conversational config wins.) Only then
wire the public channels + guild catch-all — **the lead gets all of them, and
the reviewer and marketing get none**: they have no channel wiring at all and
cannot post publicly even if instructed to, which is single-voice enforced by
absence.

**The local agent is the one deliberate exception, and it's worth stating
precisely** — the older blanket claim that no sub-agent has any channel
identity is no longer true. Holding acknowledgments only work if something
can actually speak while the lead can't, so the local agent gets **one**
channel wiring and posts through the *same* Discord bot — one public identity
still, not a second bot. Its restriction is enforced by *scope* rather than
absence: one channel, read-only credentials everywhere else, no write access,
and a template-only reply it is forbidden to compose freely. It is a receipt
("we've seen this, a human/the lead will follow up"), never a resolution.
**Unverified**: whether two groups can both wire to the same Discord channel
in your NanoClaw version — test it on the real install rather than assuming
it, and fall back to a dedicated acknowledgment channel if not.

After setup, everything runs through Discord; the sandbox Claude CLI is
break-glass admin only (see below).

## Break-glass admin: the Claude CLI — how it helps, how it hurts

`sbx exec -it -w /home/agent/nanoclaw nanoclaw claude` opens a Claude Code
session inside the sandbox with direct access to the install — files, `ncl`,
the group workspaces. Reserve it for a **bad state**: the owner DM broken, an
agent stuck in a verification deadlock, task/wiring surgery, log forensics.

**How it helps:**
- It operates on the *system* instead of negotiating with an *agent* — when
  an agent can't verify you, stop arguing in-channel and act at the layer you
  control.
- It works when Discord doesn't: wiring repair, `/add-discord`, reading
  journals and task tables directly.
- It stays inside the sandbox boundary — same egress allowlist, no new trust
  domain, no credentials exposed (the vault still injects at the proxy).

**How it hurts:**
- Every CLI change is an out-of-framework edit — exactly what drift detection
  flags. Pair each intervention with a one-line DM to the lead afterward ("I
  changed X via CLI at Y"), or expect (and calmly answer) an ask-don't-lock
  question from the integrity gate.
- It bypasses every gate: no OneCLI request-holds, no single-voice review, no
  public-action ledger entry. Nothing stops a typo'd `ncl tasks` command or a
  bad file edit. Its power is unaudited unless you narrate it.
- Habit decay is the real risk: if routine config drifts into CLI edits, the
  owner DM stops being the single authoritative thread, config becomes
  untracked again, and you've rebuilt the exact "who changed this?" ambiguity
  the single-voice design exists to prevent. **Discord for operations, CLI
  for surgery.**
- A CLI session is itself an agent with tools — its conclusions deserve the
  same verify-don't-vibe discipline as anything else.

Note this doctrine applies to **operations after go-live**. During initial
setup (steps 1–7 above), CLI-driving is the intended path, not an exception.

**FYI — `/debug` is your first move in this session, not a separate
install.** It's a built-in NanoClaw skill (nothing to add, nothing to
configure): run `/debug` inside this same break-glass Claude Code session
and it walks logs, env vars, mounts, and MCP connectivity for you instead of
you doing it by hand. Reach for it before manual log archaeology.

## Monitoring: clidash (do this once, here)

While you're in this same sandbox Claude Code session, also set up
[`clidash`](https://nanoclaw.dev/skills/clidash) — a read-only web dashboard
(groups/sessions/channels/users, message-activity charts, log tails) built
from `ncl`'s own JSON output. Zero dependencies, no build step, doesn't touch
NanoClaw's source, and needs no vault entry (its own local secret, if any,
never leaves this machine):

```bash
/add-clidash
cd tools/clidash && cp clidash.config.example.json clidash.config.json
node server.js   # binds 127.0.0.1:4690 by default
```

Reach it the same way as the OneCLI dashboard — locally, or over Tailscale
for remote checks (§4 below has the exact `serve` command; point it at
clidash's port instead of 10254). It's the default monitoring surface for
this deployment. The heavier `dashboard` skill (live push, token-usage and
context-window numbers) is a deliberate non-default — see
[SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md) for why, and add it later only
if you hit a real "which task is burning budget" question clidash can't
answer.

## Platform skills — the one authoritative list

**The template format can't declare these.** Agent Plugins 1.0.0 has no
dependency field, so a template ships its own *agent* skills
(`skills/<name>/SKILL.md` — those install with the template, nothing to do)
but cannot declare **platform** skills. Those are operator actions, and this
is the single list. It's also the replay checklist for a recreate: anything
marked *modifies install* has to be re-applied after
[OPERATIONS.md](OPERATIONS.md)'s refresh, or you lose it silently.

| Skill | Status | When | Modifies install? |
|---|---|---|---|
| `/add-discord` | **Required** | Step 3, in the sandbox Claude session. Owner DM wiring first, then public channels after the interview | No — config only |
| `/debug` | Built-in, nothing to install | Any time, from a break-glass session. First move for a container-level problem | No |
| `/add-clidash` | **Recommended** | Right after step 3 (see the monitoring section above) | Copies `tools/clidash`; no source edit |
| `/add-ollama-provider` | **Not used for this phase** — evaluated and set aside; see [SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md) | Would route the local group to a host Ollama model instead of the cloud default. Revisit once the system is verified end-to-end on the cloud default | **Yes** — extends `ContainerConfig`, edits the Dockerfile (chmod 777), writes per-group `container.json`. Replay on recreate |
| `/add-ollama` (the tool) | **Proposed, undecided** | Only if bilingual translation volume proves expensive. Gives an agent a local model to *call* while it stays on Claude — the lead's case, never the coding agent's | **Yes** — copies an MCP server into the source tree and rebuilds the image. Replay on recreate |
| `/add-dashboard` | **Deliberate non-default** | Only if clidash can't answer a real "which task is burning budget" question | **Yes** — wires a pusher into `src/index.ts`, runs a persistent process, adds `DASHBOARD_SECRET`. Replay on recreate |
| `/update-skills` | **Break-glass only** | Never in steady state — it's in-place mutation, which the update policy forbids. Acceptable for an urgent upstream channel fix that can't wait for a kit image | **Yes**, and it desyncs you from `platform-baseline.json` — note it and do a digest-pinned recreate as soon as one exists |

Everything else in NanoClaw's 52-skill catalog was reviewed and is either
not applicable to a sandbox-kit deployment or rejected with reasons — see
[SKILLS-ADOPTION.md](../SKILLS-ADOPTION.md) rather than re-litigating.

## 4 · Register credentials in OneCLI

### Reaching the dashboard from wherever you actually are

`sbx run` publishes the OneCLI dashboard on port `10254` — but that port is
bound to **the sandbox host machine's own loopback**. `http://127.0.0.1:10254`
only resolves on that machine; open it from your phone or another laptop and
there's nothing there. This is a documented OneCLI gotcha, not a sandbox quirk
— the gateway itself distinguishes **host access** (`127.0.0.1`, or your own
LAN/Tailscale IP) from **container access** (`host.docker.internal`, how
agent containers reach it over the docker bridge) as two different addresses
for two different callers.

**If you only ever open the dashboard from the host machine, `localhost:10254`
is fine — skip this.** If you check in from elsewhere, give the sandbox host a
stable address reachable from anywhere without opening the port to the public
internet: **[Tailscale](https://tailscale.com)** (free for personal use) is
the recommended way — install it on the host and on whatever device you check
in from (`tailscale up` on each), then route the port onto your tailnet as
**raw TCP** (not HTTPS termination — this keeps the exact plain-`http://`,
same-port URL shape the dashboard already uses):

```bash
tailscale serve --tcp=10254 tcp://localhost:10254 --bg
```

Verify with `tailscale serve status`, then open
`http://<host's-tailscale-ip>:10254` from any device on the tailnet — that's
the URL the welcome interview should be given (never `funnel`, which exposes
to the public internet; this dashboard holds credentials). To undo:
`tailscale serve --tcp=10254 off`. The welcome interview asks for this address
once and persists it — whatever you give it, the lead uses that exact one for
every future dashboard link, instead of assuming localhost.

The model credential (what NanoClaw uses to run Claude — subscription, OAuth
token, or API key) lives in the same dashboard's **LLMs** tab, separate from
the **Apps**/**Custom** tabs above — one more reason a working remote address
is worth setting up once.

**Version note**: OneCLI has its own release line independent of NanoClaw
(`versions.json` pins a specific gateway version; there's deliberately no
automatic compatibility check). If credential calls fail with what look like
transient 404s that never clear, your gateway may predate the `/v1` API the
current SDK expects — run the detect steps NanoClaw's own
`docs/onecli-upgrades.md` gives before assuming it's a template problem.

For each credential from step 0, create a vault secret matched to its API host:

| Secret | Host match | Auth style |
|---|---|---|
| GitHub lead token | `api.github.com` | `Authorization: Bearer` |
| GitHub local token | `api.github.com` | `Authorization: Bearer` |
| GitHub coding token | `api.github.com` | `Authorization: Bearer` |
| GitHub marketing token (only if marketing is stamped) | `api.github.com` | `Authorization: Bearer` |
| GitHub backup push (optional — the **local** agent's) | `github.com` | `Authorization: Bearer` |
| GA4 OAuth (optional) | `analyticsdata.googleapis.com` | OAuth 2.0 Bearer |
| Gmail (optional) | `gmail.googleapis.com` | OAuth 2.0 Bearer |

**Then set every stamped agent to `selective` secret mode and assign each its
own GitHub secret** — all four tokens match the same host, and in the default
`all` mode every agent would get whichever matches first, collapsing your
scoped tokens back into shared access. With four tokens on one host this
matters more than it did with three, not less:

```bash
onecli agents list
onecli agents set-secret-mode --id <agent-id> --mode selective   # ×4
# assign each agent its own secret in the dashboard
```

Optionally add **request-hold approval rules** in the dashboard for anything
you can never allow unattended (publishing, sending mail, closing/merging) —
gating the outbound request at the proxy is enforcement no prompt can bypass.

### Least privilege — exactly what each bot does, and nothing more

One canonical list, so "does it need that?" always has a checkable answer
instead of a guess. Anything not listed under **Needs** is deliberately
**never granted**, not an oversight.

**Discord bot** (exactly one, for the whole system). It's the lead's voice, and
the **local agent posts its holding acknowledgments through this same bot** —
one bot application, one public identity, two agents allowed to speak through
it with very different scopes. The **reviewer and marketing have no Discord
identity at all** and cannot post even if instructed to. The local agent's
limit isn't absence, it's scope: one channel, template-only text, no write
credentials anywhere else. Permissions below are the bot's, so they're the
union of both — and they're already minimal, which is why sharing one bot
doesn't widen anything:

| | |
|---|---|
| Needs | Send Messages, Embed Links, Attach Files, Read Message History, and the **Message Content privileged intent** (justified: auto-reply in support channels means reading messages the bot wasn't @mentioned in — this is the one privileged grant this system needs, and it's why 100+ guild deployments trigger Discord's own bot verification, see `discord-mechanics.md`) |
| Never | Administrator, Manage Server, Manage Roles, Manage Channels, Manage Messages (deleting others' messages), Kick/Ban/Timeout Members, View Audit Log — none of this is moderation, and it never will be from this bot |

**GitHub tokens** (four, one per agent, least-privilege split — never one
shared token):

| Token | Needs | Never |
|---|---|---|
| Lead | `repo` (or `public_repo`) — comments, labels, opens issues | `read:org`, `admin:*`, `delete_repo`, org/team scopes |
| Local | Fine-grained over `COMMUNITY_REPOS` **+ `MIRROR_REPOS`**: Contents + Issues read, PRs read (`draft-cleanup`), and Contents **write on the backup repo only** | Write on anything but the backup repo; issue/PR comment rights — it never replies on GitHub, only on its one Discord channel |
| Coding | Fine-grained over `COMMUNITY_REPOS` only, **read-only**: Contents + Issues + PRs read; + Dependabot alerts read if the security sweep is enabled | Any write scope at all — this agent never posts, so its token literally cannot. Also **not** `MIRROR_REPOS`: mirroring is the local agent's task now, so those repos would be access with no task behind it |
| Marketing | Fine-grained, **content repo only**: Contents + PRs read/write (add `RELEASE_WATCH_REPO` if it's a different repo) | Write on any repo but the content one; org-wide scopes |
| Backup (optional) | Push to one backup repo (`github.com` host match) — assigned to the **local** agent, which owns `workspace-backup` | Nothing beyond that repo |

**The instinct to check, always**: if a future feature seems to need broader
access, the fix is almost never "widen this token" — it's "does this actually
need a new, narrower, single-purpose credential instead." Ask before granting;
see "Default to free tools"' sibling rule in each persona for the same
discipline applied to scope, not just cost.

### Per agent: the complete OneCLI footprint, in one place

The tables above are organized by credential; this one is organized by
**agent**, across every service, not just GitHub — it's the exact list
`onecli apps connections agent-access` (PREREQS.md §3) should show for each
one, and nothing more. Every row exists because a specific task reads it;
anything else the live command shows for an agent is a finding, not a
formality.

| Agent | Secret mode | Granted | Host | Used by |
|---|---|---|---|---|
| Lead | `selective` | Lead GitHub PAT | `api.github.com` | `daily-github-triage`, `docs-gap-review`, `release-announcement-watch`, `weekly-identity-integrity-check`, live issue/PR replies |
| Lead | `selective` | Gmail OAuth *(optional)* | `gmail.googleapis.com` | `inbox-check` — an inbox is a support channel, so it belongs to the agent that owns support escalation |
| Local | `selective` | Local GitHub PAT | `api.github.com` | `dev-metrics-report`, `good-first-issue-health`, `repo-hygiene-audit`, `draft-cleanup` |
| Local | `selective` | same PAT, git protocol *(only for private repos)* | `github.com` (git) | `repo-mirror-sync` — public repos need no credential |
| Local | `selective` | Backup push secret *(optional)* | `github.com` (git) | `workspace-backup` |
| Local | `selective` | GA4 OAuth *(optional)* | `analyticsdata.googleapis.com` | `weekly-analytics-report` |
| Local | — (no vault secret) | Sandbox allowlist entries only, public pages | `x.com`, `www.linkedin.com`, etc. | `social-metrics-snapshot` — reads public profiles, no credential exists to grant |
| Local | — (no secret, no network) | nothing at all | — | `unanswered-watch`, `health-check` — local message/container state only. **This is why they survive the outage they compensate for**: nothing to fail, nothing to expire |
| Coding | `selective` | Coding GitHub PAT | `api.github.com` | `github-ops-triage`, `security-advisory-sweep`, `dependabot-pr-review`, `docs-currency-watch`, `contributor-health-review` — 5 tasks (a 6th, `posthog-weekly-review`, is removed for now) |
| Marketing | `selective` | Marketing GitHub PAT | `api.github.com` | `content-draft-cycle` — its only task |

Note where the analytics/telemetry rows landed: **on Local, not Marketing or
Coding.** That's the whole restructure in one table — the metered agents kept
judgment work, and everything that is "run a script, narrate the numbers"
moved to the tier that never runs out.

**A row that doesn't exist here is a finding, not a formality.** Concretely:
the reviewer and marketing agents never appear against Discord at all;
neither of them appears against GA4, the social hosts, or `github.com` git;
and the local agent never appears with a write grant outside the single
backup repo. `selective` mode (not the default `all`) is
what makes any of this enforceable — in `all` mode every agent gets every
secret whose host matches, and with four PATs on `api.github.com` that
collapses this entire table back into one shared token.

### Confirm identity, don't assume it (and audit what's already connected)

**[PREREQS.md](../PREREQS.md)** has the full audit and rotation runbook using
`onecli`'s real CLI — `secrets list`, `apps connections agent-access` (the
direct, verifiable answer to "does this agent have more access than it
needs"), and `secrets update` for safe in-place rotation with no downtime.
Run it once after any setup, and again after any credential change.

A scoped token is not the same guarantee as the *right account* holding it —
it's easy to paste a personal access token by mistake and have every public
GitHub action quietly appear to come from the owner, not the bot. The welcome
interview asks for the expected bot username up front and **verifies it
mechanically**: after registering each GitHub token, a `GET /user` call
confirms the authenticated login actually matches the declared bot account —
not a check-the-box, an actual API call whose answer can only be wrong if
something is misconfigured. If it resolves to the owner's own account instead,
that's surfaced immediately, not discovered later from a confused community
member asking why the owner personally labeled their issue.

Discord doesn't need the equivalent check: a bot token structurally cannot
ever resolve to a personal user identity (that's what makes self-botting a
Terms violation rather than just a bad idea — see `discord-mechanics.md`'s
platform-rules section) — the account-confusion failure mode this section
guards against is GitHub-specific.

## 5 · Extend the network allowlist (only if you use the optional services)

**Recommended: keep a thin local overlay on top of the upstream kit, not a
copy-paste-per-install edit and not a pre-built forked image.** Clone the
kit once (`git clone https://github.com/docker/sbx-kits-contrib.git kit &&
cd kit && git sparse-checkout set nanoclaw`), apply the relevant blocks from
[`spec.yaml.allowlist-snippet`](../spec.yaml.allowlist-snippet) in this repo
to `kit/nanoclaw/spec.yaml` (uncomment only what your enabled tasks need),
and commit that `kit/` directory alongside this staging repo. Every `sbx
run`/recreate then uses `--kit ./kit/nanoclaw` — your allowlist edit is made
exactly once, survives every recreate, and is diffable/reviewable like any
other config, without ever becoming a second built image to version-pin.

Deliberately **not** a pre-built kit image with these hosts baked in: that
would widen every install's attack surface by default regardless of which
services it actually uses, and it's a second artifact competing with
`platform-baseline.json`'s digest for "what did we actually verify." A
plain local git checkout has neither problem — it's just files, reviewed
the same way as everything else here.

The kit's default allowlist does **not** include GA4, Gmail — or the
**social platform hosts the follower snapshot reads** (`x.com:443`,
`www.linkedin.com:443`, `www.facebook.com:443`, `www.instagram.com:443`,
`www.youtube.com:443` — whichever your platform list uses). Those tasks hit
`502 Bad Gateway` until you add them.

**One addition is NOT optional: your project's own web hosts.** The lead
reads the project's docs site to answer support questions, verify docs
currency, and check whether a repeat question already has a page — add the
docs site and project website hosts (e.g. `docs.yourproject.org:443`,
`yourproject.org:443`) or that whole class of work silently degrades to
"couldn't check."

**Also required for the follower snapshot: a page-reading tool.** An open
allowlist host alone isn't enough — something inside the agent needs to
actually fetch and read the page. Confirm the container has either Claude's
own built-in web fetch or NanoClaw's [`agent-browser`](https://nanoclaw.dev/skills/agent-browser)
skill installed **for the local group** — `social-metrics-snapshot` is the
local agent's task, so the marketing container is the wrong place to check —
before resuming it. This isn't curl-testable (that's why `setup-check.sh`
marks it `unknown`, not `ok`/`missing`) — verify it once with a real fetch of
one configured profile URL. Whether `agent-browser` is present in that
container at all is **unverified** on this stack; the real fetch is the test.

Clone the kit, edit `nanoclaw/spec.yaml` → `permissions.network.allow`
(e.g. add your project hosts, `analyticsdata.googleapis.com:443`,
`gmail.googleapis.com:443`, plus the social hosts), and start with
`--kit ./nanoclaw`. Verify with:

```bash
sbx policy ls nanoclaw --type network
```

This friction is the point: every egress hole is opened deliberately, per host,
in a file agents can't write. When any request 502s, suspect policy before the
target service.

### Optional: paid X auto-posting

Off by default. The welcome interview's social-platforms question offers it
explicitly — a plain yes/no with the real cost stated ("X has no free tier
since Feb 2026; pay-per-use, roughly $0.20 per link post"), never assumed.
Say no (or don't mention it) and nothing changes: the free intent-URL flow
stays the mechanism — the agent drafts, hands a pre-filled compose link to a
human, who clicks Post. That's the default because it needs zero credentials
and zero publishing risk on this agent.

If you opt in: create an X API credential, vault it in OneCLI scoped to
`api.x.com`, add that host to the allowlist (§5's snippet has the line), and
— this is the part that matters — put an **OneCLI request-hold** on that
host so every actual post still needs your button-press approval, at least
until the volume has earned trust. Never wire auto-posting as a silent
capability; the request-hold is what keeps "the agent can draft a tweet"
from quietly becoming "the agent can publish one."

## 6 · Configuration — one conversation, three files

**The default path is the conversation, not file edits.** After the owner DM
is wired (step 3), the lead's `welcome` skill interviews you — first question:
the project's GitHub repo — infers and confirms the rest, persists everything
as runtime config (`plugin-data/*/project-config.md` + the `config.env` script
keys), and relays each sub-agent's values so they write their own. That covers
the project identity, repo map, docs site, language, channel tiers, security
contact, social platforms, and optional analytics ids. **You edit zero files
for any of that.**

### The relay — you talk to the lead, the lead configures the others

You only ever answer questions once, in the owner DM. The lead then pushes
each sub-agent's parameters over the destination pair you wired in step 3,
and each sub-agent writes its own `plugin-data/<agent>/config.env`. That's
three separate relays now, not one, and they are very unequal in size:

| Sub-agent | Keys the lead relays into its `config.env` |
|---|---|
| **Local ops** | `COMMUNITY_REPOS`, `MIRROR_REPOS`, `CONTENT_REPO`, `GA4_PROPERTY_ID`, `GFI_LABEL`, `ACK_GRACE_MINUTES` |
| **Reviewer** (coding) | `COMMUNITY_REPOS` |
| **Marketing** | `CONTENT_REPO`, `RELEASE_WATCH_REPO` |

Plus `GITHUB_BOT_USERNAME`, which all four agents hold — it's what every
token's identity check is compared against.

**Check the local relay specifically, because it fails quietly.** It's by far
the largest payload, it feeds the 11 tasks that do the bulk of the recurring
work, and a missing key isn't an error — the gate script exits
`not-configured` and the task goes back to sleep. The symptom is "the local
agent was stamped and never does anything," which reads like a broken agent
and is actually an unrelayed key. `ACK_GRACE_MINUTES` is the one with a
built-in default (20 minutes before a holding acknowledgment goes out), so
`unanswered-watch` still works unrelayed; nothing else does. Confirm by
reading that file in the group folder, or ask the lead to echo back what the
local agent reported receiving.

**Only three things live outside the conversation:**

| What | Where | When |
|---|---|---|
| Task schedules (cron lines, every task file — run `bash scripts/gen-task-table.sh --counts` for the current total) — **the kit pins `TZ=UTC`**, so adjust the crons to your working day | Template files | **Before stamping** (frontmatter isn't runtime-editable; after stamping it's cancel-and-recreate per task). A per-group timezone override may exist in your NanoClaw version — unverified, don't rely on it |
| Workspace backup: `git init` + `remote` + identity + `.gitignore` | The **local** agent's group folder in the sandbox — it owns `workspace-backup` | After stamping, host-side (or ask the lead to relay the request) |
| Network allowlist additions (GA4/Gmail hosts) | Kit `spec.yaml`, local copy | Before `sbx run` — see step 5 |

**Pre-stamp file fill-ins remain available as version-controlled defaults** —
the persona "Your project" blocks, `channel-routing.md` (worked example in
`example-mapping.md`), and `escalation-paths.md`. Useful when stamping many
identical deployments, or when you want config reviewable in git before it
exists anywhere else. At runtime the conversational config in `plugin-data/`
always wins; the `additional_context` and skill files are read-only reference
once stamped.

### New project? Here's every question, before you're asked

Nothing below blocks you from starting — the interview infers what it can and
"not now" / "none" are complete answers to anything marked optional. This
table exists so nothing catches you off guard mid-conversation; skim it once,
then just talk to the agent.

### Prefer filling in a file over answering live? (the repeatable path)

Copy [`onboarding-answers.example.json`](../onboarding-answers.example.json),
fill in what you know, and the lead reads it instead of interviewing you —
asking only about what's still `null`. Keep the filled file and you can tear
the whole system down and rebuild it identically, which is what makes
onboarding testable rather than a one-shot conversation.

**1. Fill it in, on your own machine:**

```bash
cp onboarding-answers.example.json onboarding-answers.json
$EDITOR onboarding-answers.json
bash scripts/check-onboarding.sh onboarding-answers.json
```

That last command is worth running before you hand it over: it validates the
JSON, verifies every key the scripts read is present, and **refuses anything
credential-shaped**. Never put a secret in this file — no tokens, no webhook
URLs. It's config, and it's safe to keep in a private repo.

**2. Put it where the agent can actually read it.** This is the step people
miss: the lead runs in a container and can only see its own workspace. The
group folder on your host **is** that workspace:

| On your host | What the agent sees |
|---|---|
| `groups/<lead-folder>/onboarding-answers.json` | `/workspace/agent/onboarding-answers.json` |

```bash
# after stamping (step 3), from the nanoclaw install directory:
cp /path/to/onboarding-answers.json groups/<lead-folder>/
```

If you'd rather not touch the host filesystem, paste the JSON straight into
the owner DM instead — it's a config file, so there's nothing sensitive in it
by construction. The file is just more convenient for anything you'll rebuild.

**3. Point the lead at it.** DM: *"my answers are in
`/workspace/agent/onboarding-answers.json`"*. It reads the file, echoes back
a summary of what it got, asks about anything still missing, and persists —
same destination as the interview, so everything downstream is identical.
**Check that echo-back**: it's how you confirm the file was actually read
rather than silently missed.

**Rebuilding later**: the answers file plus your `plugin-data/` backup is the
complete recovery set. Stamp fresh, drop both in, and you're where you were —
no interview, no reconstruction from memory.

**Already installed conversationally and wish you had the file?** You don't
have to redo the interview to get one:

```bash
bash scripts/export-answers.sh <nanoclaw-root> [out.json]   # e.g. ~/nanoclaw
```

It walks the live install, reads every `config.env` key the templates
consume across all four agents, and writes them back into the same shape as
`onboarding-answers.example.json` — so a conversational install becomes an
editable, diffable record after the fact. That closes the loop: change one
value in the file and rebuild, instead of talking the agent through a
correction. Two limits worth knowing before you trust the output: each
agent's `project-config.md` is copied in verbatim as `_project_config_raw`
rather than parsed (it's prose an agent wrote), and anything that never lands
in a `config.env` — free-text tone/audience guidance, and every credential —
comes back `null` with its `_ask` prompt intact. Credentials live only in the
vault and the export **fails** rather than writing a file containing one.

### Answer these two before you stamp anything

Everything else in this section is safe to answer live, mid-conversation.
These two are not — they decide how tasks are created, so they have to be
settled before the stamp step:

| Asked | Format | Why it can't wait |
|---|---|---|
| **Timezone — what hours should scheduled work land in?** | your timezone, or "UTC is fine" | Schedules are cron lines in task frontmatter and the kit pins `TZ=UTC`. Not runtime-editable: changing a time after stamping means cancel-and-recreate, per task. One edit to your local task files now vs. 19 recreates later — see step 2 |
| **Which agents do you want at all?** — lead only, or lead + local ops and/or coding and/or marketing | pick | Determines what you stamp. If you add exactly one, add **local ops** — it's the tier that keeps working when the shared window closes, and it carries 12 of the 21 tasks. Not a one-way door (you can add or pause an agent later, see step 3) but it's the first command you run |

### Then the interview asks these

| # | Asked | Format | Optional? |
|---|---|---|---|
| 1 | Your project's GitHub repo or org | `owner/repo` | **No** — everything else derives from this |
| 2 | Which of the four jobs are goals: support, growth (and if so, users/contributors priority), proactive detection, security | yes/no per job | **No** — scopes everything asked after |
| 3 | Repo map: product / docs / site / marketing | repo per function, any may share one or be absent — inferred from #1, you confirm | Inferred + confirmed |
| 4 | Docs site URL, primary language, topic scope | free text | Inferred where possible |
| 5 | Discord channels: which are support (auto-reply) vs developer/team-lead (mention-only) | channel names per tier | Required if using Discord |
| 6 | Security disclosure contact + who counts as a maintainer | free text | Required if security is a goal |
| 7 | Social platforms: which exist, which you post to, and per platform the mechanism (intent-URL/manual/paid) | list + choice per platform | Optional — "none" is fine |
| 8 | Discord invite URL to offer from GitHub replies | URL or "none" | Optional |
| 9 | GA4 property id | id or "not now" | Optional — tasks silent-skip unconfigured |
| 10 | Model per agent — state the job, the default, and real alternatives (e.g. Reviewer: Haiku default, Sonnet if you want stronger judgment on drafts) | accept a default or name a model | Defaults offered per agent, confirm or change |
| 11 | Set up deterministic GitHub Actions notifications for bug/security labels? | yes/no | Optional, asked plainly — see `examples/github-discord-notify.yml` |
| 12 | OneCLI dashboard address — host machine only, or a reachable remote address (e.g. Tailscale IP) for checking in from elsewhere | URL or "same machine" | Asked once, used for every future dashboard link |
| 13 | Docs style — current-state only, or is version-history language ("added in 2.1") fine? | either | Enforced on every docs draft — which is the **lead's** work now, since `docs-gap-review` moved there |
| 14 | Who your content is actually for, in your own words, and the tone that follows | free text | **No** — marketing writes for this; without it, drafts default to generic copy |
| 15 | Workspace backup — a private repo the config/ledgers get pushed to (the **local** agent does the pushing) | `owner/repo` or "skip" | Optional, but it's the only thing that survives a sandbox recreate |
| 16 | The dedicated bot account's GitHub username (never the owner's own) | username | **No** — every GitHub token is checked against it |
| 17 | A named human backstop: who takes abuse reports and urgent escalations when you're unreachable | name + contact | **Asked always** — going live without one is recorded as an open risk, not silently accepted |

After this, the agent walks you through exactly which credentials to add
(step 4 below) and verifies each with a real call, offers to set up the
workspace backup itself, and asks for one explicit "go" before activating
anything. This is the only onboarding path — there's no separate migration
runbook to fill in beforehand; every answer above is meant to be given live,
in the conversation. See `example-mapping.md` (in the lead template's
`additional_context/`) for what a filled-in channel-routing answer looks like
from a real deployment, if a worked example helps.

## 7 · Start it — the go-live sequence

**The conversational path**: the lead's `welcome` flow ends with a credential
verification pass (it test-calls each enabled service and reports
working/not), a backup setup it performs itself, and an activation plan — it
resumes the verified tasks on your explicit "go" in the DM. If you use that
path, this section is your reference for what it's doing. The manual
CLI-driven equivalent:

Everything ships **paused**. Verify, test, then resume in this order:

```bash
./bin/ncl tasks list --status paused          # expect all 21 (5 support, 12 local, 3 engineering, 1 marketing)
./bin/ncl tasks run <task-id>                 # dry-run each SCRIPTED gate you configured
./bin/ncl tasks get <task-id>                 #   …and inspect its result
```

Marketing's 1 task won't be in that list unless you actually stamped that
template — it isn't stamped by default (step 3), so **18 paused tasks is the
expected result for a default install**, not a missing task. For the
authoritative per-task list, with owners and schedules, run
`bash scripts/gen-task-table.sh` from your local copy of this repo rather
than trusting any table typed into a doc.

Resume order (safe → side-effect-adjacent):

1. **The outage safety net, first** — these need no credentials and no
   network, so nothing about them can be misconfigured yet:
   `unanswered-watch` (local) is the highest-frequency task in the system
   (every 10 minutes) and the one thing that keeps the project from going
   silent when the lead is rate-limited or down; it reads local message
   state only and posts a template-only holding acknowledgment after
   `ACK_GRACE_MINUTES`. Resume it early — deferring it means deferring
   exactly the coverage you installed the local agent for. Alongside it:
   `health-check` (local) and `weekly-identity-integrity-check` (lead) —
   both wake only on problems.
2. **Local backup** (`workspace-backup`) — the local agent's task; only after
   the git setup in step 6.
3. **Lead announcements** (`release-announcement-watch`) — safe as soon as
   `COMMUNITY_REPOS` is set; it only ever posts already-public release info.
   The lead's `docs-gap-review` is safe from day one too — it stays quiet
   until normal support work has filled its question ledger.
4. **Local gates**, once §6's relay has actually landed in the local
   `config.env`: `repo-mirror-sync`, `dev-metrics-report`,
   `good-first-issue-health`, `repo-hygiene-audit`, `draft-cleanup`,
   `weekly-analytics-report` (GA4). Each silently exits `not-configured` if
   its key is missing, so resume them and then check they actually did
   something.
5. **Coding**: `github-ops-triage`, `security-advisory-sweep`,
   `dependabot-pr-review`, `docs-currency-watch`, `contributor-health-review`
   — the reviewer's current task list (`posthog-weekly-review` is removed for
   now; see SKILLS-ADOPTION.md if it comes back).
6. **Ungated tasks last**, because nothing stops them from burning a wake on
   an unconfigured service — there are exactly two:
   `social-metrics-snapshot` (local), only after you've verified a real page
   fetch works (§5), and the lead's `inbox-check`, only after an email MCP is
   actually connected.
7. **Marketing** (only if stamped): `content-draft-cycle`, once the content
   fill-ins are done and reviewed. It's the marketing agent's only task.
8. **Never resume** the lead's `daily-github-triage` while the coding agent is
   stamped. It's the lead's own standalone-mode fallback — the same ground at
   a lower cadence, kept so a lead-only install still triages — and
   `github-ops-triage` supersedes it. Running both double-reports every issue.
   Stamp the reviewer later? Pause this one at the same time.

Smoke-test before walking away: post a question in a support-tier channel
(expect an unprompted reply), @mention the lead in a dev-tier channel (expect a
reply *only* because you tagged it), and DM the lead asking it to ping every
sub-agent you stamped and relay their answers — that exercises all three
destination pairs at once, and a silent sub-agent here is a missing
destination, not a broken agent. If you stamped local ops, also confirm the
holding-acknowledgment path once: it's the one behaviour that only shows up
when the lead *can't* answer, so it's the easiest thing to leave untested
until the day you need it.

Day-2 commands: `sbx policy ls nanoclaw` · `sbx exec -it -w
/home/agent/nanoclaw nanoclaw claude` (break-glass admin, see above) ·
`sbx rm nanoclaw` (teardown — the whole system, gone).

**Not so fast — "resumed" is not "ready."** Before you call it live, walk
the 17-point ready gate in [CHECKPOINTS.md](CHECKPOINTS.md) — it also gives
you the day-2, week-1, and month-1 verification checkpoints. Everything else
— token budget, the full task reference, keeping the session alive, and the
SHA-pinned update policy — is in [OPERATIONS.md](OPERATIONS.md).
