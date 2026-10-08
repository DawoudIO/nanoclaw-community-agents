# Community Agent Set for NanoClaw

One agent template that runs an open-source project's community work with
**one public voice**. Its job is to help Discord and GitHub users with
questions and answers — cheaply, before people give up on GitHub or Discord.

| Template | Role | Model | Public voice |
|---|---|---|---|
| [`opensource/community-manager`](opensource/community-manager/) | Manager — replies, escalation, first response on GitHub, a daily picture of what is released and what is coming | Claude Sonnet | **Yes** |

The template's own README has the detail.

**Nothing here writes content.** Posts, announcements and campaign copy stay
with the project's owner; this set answers people, triages, and reports.
Project metrics are not an agent job either — they run as GitHub Actions in
the project's own repos.

## Install

```bash
git clone https://github.com/DawoudIO/nanoclaw.git
git clone https://github.com/DawoudIO/nanoclaw-community-agents.git

cd nanoclaw-community-agents
bash scripts/install-templates.sh     # copies the template into ../nanoclaw/templates/

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
- **One public voice, enforced structurally, not by instruction.** There is
  one agent and one bot identity; nothing else in the system can post.
  `follow-up-nudge` checks in weekly on contributors who went quiet: a PR
  idle a week, an issue where a posted workaround got no reply — one kind
  comment, an offer of help, the team chat invite.
  `unanswered-watch` is its safety net for a question that scrolled past —
  the agent was busy, restarting, or in another channel. Every 10 minutes a
  no-network gate checks whether the newest message in a support channel is
  an inbound one that has sat past the grace period, and wakes the agent to
  answer it for real. What it does not cover, honestly: the agent's own
  usage window running out. It runs on the same credential, so an exhausted
  window exhausts it too — see `docs/OPERATIONS.md` → Model budget for what
  does protect against that.
- **Agents never hold keys.** Every credential lives in the OneCLI vault and
  is injected at the egress proxy, outside the containers. An agent that
  asks you for a raw key is broken or compromised.
- **Stateless by design.** The agent rebuilds context from the project's
  repos on cold start, and `project-context` keeps that picture current: once
  a day it fetches what landed since yesterday, which agent skills and docs
  changed, and what is released versus merged-but-unreleased, writes
  `release-state.csv`, and wakes the agent only when something changed. Nothing
  is published anywhere. The question ledger holds community members' words,
  so it is never published either; losing it at a rebuild is accepted on
  purpose — it rebuilds from live traffic over the following weeks.
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
> only. A PR to `nanocoai/nanoclaw-templates` carries just the template
> directory — that catalog has its own README.
