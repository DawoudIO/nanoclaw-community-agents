# Community Agent Set for NanoClaw

Three templates that run an open-source project as a team with **one public
voice** — covering the four jobs that keep a project alive: people know about
it (awareness), reported issues get handled (response), problems get found
before users report them (proactive detection), and it stays secure. A support
lead talks to users on Discord and GitHub; two headless sub-agents (coding
ops, marketing ops) draft and hand off but never post.

The mechanism bias throughout: **scripts and skills over prompt-stuffed
agents**. 10 of 13 recurring tasks are script-gated — deterministic fetching,
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
into outbound requests.

**GitHub — three tokens from the bot account** (github.com → Settings →
Developer settings → Personal access tokens):

1. **Lead token** (classic): scopes `repo` (or `public_repo` for public-only
   projects) + `read:org`. This one comments on issues — it needs write. Never
   `admin:*`.
2. **Coding token** (classic): same but treat as **read-only** in spirit; add
   `security_events` (read) if you want the Dependabot advisory sweep. This
   agent never posts — don't give it more.
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
that walks bot creation and invite during setup (step 3).

---

## 1 · Start the sandbox

```bash
sbx run --name nanoclaw --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=nanoclaw" nanoclaw
```

(Alternatives: prebuilt `--kit docker.io/sbx/nanoclaw-kit:latest`, or a local
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

**Do your "edit BEFORE stamping" changes first — see step 6.** Personas are
mounted read-only into stamped agents; editing them after stamping means
restamping.

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
# Stamp — check each create response's templateReport for skipped parts
./bin/ncl groups create --template support/community-support     --name "Community Support"
./bin/ncl groups create --template engineering/community-coding  --name "Community Coding"
./bin/ncl groups create --template marketing/community-marketing --name "Community Marketing"

# Wire sub-agents to the lead — agent-to-agent both ways, NEVER to a channel
./bin/ncl destinations add --agent-group-id <coding-id>    --name parent    --target <lead-id>
./bin/ncl destinations add --agent-group-id <lead-id>      --name coding    --target <coding-id>
./bin/ncl destinations add --agent-group-id <marketing-id> --name parent    --target <lead-id>
./bin/ncl destinations add --agent-group-id <lead-id>      --name marketing --target <marketing-id>
```

Then connect Discord: in the sandbox's Claude Code session, run
`/add-discord` and follow it (bot creation, invite with Manage-Server rights
on your guild, channel wiring). **The first wiring is your own DM with the
lead — the control plane; nothing works without it.** Verify the round trip in
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

Open the OneCLI dashboard via the `10254` port mapping printed by `sbx run`.
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

## 5 · Extend the network allowlist (only if you use the optional services)

The kit's default allowlist does **not** include GA4, PostHog, or Gmail hosts —
those tasks will hit `502 Bad Gateway` until you add them. Clone the kit, edit
`nanoclaw/spec.yaml` → `permissions.network.allow` (e.g. add
`analyticsdata.googleapis.com:443`, `us.posthog.com:443`,
`gmail.googleapis.com:443`), and start with `--kit ./nanoclaw`. Verify with:

```bash
sbx policy ls nanoclaw --type network
```

This friction is the point: every egress hole is opened deliberately, per host,
in a file agents can't write. When any request 502s, suspect policy before the
target service.

## 6 · Files you edit — the complete list

**Or skip most of this and answer conversationally**: the lead's `welcome`
skill collects everything in the BEFORE-stamping table below (except cron
lines) over Discord at first contact and persists it as runtime config in
`plugin-data/` — file fill-ins act as defaults, the conversation wins. Edit
files when you prefer version-controlled config; talk when you prefer speed.

**BEFORE stamping** (personas mount read-only into agents — edit in the
template, in your staging repo/local copy, then load + stamp):

| File | Fill in |
|---|---|
| `support/…/context/instructions.md` | **Your project** block: name, repos, docs site, language, topic scope |
| `support/…/context/additional_context/channel-routing.md` | Your Discord channels per tier (support = auto-reply; developer & team-lead = mention-only). Worked example in `example-mapping.md` — delete it after |
| `support/…/skills/community-support/references/escalation-paths.md` | Private security-disclosure contact + who counts as a maintainer |
| `engineering/…/context/instructions.md` | **Your project** block: repos to triage, default branch, telemetry, label policy |
| `marketing/…/context/instructions.md` | **Your project** block: content repo, brand/strategy source, site repo, inbox, GA4 id |
| Task cron lines (all 13 task files) | Optional — **the kit pins `TZ=UTC`**, so shipped times fire in UTC unless you set each group's timezone; either adjust the crons or set the group tz |

**AFTER stamping** (writable at runtime — edit in the group folder inside the
sandbox, or ask the agent to write them):

| File | Fill in |
|---|---|
| `<coding group>/plugin-data/community-coding/config.env` | `COMMUNITY_REPOS="owner/repo1 owner/repo2"`, `POSTHOG_PROJECT_ID`, `POSTHOG_HOST` |
| `<marketing group>/plugin-data/community-marketing/config.env` | `GA4_PROPERTY_ID`, `CONTENT_REPO="owner/marketing"` |
| Lead group folder (optional backup) | `git init`, `git remote add origin …`, `git config user.name/email`, `.gitignore` |

## 7 · Start it — the go-live sequence

Everything ships **paused**. Verify, test, then resume in this order:

```bash
./bin/ncl tasks list --status paused          # expect all 13
./bin/ncl tasks run <task-id>                 # dry-run each SCRIPTED gate you configured
./bin/ncl tasks get <task-id>                 #   …and inspect its result
```

Resume order (safe → side-effect-adjacent):

1. **Lead safety net**: `health-check`, `weekly-identity-integrity-check` —
   need nothing, wake only on problems.
2. **Lead backup** (`workspace-backup`) — only after the git setup in step 6.
3. **Coding**: `github-ops-triage`, then the gates you configured
   (`security-advisory-sweep`, `dev-metrics-report`, `posthog-weekly-review`).
4. **Marketing gates**: `weekly-analytics-report`, `draft-cleanup`.
5. **Last, once fill-ins are done and reviewed**: `content-draft-cycle`, and
   `inbox-check` only after an email MCP is actually connected.
6. **Never resume** the lead's `daily-github-triage` if the coding agent is
   stamped — it's the standalone-mode fallback and would double-report.

Smoke-test before walking away: post a question in a support-tier channel
(expect an unprompted reply), @mention the lead in a dev-tier channel (expect a
reply *only* because you tagged it), and DM the lead asking it to ping both
sub-agents and relay their answers.

Day-2 commands: `sbx policy ls nanoclaw` · `sbx exec -it -w
/home/agent/nanoclaw nanoclaw claude` (customize) · `sbx rm nanoclaw`
(teardown — the whole system, gone).

---

## Reference: every task, required vs optional

"Silent skip" = safe to resume unconfigured (gate exits `not-configured` at
zero cost). "Leave paused" = agent-owned, no gate — resuming unconfigured burns
turns.

| Task | Agent | Wakes model | Needs | Unconfigured |
|---|---|---|---|---|
| `health-check` (every 3h) | lead | on a problem | nothing | safe |
| `workspace-backup` (daily) | lead | on failure | git repo + remote + `github.com` secret | silent skip |
| `daily-github-triage` (weekdays) | lead | only on new/updated items | lead PAT + `COMMUNITY_REPOS` in `plugin-data/community-support/config.env` | silent skip — leave paused permanently if coding agent stamped |
| `weekly-identity-integrity-check` | lead | only on prompt drift (hash gate) | nothing (`ncl`+`jq`; falls back to a manual-pass wake) | safe |
| `github-ops-triage` (4×/day) | coding | only on new/updated items | coding PAT + `COMMUNITY_REPOS` | silent skip |
| `security-advisory-sweep` (6×/day) | coding | on new alerts | PAT + `security_events` + `COMMUNITY_REPOS` | silent skip |
| `dev-metrics-report` (daily) | coding | daily | PAT + `COMMUNITY_REPOS` | silent skip |
| `posthog-weekly-review` (Mon) | coding | weekly | PostHog key + `POSTHOG_PROJECT_ID` + allowlist | silent skip |
| `inbox-check` (2×/day) | marketing | every run | email MCP + read-only mailbox + allowlist | leave paused |
| `content-draft-cycle` (weekdays) | marketing | every run | marketing PAT + brand source filled in | leave paused |
| `weekly-analytics-report` (Sun) | marketing | weekly | GA4 OAuth + `GA4_PROPERTY_ID` + allowlist | silent skip |
| `draft-cleanup` (daily) | marketing | on stale PRs | PAT + `CONTENT_REPO` | silent skip |
| `social-metrics-snapshot` (Sun) | marketing | every run | public profile pages only (no credentials) | leave paused — guards the one stateful asset (follower series) |

Shipped times (UTC under the kit): health-check every 3h · backup 08:40 · lead
triage weekdays 13:00 · coding triage every 6h · sweep every 4h · dev metrics
12:00 · PostHog Mon 15:00 · inbox 06:00 + 16:00 · content weekdays 13:30 ·
social snapshot Sun 13:00 · GA4 Sun 14:00 · cleanup 17:30 · integrity check
Mon 15:00. Rules of thumb: put the
integrity check before your own workday, dev metrics ahead of your dev
channel's hours, inbox checks at your real start/end of day. Ungated tasks cap
at 4 fires/day — the script gate is what lets health-check (8×) and the sweep
(6×) exceed it.

## Companion documents (staging repo only)

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
