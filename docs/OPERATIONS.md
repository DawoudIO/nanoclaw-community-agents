# Operations — day 2 and beyond

Everything after go-live: token budget, the full task reference, keeping the
system alive, and the update policy. Install steps are in
[INSTALL.md](INSTALL.md).

## Keeping it running — the session IS the system

`sbx run` is a foreground process: **NanoClaw stops when its terminal
session closes.** A laptop reboot, an SSH drop, or a closed tab takes the
whole system down — and a stopped system cannot report its own death, so the
symptom is pure silence. Two defenses:

- Run `sbx run` somewhere durable — a `tmux`/`screen` session on an
  always-on machine, not a laptop tab. After any host reboot, restarting it
  is a manual step: same `sbx run` command; the sandbox's state volume
  persists, so agents, config, and ledgers come back as they were.
- **Watch for the weekly heartbeat.** The lead's `health-check` task DMs a
  one-line "all checks passed" proof-of-life at least every 7 days even when
  everything is fine. If more than ~8 days pass without it, the system is
  down — restart the sandbox on the host. Silence is the alarm.

## Models and token budget — right-sizing on a small plan

**Three agents is the right number — and it's cheaper than it looks.** Burn
comes from model *wakes*, not from agents existing: a stamped agent whose
tasks are paused costs nothing. 12 of 15 tasks are script-gated, so quiet
periods cost near zero regardless of agent count — and the two highest-
frequency gates (`dev-metrics-report` daily, `posthog-weekly-review` weekly)
don't just skip when unconfigured, they skip on any run where nothing
actually changed, with only a 7-day heartbeat forcing a wake so the channel
never goes silent long enough to look dead. That makes the team elastic:
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
`good-first-issue-health` → `draft-cleanup` → `dev-metrics-report` →
`social-metrics-snapshot` → `inbox-check` → reduce `github-ops-triage` to
2×/day → `content-draft-cycle` to 3×/week. The safety net (`health-check`,
`workspace-backup`, `weekly-identity-integrity-check`) and community replies
are the last things to give up — they're also nearly free, since all three
are gated.

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
| `security-advisory-sweep` (6×/day) | coding | on new alerts | coding PAT + Dependabot alerts (read) permission + `COMMUNITY_REPOS` | silent skip |
| `dev-metrics-report` (daily) | coding | only on notable change, else weekly heartbeat | PAT + `COMMUNITY_REPOS` | silent skip |
| `posthog-weekly-review` (Mon) | coding | only on insight change, else weekly heartbeat | PostHog key + `POSTHOG_PROJECT_ID` + allowlist | silent skip |
| `good-first-issue-health` (Mon) | coding | weekly | coding PAT + `COMMUNITY_REPOS` (+ optional `GFI_LABEL`) | silent skip |
| `inbox-check` (2×/day) | marketing | every run | email MCP + read-only mailbox + allowlist | leave paused |
| `content-draft-cycle` (weekdays) | marketing | every run | marketing PAT + brand source filled in | leave paused |
| `weekly-analytics-report` (Sun) | marketing | weekly | GA4 OAuth + `GA4_PROPERTY_ID` + allowlist | silent skip |
| `draft-cleanup` (daily) | marketing | on stale PRs | PAT + `CONTENT_REPO` | silent skip |
| `social-metrics-snapshot` (Sun) | marketing | every run | public profile pages (no credentials) + **sandbox allowlist entries for the platform hosts** | leave paused until platforms are configured and allowlisted — it guards the one stateful asset (follower series; durable copy = the lead's ledger) |

Shipped times (UTC under the kit): health-check every 3h · backup 08:40 ·
release watch every 3h · lead triage weekdays 13:00 · coding triage every 6h ·
sweep every 4h · dev metrics 12:00 · PostHog Mon 15:00 · GFI health Mon 16:00 ·
inbox 06:00 + 16:00 · content weekdays 13:30 · social snapshot Sun 13:00 ·
GA4 Sun 14:00 · cleanup 17:30 · integrity check Mon 15:00. Rules of thumb: put the
integrity check before your own workday, dev metrics ahead of your dev
channel's hours, inbox checks at your real start/end of day. Ungated tasks cap
at 4 fires/day — the script gate is what lets health-check (8×) and the sweep
(6×) exceed it.

## Staying up to date — SHA-pinned pulls only, never `git pull`

**Hard rule: never update NanoClaw in place.** No `git pull` of the NanoClaw
source inside the sandbox, no in-place package upgrade, no floating-tag
re-pull under a live system. The runtime, its database schema, its task
table, and its adapters version together — pulling newer source or a newer
image under a running install desynchronizes them and corrupts the
deployment. NanoClaw documents no in-place upgrade path; do not invent one.

**All upgrades are digest-pinned image pulls plus a full recreate.** The
digest in [`platform-baseline.json`](../platform-baseline.json) is the exact
`sha256` this template set was last verified against — content-addressed, so
the same digest is byte-for-byte the same tested package everywhere. Pull by
digest (`docker.io/sbx/nanoclaw-kit@sha256:...`), never by tag, when you
actually upgrade; the `:latest` tag exists only so the watcher below can
notice that a new digest was published.

The system is built to make that upgrade path cheap: **cattle, not pets**.
Because almost nothing is stateful (context rebuilds from the web, config is a
conversation, the one durable file lives in the git backup), updating the
platform = recreating the sandbox — the same runbook you used to build it.

**Noticing updates is automated, not an agent job.** The
[`platform-watch`](.github/workflows/platform-watch.yml) Action in this repo
runs weekly: it compares the sbx VM image digest (`sbx/nanoclaw-kit:latest`,
the prebuilt image this repo actually pulls), the latest NanoClaw release,
and the kit spec against `platform-baseline.json`,
and opens an issue here with a refresh checklist when any of them move.
Security advisories for NanoClaw deserve an immediate refresh; otherwise batch
refreshes when the issue appears.

**The refresh procedure** (~1 hour, mostly waiting on pulls):

1. Confirm the last workspace backup ran — the lead's workspace carries
   `project-config.md` and the durable follower-series ledger
   (`plugin-data/community-support/social-metrics-history.jsonl`, appended by
   the lead each time marketing hands over a snapshot), the only things worth
   restoring.
2. Read the watch issue: it names the new digest. Verify it's what you
   intend (release notes, no open security advisories), then update
   `platform-baseline.json` to the new digest — that file is the record of
   what you verified.
3. `sbx rm nanoclaw` → `docker pull docker.io/sbx/nanoclaw-kit@sha256:<the
   verified digest>` → `sbx run` against that same digest. Never pull the
   bare `:latest` tag for the actual upgrade — the tag can move between your
   decision and your pull.
4. Restamp the latest templates from this repo; re-run `/add-discord` with the
   **same** Discord bot (its token comes from the Discord developer portal —
   the VM's stored copy died with the VM); re-verify the owner-DM round trip.
5. Re-enter the 3 GitHub PATs in the fresh vault, selective mode (~5 min).
   No rotation needed — refresh isn't compromise.
6. Restore the follower-series ledger from the backup repo into the lead's
   `plugin-data/community-support/`; either restore `project-config.md` too or
   just answer the welcome interview again.
7. Smoke tests per INSTALL.md §7, and re-test anything in UPSTREAM-ISSUES.md
   against the new build before closing the watch issue.

**Template updates** flow the other way: edit this repo, restamp. Personas and
skills are read-only inside stamped agents by design, so a restamp *is* the
deployment mechanism — and the watch issue is a natural moment to fold in any
accumulated template improvements. Whether NanoClaw supports an in-place
upgrade instead of recreate is undocumented — tracked as an upstream docs ask
in UPSTREAM-ISSUES.md.
