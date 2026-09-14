# Community Agent Set for NanoClaw

Four agent templates that run an open-source project's community work as a
team with **one public voice**: awareness, response, proactive issue
detection, and security — at low cost, before people give up on GitHub or
Discord.

| Template | Role | Model | Public voice |
|---|---|---|---|
| [`opensource/community-manager`](opensource/community-manager/) | Lead — replies, escalation, relays the sub-agents | Claude Sonnet | **Yes, the only full one** |
| [`opensource/community-coding`](opensource/community-coding/) | Reviewer — issue/PR triage, security advisories, docs currency, repo and contributor health; holds the line when the lead is rate-limited | Claude Haiku | Holding replies only |
| [`opensource/community-marketing`](opensource/community-marketing/) | Measurement — follower counts and web traffic. Writes no content. **Optional, not stamped by default** | Claude Haiku | No |

The lead works standalone and stamps the other two itself, during setup,
once it knows which jobs you want. Each template's own README has the detail.

## Install

```bash
git clone -b community-fixes-2026-08-24 https://github.com/DawoudIO/nanoclaw.git
git clone https://github.com/DawoudIO/nanoclaw-community-agents.git

cd nanoclaw-community-agents
bash scripts/install-templates.sh     # copies the 4 templates into ../nanoclaw/templates/

cd ../nanoclaw
./nanoclaw.sh                         # "From local templates" → opensource/community-manager
```

Then DM the agent — it interviews you for everything else. `nanoclaw.sh`
handles the container, the vault, and your first agent; `bash
scripts/install-templates.sh --check` tells you if your copy has drifted
from this repo (re-run after every `git pull` here).

Read next, in this order:

1. **[PREREQS.md](PREREQS.md)** — every credential to create, before you start.
2. **[docs/INSTALL.md](docs/INSTALL.md)** — the full runbook.
3. **[docs/CHECKPOINTS.md](docs/CHECKPOINTS.md)** — the ready gate to pass before calling it live.
4. **[docs/OPERATIONS.md](docs/OPERATIONS.md)** — day 2 and beyond: tasks, budget, updates.
5. **[docs/REPORTING-STANDARD.md](docs/REPORTING-STANDARD.md)** — the shape every agent report follows.
6. **[docs/UNINSTALL.md](docs/UNINSTALL.md)** — tearing down, and what's left behind.

## How it's built

- **Scripts do the work; agents do the judgment.** Recurring tasks are
  script-gated — deterministic fetch/diff/threshold logic runs as bash with
  no model involved, and the agent wakes only when there's something to
  judge. `bash scripts/gen-task-table.sh` prints the current task table,
  generated from the task files so it can't drift from what ships.
- **One public voice, enforced structurally, not by instruction.** The
  Marketing agent has no channel wiring at all — it can't post publicly even
  if told to. The Reviewer's `unanswered-watch` is the one exception: the
  support channels only, under the lead's own bot identity, and a
  template-only acknowledgment it's forbidden to write freely — a receipt,
  never a resolution.
- **Agents never hold keys.** Every credential lives in the OneCLI vault and
  is injected at the egress proxy, outside the containers. An agent that
  asks you for a raw key is broken or compromised.
- **Stateless by design.** Agents rebuild context from the project's repos
  on cold start. The few things that can't be reconstructed (follower
  counts, the question ledger) are append-only and covered by the workspace
  backup.
- **Setup is a conversation.** You DM the lead; its `welcome` skill
  interviews you, and configuration is runtime data, not a template edit.

## Staying up to date

The running system is a **sealed package, not a checkout** — never `git
pull` inside a live sandbox; the runtime, DB schema, and adapters version
together, and there's no supported in-place upgrade.

Upgrades are image pulls **pinned by digest**.
[`platform-baseline.json`](platform-baseline.json) records the exact
`sha256` this set was last verified against — check it against
`versions.json`'s `agent-image` field by hand; there's no automated watcher
for it. See `docs/OPERATIONS.md` → "Staying up to date" for the
pull/restamp/restore procedure.

## Other

- **[UPSTREAM-ISSUES.md](UPSTREAM-ISSUES.md)** — platform issues found on a
  real install, for filing against `nanocoai/nanoclaw`.
- No migration runbook, by design: every install is fresh, driven by the
  welcome interview. Revoke the old deployment's credentials once the new
  one is verified live.
- This template set was extracted from a real deployment (ChurchCRM's
  community agent) and generalized.

> This README, `docs/`, and `UPSTREAM-ISSUES.md` are for this staging repo
> only. A PR to `nanocoai/nanoclaw-templates` carries just the four template
> directories — that catalog has its own README.
