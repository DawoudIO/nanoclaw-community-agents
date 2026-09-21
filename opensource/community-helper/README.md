# Community Helper Agent Template

The **Helper**: the one headless sub-agent in this set, running on **Claude
Haiku**. Read-only everywhere except two narrow paths — it drafts security
patch PRs, and it publishes a metrics history branch. It triages issues and
PRs, assesses security advisories, tracks repo and contributor health, reads
the project's traffic and follower numbers, and hands all of it to the
manager rather than posting publicly.

It carries every recurring job in this set that isn't talking to people.
That concentration is deliberate:

- **One headless agent means one credential scope** to reason about.
- **It keeps tasks together with the state they read.** `project-health`'s
  weekly post reads the contributor ledger its own daily runs build — since
  no agent can read another agent's `plugin-data`, that history has to live
  in one container.

Pairs with **`opensource/community-manager`** (the manager). It works standalone,
but the single-public-voice design assumes a manager exists to relay
through.

## Why headless

Every identity that can post publicly is another thing readers must trust and
another seam an injected instruction can aim at ("post this as the main
account," "don't mention a sub-agent did it"). This agent has no public channel
wiring at all, so that class of attempt fails structurally rather than depending
on the agent remembering a rule. See the manager template's
`references/single-voice-relay.md`.

## Layout

```
community-helper/
├── plugin.json
├── mcp.json                                     # GitHub MCP, placeholder token
├── setup-check.sh                                # run via Bash: mechanical setup self-check
├── token-audit.sh                                # run via Bash: zero-token usage/cost breakdown
├── ai.nanoco.nanoclaw/
│   ├── context/
│   │   └── instructions.md                       # standing brief: draft, never post
│   └── tasks/                                    # all created paused
│       ├── github-ops-triage.md                  # weekly issue + PR triage digest
│       ├── security-advisory-sweep.md            # scripted gate: only wakes on new alerts
│       ├── dependabot-pr-review.md               # what does this bump cost us?
│       ├── docs-currency-watch.md                # merged PR -> version-tagged docs PR
│       ├── unanswered-watch.md                   # the one task here that posts publicly
│       ├── inbox-check.md                        # 2×/day shared-inbox triage, read-and-draft only
│       ├── project-health.md                     # daily: every number the project tracks,
│       │                                         #   weekly post, ledger commit + read-back
│       └── conversation-archive-prune.md         # pure housekeeping, never wakes the model
├── skills/
│   └── helper-ops/
│       ├── SKILL.md
│       └── references/
│           ├── reporting-to-manager.md              # the may/may-not boundary
│           ├── triage-rules.md
│           ├── security-handling.md
│           ├── inbox-triage.md                        # shared-inbox handling rules
│           ├── metrics-and-telemetry.md
│           └── github-contents-api.md                # base64 read-modify-write gotcha
└── README.md
```

**`docs-gap-review` and `github-first-response` are the manager's**, not this
agent's — `docs-gap-review` reads a ledger only the manager writes, and since no
agent can read another agent's plugin-data, it was permanently dead while it
lived here. That constraint is worth remembering before moving any task
between agents: a task and the state it reads have to share a container.
`github-first-response` is the fast path for new issues and PRs; this agent's
`github-ops-triage` is the weekly sweep behind it, not a second responder.

**Three checks that used to be tasks here are not tasks anywhere now.**
Approved-but-unmerged PRs, stale good-first-issues, and missing
community-health files (CONTRIBUTING, CoC, templates) are point-in-time
questions with no history to keep, so they live as an on-demand
`repo-health` skill in the project's own repo — run by whichever agent the
maintainer points at it, when asked.

**`unanswered-watch` is the exception to "headless".** It is the only task in
this template that posts into a public channel, and only ever the same fixed
holding line ("logged, a maintainer will pick it up"), under the shared bot
identity the manager already uses — so the community sees one continuous voice
even while the manager is rate-limited or down. It answers nothing, promises no
timeline, and reports every acknowledgment upward so the real reply still
happens. It needs a silent wiring to each support channel to see the messages
at all; `welcome/SKILL.md` §5c sets that up.

## Stamp it

```bash
ncl groups create --template opensource/community-helper --name "Community Helper"
# Pin the tier — stamping does NOT default to Haiku (see below)
ncl groups config update --id <this-agent-id> --model claude-haiku-4-5
ncl groups restart --id <this-agent-id>
```

**That pin is not optional bookkeeping.** `groups create` takes no
`--model`, and a group with none of its own falls back to the install-wide
`NANOCLAW_DEFAULT_MODEL` — which no installer sets. Unset, the platform
sends no model at all and the provider SDK uses its own default, a
Sonnet-class model (NanoClaw's `src/config.ts`: "Unset means the provider
SDK's own default, which is what every existing install gets"). Every cost
figure on this page assumes Haiku, so an unpinned Helper silently spends
several times what this template claims, and nothing surfaces the
mismatch. Verify with `ncl groups config get --id <this-agent-id>`, and
remember a tier change needs the restart to take effect.

Then wire it to the manager — an agent-to-agent destination, not a channel:

```bash
ncl destinations add --agent-group-id <this-agent-id> --local-name parent --target-type agent --target-id <manager-agent-id>
ncl destinations add --agent-group-id <manager-agent-id> --local-name helper --target-type agent --target-id <this-agent-id>
```

**That pair is its only route for anything substantive.** It gets exactly one
other wiring, and only because `unanswered-watch` cannot work without it: a
silent `--engage-mode mention` wiring to each support channel, plus a
destination per channel to post the holding line through. See
`welcome/SKILL.md` §5c for those commands — the manager sets them up during
onboarding. Give this group no other channel wiring; that's the design.

## Configure before resuming tasks

Tasks are created **paused**. Each scripted task reads its config from one
file — `plugin-data/community-helper/config.env` inside the group folder
(the agent sees it as `/workspace/agent/plugin-data/community-helper/config.env`).
Create it either by editing the group folder directly on the host
(`groups/<folder>/plugin-data/community-helper/config.env`) or by messaging the
stamped agent to write it:

```bash
# groups/<folder>/plugin-data/community-helper/config.env
COMMUNITY_REPOS="owner/repo1 owner/repo2"        # advisory sweep, issue/PR triage,
                                                 # project-health
SECURITY_WATCH_REPOS="owner/repo1"               # optional — narrows
                                                 # security-advisory-sweep to a
                                                 # subset of COMMUNITY_REPOS
                                                 # (falls back to it if unset)
DOCS_REPO="owner/docs"                           # optional — docs-currency-watch
                                                 # stays silent forever if unset
LEDGER_REPO="owner/marketing"                    # project-health: where the history
                                                 # branch is committed. Normally the
                                                 # marketing repo, never the product
                                                 # repo — see below
LEDGER_BRANCH="agent-metrics"                    # optional — default shown. An
                                                 # orphan branch; the repo's
                                                 # default branch is never touched
LEDGER_PATH="agent-metrics"                      # optional — default shown. Subdir
                                                 # on that branch holding the CSVs
GA4_PROPERTIES="123456789"                       # optional — project-health traffic
                                                 # on post day. One or more: "id"
                                                 # or "label:id,label:id"
HEALTH_POST_DOW="1"                              # optional — project-health post
                                                 # day, 0=Sun..6=Sat; default Monday
SOCIAL_DAILY="true"                              # optional — "false" skips the
                                                 # collect-day follower wake, so
                                                 # non-post days cost 0 tokens
NUDGE_MAX_CHECKS="4"                             # optional — cap on return-nudge
                                                 # lookups per repo per post day
ACK_GRACE_MINUTES="20"                           # unanswered-watch: how long a
                                                 # message may sit unanswered
                                                 # before the holding reply goes
```

`ACK_GRACE_MINUTES` is the one value worth thinking about rather than
defaulting: too long and the silence it exists to prevent happens anyway; too
short and it interrupts a manager that was about to answer. 20 minutes is the
shipped default.

> **`LEDGER_REPO` is the one worth not skipping.** Without it
> `project-health` reports `ledger.status: not-configured` on every run, and
> the history series live only inside this container. This system is meant to
> be rebuilt from the templates every few months and nothing reimports
> container state — so leaving it unset means the trend lines restart at zero
> on every rebuild, permanently. Repo metrics and GA4 traffic can be partly
> reconstructed; **follower counts cannot be re-read from anywhere, ever.**

**`posthog-weekly-review` is removed for now** — it never got working end to
end. If it comes back, it belongs here (product-telemetry anomalies need a
defect judgment, which is assessment, not narration — see
`skills/helper-ops/references/metrics-and-telemetry.md`), needing
`POSTHOG_PROJECT_ID` and `POSTHOG_HOST` config keys and a **PostHog key**
credential in the table below.

Every script exits cleanly with `wakeAgent: false, status: "not-configured"`
when its key is unset — an unconfigured task costs nothing rather than failing.
Configure what you want, leave the rest paused.

**Script dependencies:** the gates assume `bash`, `curl`, and `jq` in the
container image. Verify each with a manual run before resuming:

```bash
ncl tasks list --status paused
ncl tasks run <task-id>       # test a scripted task before resuming it
ncl tasks get <task-id>       # inspect the run result
ncl tasks resume <task-id>
```

**Cron lines are written UTC-relative; the group's actual timezone decides
the wall-clock fire time.** `ncl groups config update --timezone <IANA id>`
sets it and takes effect immediately (confirmed against
`src/modules/scheduling/recurrence.ts`) — no cancel-and-recreate needed.
Unset, the group defaults to the install-wide default, which is your host
machine's own detected timezone, not UTC.

## Credentials: via OneCLI, not env vars

No API keys live in this template. The OneCLI gateway holds credentials in its
vault and injects them into outbound HTTPS calls at the proxy boundary.

| Service | API host to match | Auth style | Permissions needed | Where to get it |
|---|---|---|---|---|
| GitHub | `api.github.com` | `Authorization: Bearer` | **Fine-grained. Read everywhere, plus Contents+PRs write for security patches** — this agent never posts, so its token literally can't: Contents (read), Issues (read), Pull requests (read), all triaged repos. Add the **Dependabot alerts (read)** repository permission only if the security sweep is enabled. Never `read:org`, never any write scope, never a classic `repo`-scope PAT (that's inherently read/write). | github.com → Settings → Developer settings → Personal access tokens (fine-grained) |

**On Dependabot** — the repo's setting decides this agent's role:

| Dependabot security updates | This agent's role |
|---|---|
| Enabled | *Reviews* Dependabot's fix PR — semver delta, whether our code reaches the affected API, and a merge-or-hold call |
| Disabled | *Drafts* the version bump itself |

Either is fine on its own; having both produces two PRs per CVE, which is
why onboarding asks. Nothing here can turn the setting on — that needs
Administration write, which no agent in this set holds.

This agent also holds the **GA4** credential now: OAuth on
`analyticsdata.googleapis.com`, scoped **Viewer** on the property.
`project-health` only ever calls `runReport` — a POST, but a read:
it's a query verb that takes a JSON body. Do not enable
`analyticsadmin.googleapis.com` — nothing here writes to GA4. (It would
also need a PostHog key if `posthog-weekly-review` comes back — removed for
now, see above.)

It needs the **`github.com` (git) host** wired in addition to
`api.github.com`, with push access to the ledger repo, because
`project-health` pushes the ledger branch on every run. Those are two
separate vault entry classes: wiring only the REST host leaves the publish
failing with `clone-failed` or `push-failed` while every other GitHub call
works.

**Social platforms need no credential at all** — the follower counts come off
public profile pages. What they do need is sandbox allowlist entries for those
hosts (`x.com`, `www.linkedin.com`, …) and a real page-reading capability in
this container (Claude's built-in web fetch, or the `agent-browser` skill).
There is no posting capability to put an approval gate in front of, because
there is no posting.

**Leave `GITHUB_PERSONAL_ACCESS_TOKEN: "placeholder"` in `mcp.json` as-is.** The
MCP server won't boot without the variable present; the real token is injected at
request time. Never replace it with a real value.

Least privilege is the point here: because the agent is designed never to write,
a near-read-only token both matches its job and removes the possibility of a
public-facing mistake even if an instruction slips through.

## Costs

Nearly every task here is script-gated — a broken fetch always still wakes
the agent, so a quiet day never masks a failure.

| Task | Wakes the agent when… |
|---|---|
| `github-ops-triage` | Weekly: a new or updated issue/PR since last sweep (or a fetch fails) |
| `security-advisory-sweep` | A new alert (or a fetch fails) |
| `dependabot-pr-review` | A bump not yet reviewed at its current head SHA |
| `docs-currency-watch` | A merged PR nobody has assessed yet |
| `project-health` | Daily for the follower row (off with `SOCIAL_DAILY=false`); always on post day; always when a repo's fetch failed |
| `inbox-check` | Unread mail nobody has handed over yet (or a fetch failure) — opt-in via `INBOX_ENABLED` |
| `unanswered-watch` | A message has gone unanswered past the grace window |
| `conversation-archive-prune` | Never, on success |

**`project-health` is one task with two modes, and the script picks the
mode** — the model never decides whether today is a post day.

- **`collect`** (every day): bash fetches every API-readable number — stars,
  forks, open issues and PRs, latest release, zero-comment backlog, new
  contributors — and appends a row per repo to `metrics-history.csv`. The
  model wakes for exactly one thing the API can't do: reading follower counts
  off public profile pages and appending one row to
  `social-metrics-history.csv`. It posts nothing. `SOCIAL_DAILY=false` turns
  that wake off, and a collect day then costs 0 tokens.
- **`post`** (weekly, `HEALTH_POST_DOW`, default Monday): collect, plus the
  post-day-only inputs — the unmerged-PR ratio and author concentration into
  `contributor-health-history.csv`, the 20–30-day return-nudge candidates,
  and GA4 traffic into `traffic-history-<label>.csv`. The model then composes
  two reports for the manager to route: dev numbers to the developer tier,
  social + traffic to the team-lead tier, with WoW/MoM computed from the
  daily rows rather than guessed from two points.

Every run, whichever mode, commits all history CSVs plus the frozen
`social-metrics-history.jsonl` archive to `LEDGER_BRANCH` on `LEDGER_REPO`,
then reads today's row back from GitHub. `ledger.status` says which happened:
`published-and-verified`, `published-unverified` (the push returned success
but the row read back doesn't match yet — once is raw-content lag, twice is
a finding), `not-configured`, `clone-failed`, `push-failed`, or `bad-config`.

So the one wake here a quiet day doesn't suppress is the daily follower read
— and that's a config choice, not a structural one. Everything else is
genuinely 0-token when there's nothing to judge.

**`unanswered-watch` runs most often — every ten minutes** — but it's also
the cheapest possible check: no network, no credentials, just a read of
local session state.

Holding this many gated tasks on Haiku is still a small footprint against
the shared usage window, which is the point of putting the Helper on the
cheap tier. `posthog-weekly-review` is removed for now — see above.
