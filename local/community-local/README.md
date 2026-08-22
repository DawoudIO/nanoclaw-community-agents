# Community Local Ops Agent Template

An always-available agent that runs on a **local model** instead of the cloud
one. It narrates numbers a script already computed, keeps repo mirrors fresh,
and — the reason it exists — keeps the community from hearing silence when the
cloud-backed lead agent runs out of its usage window.

It owns the largest share of the recurring work in this set, because most of
that work is mechanical by construction: a gate script fetched and computed the
data, and the agent's only job is to say what it means in a sentence or two.

## Why local

The lead agent (`support/community-support`) answers people. It runs on a
capable cloud model and shares one usage window with every other cloud-backed
group here. When that window closes, the lead stops replying — and an
unanswered question reads as an abandoned project. Response delay is the
strongest single predictor of whether a first-time contributor comes back.

This agent has no window to run out of. That single property is worth more than
the quality difference on the work it's given, because all of that work is
either narration of pre-computed data or a fixed-template acknowledgment.

**It is not a smaller version of the lead.** Read
`ai.nanoco.nanoclaw/context/instructions.md` — the "What you must NEVER do"
list is the load-bearing part of this template, not boilerplate. A local model
answering a support question or assessing a security issue is exactly the
failure this split exists to prevent.

## Layout

```
local/community-local/
├── plugin.json
├── mcp.json
├── setup-check.sh                      # mechanical "what isn't configured yet"
├── ai.nanoco.nanoclaw/
│   ├── context/
│   │   └── instructions.md             # persona + the never-do list
│   └── tasks/                          # 11 tasks, all created paused
│       ├── unanswered-watch.md         # the one the north star depends on
│       ├── repo-mirror-sync.md
│       ├── dev-metrics-report.md
│       ├── weekly-analytics-report.md
│       ├── posthog-weekly-review.md
│       ├── social-metrics-snapshot.md
│       ├── good-first-issue-health.md
│       ├── repo-hygiene-audit.md
│       ├── draft-cleanup.md
│       ├── health-check.md
│       └── workspace-backup.md
└── skills/
    └── local-ops/
        ├── SKILL.md
        └── references/
            ├── narration.md
            ├── acknowledging.md
            └── escalating.md
```

Gate scripts are **not** authored here. They live in `scripts/tasks/local/*.sh`
(canonical, testable without an agent) and are injected into the task files by
`bash scripts/sync-tasks.sh`. Edit the `.sh`, never the `.md`.

## Stamp it

```bash
ncl groups create --template local/community-local --name "Community Local Ops"
```

Then point it at a local model — **this step is what makes the template work at
all.** Stamped without it, the group runs on the cloud provider, shares the
usage window, and defeats its own purpose:

```bash
ollama pull llama3.2                    # 2 GB; sized for a 16 GB Mac mini
/add-ollama-provider                    # per-group provider override
```

`setup-check.sh` fails with `local_provider_active: missing` if
`ANTHROPIC_BASE_URL` is unset for the group, which is the mechanical way to
catch a stamp that skipped this.

### Wiring — the one sub-agent that needs a channel

Like the other sub-agents, it reports upward:

```bash
ncl destinations add --agent-group-id <this-agent-id> --name parent --target <lead-agent-id>
ncl destinations add --agent-group-id <lead-agent-id> --name local --target <this-agent-id>
```

Unlike them, it **also** needs to reach the community channel, because the
acknowledgment role has to post where the unanswered message is. Grant the
narrowest wiring your setup allows — one channel, the support channel, nothing
else.

> **Unverified:** whether two groups (the lead and this one) can both wire to
> the same Discord channel is untested on a real install — see
> `UPSTREAM-ISSUES.md`. Confirm it during the day-1 checkpoint before trusting
> the acknowledger, because if it can't post, its failure mode is silence,
> which is precisely the thing it was added to prevent.

## Configure before resuming tasks

Tasks are created **paused**. Config lives in one file —
`plugin-data/community-local/config.env` in the group folder (the agent sees it
as `/workspace/agent/plugin-data/community-local/config.env`):

```bash
# groups/<folder>/plugin-data/community-local/config.env
COMMUNITY_REPOS="owner/repo1 owner/repo2"   # dev metrics, hygiene, GFI health
MIRROR_REPOS="owner/repo1 owner/repo1.wiki" # repo-mirror-sync; the FULL repo
                                            # map, not just triaged repos.
                                            # Falls back to COMMUNITY_REPOS.
CONTENT_REPO="owner/marketing"              # optional — draft-cleanup
GA4_PROPERTY_ID="123456789"                 # optional — weekly-analytics-report
POSTHOG_PROJECT_ID="12345"                  # optional — posthog-weekly-review
POSTHOG_HOST="https://us.posthog.com"       # or https://eu.posthog.com
GFI_LABEL="good first issue"                # optional — only if your repo uses
                                            # a different beginner label
ACK_GRACE_MINUTES="20"                      # unanswered-watch: how long a
                                            # message may sit before the
                                            # holding reply goes out
```

Every gate exits cleanly with `wakeAgent: false, status: "not-configured"` when
its key is unset, so an unconfigured task costs nothing rather than failing.
Configure what you want and leave the rest paused.

`ACK_GRACE_MINUTES` is the one value worth thinking about rather than
defaulting: too long and the silence it exists to prevent happens anyway; too
short and it interrupts a lead that was about to answer. 20 minutes is the
shipped default.

Verify and resume:

```bash
ncl tasks list --status paused
ncl tasks run <task-id>        # test before resuming
ncl tasks get <task-id>        # inspect the result
ncl tasks resume <task-id>
```

**Schedules run in UTC** (the kit pins `TZ=UTC`). `unanswered-watch` owns the
round ten-minute marks (`*/10`) deliberately — it is the task the north star
depends on, so it should never queue behind another container's startup. Every
other task in the whole set is staggered onto its own minute; verify with:

```bash
grep -h '^schedule:' */*/ai.nanoco.nanoclaw/tasks/*.md | sort | uniq -d
```

## Credentials: via OneCLI, not env vars

No API keys live in this template, and this agent needs **no write access
anywhere**. Everything it does is read, compute, narrate, or post one templated
acknowledgment. OneCLI's vault holds the credentials and injects them at the
proxy boundary, outside the agent container.

If a task here appears to need a write token, that is a signal the task belongs
to a different agent — not a reason to widen this one's access.

Two of its tasks need no network at all, which is why they keep working when
everything else is rate-limited or down:

| Task | Network | Why it matters |
|------|---------|----------------|
| `unanswered-watch` | none — reads local message state | Survives an outage of the very API it's compensating for |
| `workspace-backup` | git push only | Local disk → remote, no third-party API |

## Known risk: `dev-metrics-report` is the one oversized prompt here

Measure the task prompts and one stands out badly:

```bash
for f in ai.nanoco.nanoclaw/tasks/*.md; do
  printf '%6s  %s\n' "$(awk '/^---$/{c++; next} c>=2' "$f" | wc -w)" "$(basename "$f")"
done | sort -rn
```

`dev-metrics-report` is ~1,130 words against a median of about 280 — roughly
**four times** the next largest, with eleven distinct interpretive sections
(ready-to-merge, first-response backlog, unmerged ratio, return nudges,
contribution concentration, candidate contributors, degraded repos, …) over
twenty-plus data fields. Functionally it is several reports wearing one task's
name.

That matters here specifically, because **instruction-following is the first
capability to degrade on a small model**, and this is the longest conditional
prompt on the weakest tier in the system. The mitigations already in place are
real — the gate computes every number, so the model only narrates, and `null`
means "unavailable, never zero" — but they reduce the risk rather than remove
it.

Two things follow:

- **Week one, read this report's output closely** rather than skimming it. It
  is the most likely place to find a section quietly ignored or two numbers
  transposed. If that happens, the fix is to split the task, not to switch
  models: splitting shrinks each prompt to something the tier handles well and
  lets you pause a section you don't read.
- **Don't add to it.** New metrics belong in a new task with its own gate and
  its own schedule. This is also the general rule for this agent — one task,
  one question, one short answer.

By contrast, the other agents' single tasks really are single:
`content-draft-cycle` is ~170 words with two trigger branches (a release, or
the weekly evergreen floor) and produces exactly one draft per wake.

## Costs

**Zero tokens against your subscription.** Every wake here runs against the
local model, so the 11 tasks in this template are free in the sense that
matters: they don't consume the window the lead agent needs to answer people.

The real cost is **memory**. On a 16 GB Mac mini the model (~2 GB resident)
shares unified memory with Docker, the sandbox VM, and Postgres — there is no
separate VRAM. Watch `ollama ps` and `docker stats` during a busy period in
week one. If it's strained, the levers in order are: pause optional tasks →
leave the marketing agent unstamped → drop to a smaller model
(`gemma3:1b`, ~1 GB).
