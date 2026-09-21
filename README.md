# Community Agent Set for NanoClaw

Two agent templates that run an open-source project's community work as a
pair, with **one public voice**. Together they watch, respond, catch
problems early, and flag security issues — cheaply, before people give up
on GitHub or Discord.

| Template | Role | Model | Public voice |
|---|---|---|---|
| [`opensource/community-manager`](opensource/community-manager/) | Manager — replies, escalation, relays the sub-agents | Claude Sonnet | **Yes, the only full one** |
| [`opensource/community-helper`](opensource/community-helper/) | Helper — issue/PR triage, security advisories, docs currency, and every number the project tracks (dev metrics, contributor health, traffic, followers); holds the line when the manager is rate-limited | Claude Haiku | Holding replies only |

The manager works standalone and stamps the Helper itself, during setup, once
it knows which jobs you want. Each template's own README has the detail.

**Nothing here writes content.** Posts, announcements and campaign copy stay
with the project's owner; this set answers people, triages, measures, and
reports.

## Install

```bash
git clone https://github.com/DawoudIO/nanoclaw.git
git clone https://github.com/DawoudIO/nanoclaw-community-agents.git

cd nanoclaw-community-agents
bash scripts/install-templates.sh     # copies the 2 templates into ../nanoclaw/templates/

cd ../nanoclaw
./nanoclaw.sh                         # "From local templates" → opensource/community-manager
```

Then DM the agent — it interviews you for everything else. `nanoclaw.sh`
handles the container, the vault, and your first agent. Run `bash
scripts/install-templates.sh --check` after every `git pull` here, to catch
a copy that's drifted from this repo.

Read next, in this order:

1. **[PREREQS.md](PREREQS.md)** — every credential to create, before you start.
2. **[docs/INSTALL.md](docs/INSTALL.md)** — the full runbook.
3. **[docs/CHECKPOINTS.md](docs/CHECKPOINTS.md)** — the ready gate to pass before calling it live.
4. **[docs/OPERATIONS.md](docs/OPERATIONS.md)** — day 2 and beyond: tasks, budget, updates.
5. **[docs/REPORTING-STANDARD.md](docs/REPORTING-STANDARD.md)** — the shape every agent report follows.
6. **[docs/UNINSTALL.md](docs/UNINSTALL.md)** — tearing down, and what's left behind.

## How it's built

- **Scripts do the work; agents do the judgment.** Recurring tasks are
  script-gated: plain bash checks run first, and the agent wakes only when
  there's something to decide. `bash scripts/gen-task-table.sh` prints the
  current task table, generated straight from the task files so it can't
  go stale.
- **One public voice, enforced structurally, not by instruction.** The
  Helper has no channel access at all, with one exception: `unanswered-watch`,
  its safety net for when the manager itself goes silent (rate-limited,
  crashed, mis-wired). It watches support channels for a message that's sat
  too long, then posts one fixed line, under the manager's own bot identity
  so the community never sees a second voice. It can't write anything else.
  It's a receipt, never a resolution — it answers nothing, it just proves
  someone's still there.
- **Agents never hold keys.** Every credential lives in the OneCLI vault and
  is injected at the egress proxy, outside the containers. An agent that
  asks you for a raw key is broken or compromised.
- **Stateless by design.** Agents rebuild context from the project's repos
  on cold start. A few things genuinely can't be reconstructed — follower
  counts, GA4 traffic, repo metrics history — so the Helper publishes those
  daily, append-only, to a branch in the project's own repo. The manager's
  question ledger is different: it holds community members' words, so it's
  never published at all. That loss is accepted on purpose — it just
  rebuilds from live traffic over the following weeks.
- **Setup is a conversation.** You DM the manager; its `welcome` skill
  interviews you, and configuration is runtime data, not a template edit.

## Staying up to date

The running system is a **sealed package, not a checkout**. Never `git
pull` inside a live sandbox — the runtime, DB schema, and adapters version
together, and there's no supported in-place upgrade.

Upgrades are image pulls **pinned by digest**.
[`platform-baseline.json`](platform-baseline.json) records the exact
`sha256` this set was last verified against. Compare it to `versions.json`'s
`agent-image` field by hand — there's no automated watcher for this yet.
See `docs/OPERATIONS.md` → "Staying up to date" for the full
pull/restamp/restore steps.

## Other

- **[UPSTREAM-ISSUES.md](UPSTREAM-ISSUES.md)** — platform issues found on a
  real install, for filing against `nanocoai/nanoclaw`.
- No migration runbook, by design: every install is fresh, driven by the
  welcome interview. Revoke the old deployment's credentials once the new
  one is verified live.
- This template set was extracted from a real open-source project's
  community-agent deployment and generalized.

> This README, `docs/`, and `UPSTREAM-ISSUES.md` are for this staging repo
> only. A PR to `nanocoai/nanoclaw-templates` carries just the two template
> directories — that catalog has its own README.
