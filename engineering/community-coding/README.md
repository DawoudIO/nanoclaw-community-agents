# Community Coding Agent Template

The **Reviewer** of the set: a headless GitHub-ops sub-agent, read-only
everywhere except one path — it drafts security patch PRs — and a
running on **Claude Haiku**. It triages issues and PRs, assesses security
advisories, and interprets contributor-health trends — handing all of it to a
lead support agent rather than posting publicly.

It is deliberately narrow. It does **not** compute dev metrics, review product
telemetry, or do docs-gap review; all of that moved to
`local/community-local`, which runs a local model and pays no subscription cost
to narrate numbers a script already computed. What's left here is the work that
actually needs judgment — about code, about severity, and about what a moving
number *means* — which is why it keeps a cloud model, and why that model is the
cheap one.

Pairs with **`support/community-support`** (the lead); its siblings are
**`local/community-local`** and **`marketing/community-marketing`**. It works
standalone, but the single-public-voice design assumes a lead agent exists to
relay through.

## Why headless

Every identity that can post publicly is another thing readers must trust and
another seam an injected instruction can aim at ("post this as the main
account," "don't mention a sub-agent did it"). This agent has no public channel
wiring at all, so that class of attempt fails structurally rather than depending
on the agent remembering a rule. See the lead template's
`references/single-voice-relay.md`.

## Layout

```
community-coding/
├── plugin.json
├── mcp.json                                     # GitHub MCP, placeholder token
├── ai.nanoco.nanoclaw/
│   ├── context/
│   │   └── instructions.md                       # standing brief: draft, never post
│   └── tasks/                                    # all created paused
│       ├── github-ops-triage.md                  # 4×/day, issue + PR triage digest
│       ├── security-advisory-sweep.md            # scripted gate: only wakes on new alerts
│       ├── dependabot-pr-review.md               # what does this bump cost us?
│       ├── docs-currency-watch.md                # merged PR -> version-tagged docs PR
│       └── contributor-health-review.md          # weekly, wakes on a real trend move
├── skills/
│   └── coding-ops/
│       ├── SKILL.md
│       └── references/
│           ├── reporting-to-lead.md              # the may/may-not boundary
│           ├── triage-rules.md
│           ├── security-handling.md
│           └── metrics-and-telemetry.md
└── README.md
```

**Where the other tasks went.** `dev-metrics-report`,
`good-first-issue-health`, `repo-hygiene-audit` and `repo-mirror-sync` are now
`local/community-local` tasks. `docs-gap-review` and
`daily-github-triage` are the lead's — `docs-gap-review` reads a ledger only
the lead writes, and since no agent can read another agent's plugin-data, it was
permanently dead while it lived here.

**And one metrics task came back.** `contributor-health-review` was split out of
the local agent's `dev-metrics-report` and landed here, which looks like a
reversal and isn't: the line was never "metrics live on the local tier," it was
"narration lives on the local tier." Reporting that stars went up is narration.
Deciding whether a rising close-without-merge rate means low-quality
submissions arriving or maintainers quietly burning out — opposite problems,
opposite responses, the same number — is judgment, and so is naming a
contributor as a delegation candidate. The fetching and the arithmetic stay
scripted; only the interpreting moved. The sibling half of that same split,
`ready-to-merge`, stayed local for the mirror-image reason: a list of approved
PRs is decided by the search, not by the reader.

## Stamp it

```bash
ncl groups create --template engineering/community-coding --name "Community Coding"
```

Then wire it **to the lead agent only** — an agent-to-agent destination, not a
channel:

```bash
ncl destinations add --agent-group-id <this-agent-id> --name parent --target <lead-agent-id>
ncl destinations add --agent-group-id <lead-agent-id> --name coding --target <this-agent-id>
```

Do not give this group a Discord/GitHub-channel wiring. That's the whole design.

## Configure before resuming tasks

Tasks are created **paused**. Each scripted task reads its config from one
file — `plugin-data/community-coding/config.env` inside the group folder
(the agent sees it as `/workspace/agent/plugin-data/community-coding/config.env`).
Create it either by editing the group folder directly on the host
(`groups/<folder>/plugin-data/community-coding/config.env`) or by messaging the
stamped agent to write it:

```bash
# groups/<folder>/plugin-data/community-coding/config.env
COMMUNITY_REPOS="owner/repo1 owner/repo2"        # advisory sweep, issue/PR triage,
                                                 # contributor-health review
SECURITY_WATCH_REPOS="owner/repo1"               # optional — narrows
                                                 # security-advisory-sweep to a
                                                 # subset of COMMUNITY_REPOS
                                                 # (falls back to it if unset)
```

**`posthog-weekly-review` is removed for now** — it never got working end to
end. If it comes back, it belongs here (product-telemetry anomalies need a
defect judgment, which is assessment, not narration — see
`skills/coding-ops/references/metrics-and-telemetry.md`), needing
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

**Schedules run in UTC** (the kit pins `TZ=UTC`) from each task's `schedule:`
cron. Tune them before stamping; afterwards, changing one means cancel and
recreate that task (`ncl tasks create --prompt … --recurrence …`) or edit the
template file and restamp. A per-group timezone override may exist in your
NanoClaw version — unverified, see UPSTREAM-ISSUES.md.

## Reads the shared repo mirror when it's set up

`dependabot-pr-review` and `security-advisory-sweep` will grep
`/workspace/shared-repos/<repo>/` directly for reachability and
breaking-change judgment (checking `.last-sync-epoch`'s age first) if the
local agent's shared mirror mount is set up — see
`local/community-local/README.md`, "Shared repo mirror," for the one-time
owner setup. Without it, both tasks fall back to the GitHub API or ask the
lead to relay a grep from local ops. Optional either way; nothing here
requires it.

## Credentials: via OneCLI, not env vars

No API keys live in this template. The OneCLI gateway holds credentials in its
vault and injects them into outbound HTTPS calls at the proxy boundary.

| Service | API host to match | Auth style | Permissions needed | Where to get it |
|---|---|---|---|---|
| GitHub | `api.github.com` | `Authorization: Bearer` | **Fine-grained. Read everywhere, plus Contents+PRs write for security patches** — this agent never posts, so its token literally can't: Contents (read), Issues (read), Pull requests (read), all triaged repos. Add the **Dependabot alerts (read)** repository permission only if the security sweep is enabled. Never `read:org`, never any write scope, never a classic `repo`-scope PAT (that's inherently read/write). | github.com → Settings → Developer settings → Personal access tokens (fine-grained) |

**On Dependabot.** If the repo has Dependabot security updates enabled,
Dependabot opens the fix PR and this agent *reviews* it — semver delta, whether
our code reaches the affected API, and a merge-or-hold call. If it is disabled,
this agent drafts the bump instead. Either is fine; having both produces two PRs
per CVE, which is why onboarding asks. Nothing here can turn the setting on —
that needs Administration write, which no agent in this set holds.

This agent needs **no GA4 access** — GA4 traffic narration is the local
agent's; that credential belongs to `local/community-local`, see that
template's README. (It would also need a PostHog key if
`posthog-weekly-review` comes back — removed for now, see above.)

**Leave `GITHUB_PERSONAL_ACCESS_TOKEN: "placeholder"` in `mcp.json` as-is.** The
MCP server won't boot without the variable present; the real token is injected at
request time. Never replace it with a real value.

Least privilege is the point here: because the agent is designed never to write,
a near-read-only token both matches its job and removes the possibility of a
public-facing mistake even if an instruction slips through.

## Costs

Every task here is script-gated, and none has an ungated wake.
`github-ops-triage` wakes only on new or updated issues and PRs;
`security-advisory-sweep` only on a new alert. Any of them also wakes when its
fetch fails outright — a broken fetch must never read as a quiet day. A
genuinely quiet stretch costs a few API calls per run, not an agent turn.

`contributor-health-review` is the cheapest task here despite being the most
expensive prompt, because its gate is a comparison rather than a poll. It runs
weekly and wakes only when one of four things is true: the unmerged ratio or the
top-author share moved **10 points or more** against last week's stored values;
it is the **first run** and there is no baseline to diff against; a fetch
failed; or **90 days** have passed with none of the above, which forces one
quarterly look so bus-factor risk can't sit unexamined forever. The 10-point
floor is deliberate — on repos this size a 1–2 point swing is sampling noise,
and waking a model to narrate noise is how a useful signal becomes something
the owner learns to skip. A steady quarter costs one wake.

A short list of gated tasks on Haiku is a small footprint against the shared
usage window, which is the point of putting the Reviewer on the cheap tier.
Dev metrics, GFI health, hygiene audit, and mirror sync moved to the local
agent (also on the cheap tier, but bearing narration rather than judgment).
`posthog-weekly-review` is removed for now — see above.
