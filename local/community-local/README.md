# Community Local Ops Agent Template

The narration tier: it runs the cheapest cloud-capable model (Haiku), same as
the Reviewer, and its job is to narrate numbers a script already computed,
keep repo mirrors fresh, and post a templated holding acknowledgment when the
lead is rate-limited or down. **For this phase it shares the same usage
window as every other agent** — a local-model provider (e.g. Ollama) was
evaluated and set aside as too much host setup friction to get the system
working end to end first; see `SKILLS-ADOPTION.md` if you want to revisit
that later.

It owns the largest share of the recurring work in this set, because most of
that work is mechanical by construction: a gate script fetched and computed the
data, and the agent's only job is to say what it means in a sentence or two.

## Why local

The lead agent (`support/community-support`) answers people, and everything
it's given needs public-facing judgment. This tier's work never does — it's
narration of pre-computed data or a fixed-template acknowledgment — so it
runs on the cheapest capable model instead, keeping Sonnet-class spend where
judgment actually matters. It's also who holds the line with a templated
acknowledgment (never an answer) when the lead is rate-limited or down,
logging the message for the lead to pick up later.

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
│   └── tasks/                          # 12 tasks, all created paused
│       ├── unanswered-watch.md         # the one the north star depends on
│       ├── repo-mirror-sync.md
│       ├── dev-metrics-report.md
│       ├── contributor-nudge.md          # 20-30 day re-engagement window
│       ├── ready-to-merge.md           # split out of dev-metrics-report:
│       │                               # approved-and-open PRs, 2×/day
│       ├── weekly-analytics-report.md
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

It stamps on the cloud default (Haiku), same as the other sub-agents — no
local model runtime to detect or wire for this phase. (A local-model
provider, e.g. Ollama, is a possible later optimization if you want this
agent off the shared window — see `SKILLS-ADOPTION.md` for why it was set
aside and how it would be wired back in.)

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

## Shared repo mirror — one checkout, every agent can read it

`repo-mirror-sync` writes to `/workspace/shared-repos`, not this agent's own
`plugin-data/` — a host directory the owner mounts **read-write here and
read-only into every other stamped agent** (Lead, Reviewer, Marketing), via
NanoClaw's own mount mechanism (`ncl groups config add-mount`, gated by an
owner-controlled allowlist — neither this nor any other agent can grant
itself this access). One credentialed writer, everyone else reads the same
checkout instead of independently re-fetching or re-cloning their own copy —
this is what makes the Reviewer's `dependabot-pr-review`/`docs-currency-watch`/
`security-advisory-sweep` able to grep real file contents instead of relaying
through this agent or the lead for every question.

**One-time owner setup, after all agents are stamped:**

```bash
# 1. Authorize the host directory (owner-only, outside any container's reach)
#    — run wherever NanoClaw itself runs, typically inside the sandbox.
mkdir -p shared-repos
pnpm exec tsx setup/index.ts --step mounts --force -- \
  --json '{"allowedRoots":[{"path":"'"$(pwd)"'/shared-repos","allowReadWrite":true}],"blockedPatterns":[]}'

# 2. Grant THIS agent (local ops) read-write — it's the only writer
ncl groups config add-mount --id <local-ops-group-id> \
  --host "$(pwd)/shared-repos" --container /workspace/shared-repos

# 3. Grant every other stamped agent read-only
ncl groups config add-mount --id <lead-group-id> \
  --host "$(pwd)/shared-repos" --container /workspace/shared-repos --ro
ncl groups config add-mount --id <coding-group-id> \
  --host "$(pwd)/shared-repos" --container /workspace/shared-repos --ro
ncl groups config add-mount --id <marketing-group-id> \
  --host "$(pwd)/shared-repos" --container /workspace/shared-repos --ro

# 4. Apply — mounts only take effect after a restart
ncl groups restart --id <local-ops-group-id>
ncl groups restart --id <lead-group-id>
ncl groups restart --id <coding-group-id>
ncl groups restart --id <marketing-group-id>
```

**Freshness, not real-time.** `repo-mirror-sync` runs every 15 minutes
(`:7/22/37/52`), and stamps `/workspace/shared-repos/.last-sync-epoch` (Unix
seconds, UTC) after each attempt — any agent reading the mirror for a
judgment call should check that file's age first and say "as of the last
sync" rather than implying the code is current to the second. This is a
deliberate trade: tight enough that staleness is a non-issue for triage and
security-reachability judgment, without adding a live sync-then-act round
trip through the lead (which would burn the Lead's cycles on every Reviewer
question — see PREREQS.md's model-budget trap).

**Optional, not required.** Without the mount, every agent falls back to what
it did before: fetching file contents via the GitHub API directly, or asking
the lead to relay a grep from this agent. Nothing breaks if the owner skips
this setup — it's strictly an efficiency and resilience improvement (a real
install hit an hour-plus OneCLI gateway outage that blocked every GitHub API
call at once; a filesystem mount doesn't depend on that gateway being up).

## Credentials: via OneCLI, not env vars

No API keys live in this template, and its write access is narrow and
single-purpose: `workspace-backup` pushes to one backup repo, and that's the
only write scope this agent has. Everything else it does is read, compute,
narrate, or post one templated acknowledgment. OneCLI's vault holds the
credentials and injects them at the proxy boundary, outside the agent
container.

If a task here appears to need a write token beyond the backup repo, that is
a signal the task belongs to a different agent — not a reason to widen this
one's access.

Two of its tasks need no network at all, which is why they keep working when
everything else is rate-limited or down:

| Task | Network | Why it matters |
|------|---------|----------------|
| `unanswered-watch` | none — reads local message state | Survives an outage of the very API it's compensating for |
| `workspace-backup` | git push only | Local disk → remote, no third-party API |

## Known risk, now reduced: `dev-metrics-report` is still the largest prompt here

Measure the task prompts before trusting any claim in this section, including
this one:

```bash
for f in ai.nanoco.nanoclaw/tasks/*.md; do
  printf '%6s  %s\n' "$(awk '/^---$/{c++; next} c>=2' "$f" | wc -w)" "$(basename "$f")"
done | sort -rn
```

**The split happened.** `dev-metrics-report` was ~1,130 words with eleven
interpretive sections over twenty-plus fields — several reports wearing one
task's name, on the weakest tier in the system, which is precisely where a long
conditional prompt fails first. It was split by **capability**, and that is what
decided who owns each half:

- **The judgment half left this tier.** Unmerged ratio, contribution
  concentration, and delegation candidates are now
  `contributor-health-review`, a weekly task on the **Reviewer** (Haiku). Those
  numbers are arithmetic, but each one is meaningless until somebody decides
  *why* it moved — a rising unmerged ratio is either incoming low-quality PRs
  or maintainer burnout, opposite problems with opposite responses behind the
  same number — and naming a person as a delegation candidate is the last
  judgment you want on a small model.
- **The list half stayed here.** Approved-and-open PRs are now
  `ready-to-merge`, twice daily, still local — because the GitHub search
  decides what counts as approved, so the output is a list to relay rather than
  an assessment to make. Capability, not topic, is the line.

What's left is pure narration: stars and forks, open issues and PRs, releases,
`awaiting_first_response`, `new_contributors_7d`, `return_nudges`,
`degraded_repos`, `quiet_heartbeat`. The prompt is ~660 words, down from
~1,130.

**It is still the largest prompt on this tier** — roughly 1.3× the next
largest (`repo-mirror-sync`, ~510 words, grown since the shared-mirror
addition) against a median near 300 — so it still earns
week-one attention, just less of it. The standing mitigations are unchanged and
still load-bearing: the gate computes every number, so the model only narrates,
and `null` means "unavailable, never zero". One new one worth knowing: the
return-nudge loop is **capped at 2 checks per repo per run**. It was the one
serial network path left in an otherwise parallel script, at up to 8s a call
against a 30s script budget — four contributors entering the nudge window on
the same day could blow the timeout and kill the script before it printed
anything, which under this contract means the task silently does nothing. The
cap is surfaced as `nudges_deferred` so the truncation is never silent, and the
nudge ledger makes it safe: whoever is skipped today is still in the window
tomorrow.

Two things still follow:

- **Week one, read this report's output closely** rather than skimming it. It
  is still the likeliest place in this template to find a section quietly
  ignored or two numbers transposed. If that happens, the fix is to split
  again, not to switch models.
- **Don't add to it.** New metrics belong in a new task with its own gate and
  its own schedule — and that rule now has a worked example rather than being
  advice: the two tasks above came out of exactly this prompt, and the split
  chose their owning agent by asking whether the output was a list or an
  assessment. This is the general rule for this agent — one task, one question,
  one short answer.

By contrast, the other agents' single tasks really are single:
`content-draft-cycle` is ~170 words with two trigger branches (a release, or
the weekly evergreen floor) and produces exactly one draft per wake.

## Costs

**Cheapest cloud tier, but not free.** This agent runs on Haiku for this
phase, sharing the same subscription window as the Reviewer and (in bursts)
the lead — its 12 tasks are low-judgment narration, not zero-cost. Most are
script-gated, so a quiet week costs near nothing regardless; see
`docs/OPERATIONS.md` → Model budget for the real per-agent token floors and
the shared-window trade-off behind running this tier on cloud instead of a
local model.

If you later adopt a local-model provider for this agent (see
`SKILLS-ADOPTION.md`), the real cost becomes host memory instead of tokens —
watch `docker stats` during a busy period and, if it's strained, pause
optional tasks or leave the marketing agent unstamped before dropping to a
smaller model.
