# Community Agent Set for NanoClaw

Three templates that run an open-source project as a team with **one public
voice** — covering the four jobs that keep a project alive: people know about
it (awareness), reported issues get handled (response), problems get found
before users report them (proactive detection), and it stays secure. A support
lead talks to users on Discord and GitHub; two headless sub-agents (coding
ops, marketing ops) draft and hand off but never post.

The mechanism bias throughout: **scripts and skills over prompt-stuffed
agents**. 11 of 14 recurring tasks are script-gated — deterministic fetching,
diffing, and thresholds run as bash with no model involved, and the agent
wakes only to read the result and exercise judgment. Anything with zero
judgment (label→channel notifications, secret scanning) belongs even further
out, in GitHub Actions — the docs below say where. And almost nothing here is
stateful: agents rebuild context from the project's repos on cold start,
memory is a disposable cache of the web, and the single durable asset is the
social follower-count time series (`social-metrics-snapshot` guards it).

| Template | Role | Public voice |
|---|---|---|
| [`support/community-support`](support/community-support/) | Lead — replies, triage, escalation, relays the sub-agents | **Yes — the only one** |
| [`engineering/community-coding`](engineering/community-coding/) | Issue/PR triage, security sweeps, dev metrics, telemetry | No |
| [`marketing/community-marketing`](marketing/community-marketing/) | Content drafts via PR, inbox triage, traffic analytics | No |

The lead works standalone; add sub-agents when you want that work done without
granting a second identity. Each template's README has per-agent detail. **This
file is the runbook: prerequisites → keys → edits → start.** The deployment
path documented here is a Docker Sandbox (`sbx`) micro-VM — run it that way
unless you have a strong reason not to; the isolation is the security model.

New here? Setup is a conversation, not a form — you'll DM the stamped agent
and it interviews you. If you'd rather see the whole question set before you
start, jump to [§6's prep sheet](#new-project-heres-every-question-before-youre-asked).

---

## 0 · Prerequisites — what you need before starting

### Apps / accounts

| You need | Why | Required? |
|---|---|---|
| **Docker Desktop with `sbx`** (Docker Sandboxes) | The micro-VM everything runs in | Required |
| **A Discord server you admin** (Manage Server permission) | To create/invite the bot and wire channels | Required |
| **A GitHub account for the bot** — make a dedicated service account (e.g. `yourproject-bot`), not your personal one | All GitHub work appears as this identity; you'll cut 3 scoped tokens from it | Required |
| **PostHog account** | `posthog-weekly-review` task | Optional |
| **Google Cloud project + GA4 property access** | `weekly-analytics-report` task | Optional |
| **A shared project inbox** (e.g. Gmail) | `inbox-check` task | Optional |

Skipping an optional service costs nothing: its task ships paused and its
script gate exits `not-configured` even if resumed.

### Tokens / keys — how to get each one

Collect these before setup; you'll register them in OneCLI in step 4. **Never
paste any of them into the sandbox, a template file, or a chat with an agent** —
they go into the OneCLI vault through its dashboard, and the proxy injects them
into outbound requests. **[PREREQS.md](PREREQS.md)** has the exact URL for
each one, the CLI alternative to the dashboard, and — just as important — how
to audit and rotate them later without guessing whether a change "took".

**GitHub — three tokens from the bot account** (github.com → Settings →
Developer settings → Personal access tokens):

1. **Lead token** (classic): scope `repo` (or `public_repo` for public-only
   projects) — this one comments on issues, so it needs write on issues/PRs.
   **Not `read:org`**: nothing here reads org membership or teams (listing an
   org's repos, which the welcome interview does, needs no such scope) —
   dropped as an unjustified grant. Never `admin:*`, never `delete_repo`.
2. **Coding token** (fine-grained): all triaged repos, **read-only**
   (Contents/Issues/PRs read; add Dependabot alerts read for the advisory
   sweep). A classic `repo`-scope PAT is inherently read/write — don't use one
   here; this agent never posts, so give it a token that *can't*.
3. **Marketing token** (fine-grained): Fine-grained tokens → limit to the
   **content repo only** → Contents + Pull requests read/write. It opens draft
   PRs and nothing else.
4. If you enable workspace backup, the lead's push goes to `github.com` (git),
   a **separate vault host match** from `api.github.com` (REST) — one more
   vault entry, same or a fourth token.

**PostHog** (optional): PostHog → Settings → Personal API Keys → create with
**read** access to insights/query. Note whether your org is on
`us.posthog.com` or `eu.posthog.com`. Note your numeric project id.

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

---

## 1 · Start the sandbox

```bash
sbx run --name nanoclaw --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=nanoclaw" nanoclaw
```

(The trailing `nanoclaw` is the kit's app argument — keep it as-is.
Alternatives: prebuilt `--kit docker.io/sbx/nanoclaw-kit:latest`, or a local
clone `--kit ./nanoclaw` — the local route is also how you edit the network
allowlist, see step 5.)

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
NanoClaw setup — the kit defaults to Claude as provider. **Note the port
mappings `sbx run` prints**: OneCLI dashboard (`10254`) is where you'll
register credentials; gateway is `10255`; webhook is `3000`. Keep this session
open; NanoClaw stops when it closes.

## 2 · Load the templates into the sandbox

The install's templates directory is `/home/agent/nanoclaw/templates/` inside
the VM.

**Only cron-line/timezone changes must happen before stamping** (see step 6) —
project config is collected conversationally after wiring. Pre-stamp file
fill-ins are optional defaults; personas mount read-only once stamped.

**A — from a git staging repo** (github.com is already allowlisted):

```bash
sbx exec nanoclaw bash -lc '
  git clone --depth 1 https://github.com/<you>/<staging-repo>.git /tmp/tpl &&
  mkdir -p /home/agent/nanoclaw/templates &&
  cp -R /tmp/tpl/support /tmp/tpl/engineering /tmp/tpl/marketing /home/agent/nanoclaw/templates/'
```

**B — stream your local copy over exec stdin** (no repo needed):

```bash
tar -C /path/to/nanoclaw-templates -cf - support engineering marketing \
  | sbx exec -i nanoclaw tar -C /home/agent/nanoclaw/templates -xf -
```

## 3 · Stamp the agents and wire them

Run inside the sandbox (`sbx exec -it -w /home/agent/nanoclaw nanoclaw bash`,
or drive it conversationally via `sbx exec -it -w /home/agent/nanoclaw
nanoclaw claude`):

```bash
# Stamp — check each create response's templateReport for skipped parts,
# and note each group's id from the response: the destination wiring below
# and the OneCLI selective-mode step need them.
./bin/ncl groups create --template support/community-support     --name "Community Support"
./bin/ncl groups create --template engineering/community-coding  --name "Community Coding"
./bin/ncl groups create --template marketing/community-marketing --name "Community Marketing"

# Wire sub-agents to the lead — agent-to-agent both ways, NEVER to a channel
./bin/ncl destinations add --agent-group-id <coding-id>    --name parent    --target <lead-id>
./bin/ncl destinations add --agent-group-id <lead-id>      --name coding    --target <coding-id>
./bin/ncl destinations add --agent-group-id <marketing-id> --name parent    --target <lead-id>
./bin/ncl destinations add --agent-group-id <lead-id>      --name marketing --target <marketing-id>
```

(Credential registration is step 4 — the welcome interview below runs before
it by design, so its verification pass will first report services as unwired;
it walks you through the vault entries and re-verifies. That's expected, not
broken.)

Then connect Discord: in the sandbox's Claude Code session, run
`/add-discord` and follow it (bot creation, invite with Manage-Server rights
on your guild, channel wiring). **The first wiring is your own DM with the
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
wire the public channels + guild catch-all, **lead only** — sub-agents get no
channel wiring; that's the single-voice design, enforced by absence. After
setup, everything runs through Discord; the sandbox Claude CLI is break-glass
admin only (MIGRATION.md → Break-glass admin covers when it helps and how it
hurts).

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

The model provider key itself (what NanoClaw uses to run Claude) lives in the
same dashboard's **LLMs** tab, separate from the **Apps**/**Custom** tabs
above — one more reason a working remote address is worth setting up once.

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
| GitHub coding token | `api.github.com` | `Authorization: Bearer` |
| GitHub marketing token | `api.github.com` | `Authorization: Bearer` |
| GitHub backup push (optional) | `github.com` | `Authorization: Bearer` |
| PostHog key (optional) | `us.posthog.com` or `eu.posthog.com` | `Authorization: Bearer` |
| GA4 OAuth (optional) | `analyticsdata.googleapis.com` | OAuth 2.0 Bearer |
| Gmail (optional) | `gmail.googleapis.com` | OAuth 2.0 Bearer |

**Then set the three agents to `selective` secret mode and assign each its own
GitHub secret** — all three tokens match the same host, and in the default
`all` mode every agent would get whichever matches first, collapsing your
scoped tokens back into shared access:

```bash
onecli agents list
onecli agents set-secret-mode --id <agent-id> --mode selective   # ×3
# assign each agent its own secret in the dashboard
```

Optionally add **request-hold approval rules** in the dashboard for anything
you can never allow unattended (publishing, sending mail, closing/merging) —
gating the outbound request at the proxy is enforcement no prompt can bypass.

### Least privilege — exactly what each bot does, and nothing more

One canonical list, so "does it need that?" always has a checkable answer
instead of a guess. Anything not listed under **Needs** is deliberately
**never granted**, not an oversight.

**Discord bot** (one, the lead's — sub-agents get no Discord identity at all):

| | |
|---|---|
| Needs | Send Messages, Embed Links, Attach Files, Read Message History, and the **Message Content privileged intent** (justified: auto-reply in support channels means reading messages the bot wasn't @mentioned in — this is the one privileged grant this system needs, and it's why 100+ guild deployments trigger Discord's own bot verification, see `discord-mechanics.md`) |
| Never | Administrator, Manage Server, Manage Roles, Manage Channels, Manage Messages (deleting others' messages), Kick/Ban/Timeout Members, View Audit Log — none of this is moderation, and it never will be from this bot |

**GitHub tokens** (three, least-privilege split — never one shared token):

| Token | Needs | Never |
|---|---|---|
| Lead | `repo` (or `public_repo`) — comments, labels, opens issues | `read:org`, `admin:*`, `delete_repo`, org/team scopes |
| Coding | Fine-grained, **read-only**: Contents + Issues + PRs read; + Dependabot alerts read if the security sweep is enabled | Any write scope at all — this agent never posts, so its token literally cannot |
| Marketing | Fine-grained, **content repo only**: Contents + PRs read/write | Write on any repo but the content one; org-wide scopes |
| Backup (optional) | Push to one backup repo (`github.com` host match) | Nothing beyond that repo |

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
| Lead | `selective` | Lead GitHub PAT | `api.github.com` | `daily-github-triage`, `release-announcement-watch`, issue/PR replies |
| Lead | `selective` | Backup push secret *(optional)* | `github.com` (git) | `workspace-backup` |
| Coding | `selective` | Coding GitHub PAT | `api.github.com` | `github-ops-triage`, `security-advisory-sweep`, `dev-metrics-report` |
| Coding | `selective` | PostHog key *(optional)* | `us.`/`eu.posthog.com` | `posthog-weekly-review` |
| Marketing | `selective` | Marketing GitHub PAT | `api.github.com` | `content-draft-cycle`, `draft-cleanup` |
| Marketing | `selective` | GA4 OAuth *(optional)* | `analyticsdata.googleapis.com` | `weekly-analytics-report` |
| Marketing | `selective` | Gmail OAuth *(optional)* | `gmail.googleapis.com` | `inbox-check` |
| Marketing | — (no vault secret) | Sandbox allowlist entries only, public pages | `x.com`, `www.linkedin.com`, etc. | `social-metrics-snapshot` — reads public profiles, no credential exists to grant |

**Coding never appears against Discord, PostHog access on Marketing, or any
agent against a host it has no row for above.** `selective` mode (not the
default `all`) is what makes this enforceable at all — in `all` mode every
agent gets every secret whose host matches, which collapses this entire table
back into shared access.

### Confirm identity, don't assume it (and audit what's already connected)

**[PREREQS.md](PREREQS.md)** has the full audit and rotation runbook using
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

The kit's default allowlist does **not** include GA4, PostHog, Gmail — or the
**social platform hosts the follower snapshot reads** (`x.com:443`,
`www.linkedin.com:443`, `www.facebook.com:443`, `www.instagram.com:443`,
`www.youtube.com:443` — whichever your platform list uses). Those tasks hit
`502 Bad Gateway` until you add them. Clone the kit, edit
`nanoclaw/spec.yaml` → `permissions.network.allow` (e.g. add
`analyticsdata.googleapis.com:443`, `us.posthog.com:443`,
`gmail.googleapis.com:443`, plus the social hosts), and start with
`--kit ./nanoclaw`. Verify with:

```bash
sbx policy ls nanoclaw --type network
```

This friction is the point: every egress hole is opened deliberately, per host,
in a file agents can't write. When any request 502s, suspect policy before the
target service.

## 6 · Configuration — one conversation, three files

**The default path is the conversation, not file edits.** After the owner DM
is wired (step 3), the lead's `welcome` skill interviews you — first question:
the project's GitHub repo — infers and confirms the rest, persists everything
as runtime config (`plugin-data/*/project-config.md` + the `config.env` script
keys), and relays each sub-agent's values so they write their own. That covers
the project identity, repo map, docs site, language, channel tiers, security
contact, social platforms, and optional analytics ids. **You edit zero files
for any of that.**

**Only three things live outside the conversation:**

| What | Where | When |
|---|---|---|
| Task schedules (cron lines, all 14 task files) — **the kit pins `TZ=UTC`**, so either adjust the crons or set each group's timezone | Template files | Before stamping (frontmatter isn't runtime-editable; after stamping it's cancel-and-recreate) |
| Workspace backup: `git init` + `remote` + identity + `.gitignore` | Lead's group folder in the sandbox | After stamping, host-side (or ask the lead to run it) |
| Network allowlist additions (GA4/PostHog/Gmail hosts) | Kit `spec.yaml`, local copy | Before `sbx run` — see step 5 |

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
| 9 | GA4 property id / PostHog project id + host | id/host or "not now" | Optional — tasks silent-skip unconfigured |
| 10 | Model per agent — confirm the plan-tier defaults or override | accept or name a model | Defaults offered, confirm or change |
| 11 | Set up deterministic GitHub Actions notifications for bug/security labels? | yes/no | Optional, asked plainly — see `examples/github-discord-notify.yml` |
| 12 | OneCLI dashboard address — host machine only, or a reachable remote address (e.g. Tailscale IP) for checking in from elsewhere | URL or "same machine" | Asked once, used for every future dashboard link |
| 13 | The dedicated bot account's GitHub username (never the owner's own) | username | **No** — every GitHub token is checked against it |

After this, the agent walks you through exactly which credentials to add
(step 4 below) and verifies each with a real call, offers to set up the
workspace backup itself, and asks for one explicit "go" before activating
anything. See `MIGRATION.md`'s appendix for what a filled-in answer set looks
like from a real deployment (ChurchCRM) if a worked example helps.

## 7 · Start it — the go-live sequence

**The conversational path**: the lead's `welcome` flow ends with a credential
verification pass (it test-calls each enabled service and reports
working/not), a backup setup it performs itself, and an activation plan — it
resumes the verified tasks on your explicit "go" in the DM. If you use that
path, this section is your reference for what it's doing. The manual
CLI-driven equivalent:

Everything ships **paused**. Verify, test, then resume in this order:

```bash
./bin/ncl tasks list --status paused          # expect all 14
./bin/ncl tasks run <task-id>                 # dry-run each SCRIPTED gate you configured
./bin/ncl tasks get <task-id>                 #   …and inspect its result
```

Resume order (safe → side-effect-adjacent):

1. **Lead safety net**: `health-check`, `weekly-identity-integrity-check` —
   need nothing, wake only on problems.
2. **Lead backup** (`workspace-backup`) — only after the git setup in step 6.
3. **Lead announcements** (`release-announcement-watch`) — safe as soon as
   `COMMUNITY_REPOS` is set; it only ever posts already-public release info.
4. **Coding**: `github-ops-triage`, then the gates you configured
   (`security-advisory-sweep`, `dev-metrics-report`, `posthog-weekly-review`).
5. **Marketing gates**: `weekly-analytics-report`, `draft-cleanup`.
6. **Last, once fill-ins are done and reviewed**: `content-draft-cycle`, and
   `inbox-check` only after an email MCP is actually connected.
7. **Never resume** the lead's `daily-github-triage` if the coding agent is
   stamped — it's the standalone-mode fallback and would double-report.

Smoke-test before walking away: post a question in a support-tier channel
(expect an unprompted reply), @mention the lead in a dev-tier channel (expect a
reply *only* because you tagged it), and DM the lead asking it to ping both
sub-agents and relay their answers.

Day-2 commands: `sbx policy ls nanoclaw` · `sbx exec -it -w
/home/agent/nanoclaw nanoclaw claude` (customize) · `sbx rm nanoclaw`
(teardown — the whole system, gone).

---

## Models and token budget — right-sizing on a small plan

**Three agents is the right number — and it's cheaper than it looks.** Burn
comes from model *wakes*, not from agents existing: a stamped agent whose
tasks are paused costs nothing. 11 of 14 tasks are script-gated, so quiet
periods cost near zero regardless of agent count. That makes the team elastic:
stamp all three, then tune budget by which tasks you activate — never by
deleting agents.

Two sizing mistakes this design specifically avoids (both were learned the
expensive way on a real deployment that hit its plan limits with 4 agents):

- **Don't add a "quick tasks" agent.** The lead stays responsive by design —
  scheduled work runs in isolated task sessions and long background work
  belongs to the sub-agents, so the owner DM is never stuck behind a slow
  thread. A fourth agent for responsiveness just duplicates context loads.
- **Don't merge everything into one agent to save tokens.** The savings are
  small (gated tasks already cost ~nothing when idle) and you lose the
  per-agent credential scoping and the single-voice structure.

**Model defaults per agent** (confirmed at cold start by the welcome flow —
the owner can change them there or later via group config):

| Agent | Default | Why |
|---|---|---|
| Lead | Sonnet-class | Public-facing judgment: tone, escalation calls, security routing |
| Marketing | Sonnet-class | Content quality is its whole job; drafts are the deliverable |
| Coding | Haiku-class | Triage/digest work with skills to guide it — and everything it produces is reviewed by the lead before publishing. Upgrade only if draft quality disappoints |
| Any scheduled task | never Opus-class | Wakes are frequent; premium models belong in interactive sessions, not cron |

**If you still hit plan limits**, pause in this order (lowest value first):
`draft-cleanup` → `dev-metrics-report` → `social-metrics-snapshot` →
`inbox-check` → reduce `github-ops-triage` to 2×/day → `content-draft-cycle`
to 3×/week. The safety net (`health-check`, `workspace-backup`,
`weekly-identity-integrity-check`) and community replies are the last things
to give up — they're also nearly free, since all three are gated.

## Reference: every task, required vs optional

"Silent skip" = safe to resume unconfigured (gate exits `not-configured` at
zero cost). "Leave paused" = agent-owned, no gate — resuming unconfigured burns
turns.

| Task | Agent | Wakes model | Needs | Unconfigured |
|---|---|---|---|---|
| `health-check` (every 3h) | lead | on a problem | nothing | safe |
| `workspace-backup` (daily) | lead | on failure | git repo + remote + `github.com` secret | silent skip |
| `daily-github-triage` (weekdays) | lead | only on new/updated items | lead PAT + `COMMUNITY_REPOS` in `plugin-data/community-support/config.env` | silent skip — leave paused permanently if coding agent stamped |
| `release-announcement-watch` (every 3h) | lead | only on a new stable release | lead PAT + `COMMUNITY_REPOS` | silent skip |
| `weekly-identity-integrity-check` | lead | only on prompt drift (hash gate) | nothing (`ncl`+`jq`; falls back to a manual-pass wake) | safe |
| `github-ops-triage` (4×/day) | coding | only on new/updated items | coding PAT + `COMMUNITY_REPOS` | silent skip |
| `security-advisory-sweep` (6×/day) | coding | on new alerts | PAT + `security_events` + `COMMUNITY_REPOS` | silent skip |
| `dev-metrics-report` (daily) | coding | daily | PAT + `COMMUNITY_REPOS` | silent skip |
| `posthog-weekly-review` (Mon) | coding | weekly | PostHog key + `POSTHOG_PROJECT_ID` + allowlist | silent skip |
| `inbox-check` (2×/day) | marketing | every run | email MCP + read-only mailbox + allowlist | leave paused |
| `content-draft-cycle` (weekdays) | marketing | every run | marketing PAT + brand source filled in | leave paused |
| `weekly-analytics-report` (Sun) | marketing | weekly | GA4 OAuth + `GA4_PROPERTY_ID` + allowlist | silent skip |
| `draft-cleanup` (daily) | marketing | on stale PRs | PAT + `CONTENT_REPO` | silent skip |
| `social-metrics-snapshot` (Sun) | marketing | every run | public profile pages (no credentials) + **sandbox allowlist entries for the platform hosts** | leave paused until platforms are configured and allowlisted — it guards the one stateful asset (follower series; durable copy = the lead's ledger) |

Shipped times (UTC under the kit): health-check every 3h · backup 08:40 ·
release watch every 3h · lead triage weekdays 13:00 · coding triage every 6h ·
sweep every 4h · dev metrics 12:00 · PostHog Mon 15:00 · inbox 06:00 + 16:00 ·
content weekdays 13:30 · social snapshot Sun 13:00 · GA4 Sun 14:00 · cleanup
17:30 · integrity check Mon 15:00. Rules of thumb: put the
integrity check before your own workday, dev metrics ahead of your dev
channel's hours, inbox checks at your real start/end of day. Ungated tasks cap
at 4 fires/day — the script gate is what lets health-check (8×) and the sweep
(6×) exceed it.

## Staying up to date

The system is built to make its own upgrade path cheap: **cattle, not pets**.
Because almost nothing is stateful (context rebuilds from the web, config is a
conversation, the one durable file lives in the git backup), updating the
platform = recreating the sandbox — the same runbook you used to build it.

**Noticing updates is automated, not an agent job.** The
[`platform-watch`](.github/workflows/platform-watch.yml) Action in this repo
runs weekly: it compares the sbx VM image digest (`sbx-claude-alpha`), the
latest NanoClaw release, and the kit spec against `platform-baseline.json`,
and opens an issue here with a refresh checklist when any of them move.
Security advisories for NanoClaw deserve an immediate refresh; otherwise batch
refreshes when the issue appears.

**The refresh procedure** (~1 hour, mostly waiting on pulls):

1. Confirm the last workspace backup ran — the lead's workspace carries
   `project-config.md` and the durable follower-series ledger
   (`plugin-data/community-support/social-metrics-history.jsonl`, appended by
   the lead each time marketing hands over a snapshot), the only things worth
   restoring.
2. `sbx rm nanoclaw` → `docker pull nanoco/nanoclaw:sbx-claude-alpha` (belt
   and braces against tag caching) → `sbx run …` (the git kit ref is always
   fetched fresh).
3. Restamp the latest templates from this repo; re-run `/add-discord` with the
   **same** Discord bot (its token comes from the Discord developer portal —
   the VM's stored copy died with the VM); re-verify the owner-DM round trip.
4. Re-enter the 3 GitHub PATs in the fresh vault, selective mode (~5 min).
   No rotation needed — refresh isn't compromise.
5. Restore the follower-series ledger from the backup repo into the lead's
   `plugin-data/community-support/`; either restore `project-config.md` too or
   just answer the welcome interview again.
6. Smoke tests per §7, and re-test anything in UPSTREAM-ISSUES.md against the
   new build before closing the watch issue.

**Template updates** flow the other way: edit this repo, restamp. Personas and
skills are read-only inside stamped agents by design, so a restamp *is* the
deployment mechanism — and the watch issue is a natural moment to fold in any
accumulated template improvements. Whether NanoClaw supports an in-place
upgrade instead of recreate is undocumented — tracked as an upstream docs ask
in UPSTREAM-ISSUES.md.

## Companion documents (staging repo only)

- **[PREREQS.md](PREREQS.md)** — create every credential (exact URLs),
  audit what's actually connected (real `onecli` commands, not guesses),
  confirm identity, and rotate safely with no downtime. Read this before
  step 0 if you'd rather script the whole credential story than click
  through the dashboard.

- **[MIGRATION.md](MIGRATION.md)** — step-by-step for replacing an existing
  NanoClaw install with this set in a sandbox: evidence preservation, the
  keep-OneCLI/minimal-rotation credential stance, cutover order, and the
  ChurchCRM deployment's concrete fill-in values.
- **[UPSTREAM-ISSUES.md](UPSTREAM-ISSUES.md)** — platform issues observed on
  the previous install, each with repro-on-clean-install steps; confirm during
  testing, then file against `nanocoai/nanoclaw` so the template works for
  every user, not just this deployment.

> This root README, MIGRATION.md, and UPSTREAM-ISSUES.md are for the staging
> repo. A PR to `nanocoai/nanoclaw-templates` submits only the three template
> directories; the catalog has its own root README.
