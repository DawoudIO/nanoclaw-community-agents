# Upstream issue tracker — candidates for nanocoai/nanoclaw

Platform behaviors observed on the previous install (v?, pre-sandbox) that
likely affect every NanoClaw user. Rule: **confirm on the clean sandbox
install first** (`nanoco/nanoclaw:sbx-claude-alpha`), then file — one issue
each, include the image tag, reference existing issue #411 where relevant.
Update the Status column as tonight's testing progresses.

| # | Candidate issue | Type | Status |
|---|---|---|---|
| 1 | Message IDs are not one monotonic sequence across messaging groups / directions, but nothing documents their semantics — agents (and humans) misread cross-sequence comparisons as forgery evidence | docs/bug | observed old install; confirm on clean |
| 2 | Task-shaped prompts fire with no backing task session (`append-log` → "no task session to derive it from"; series absent from `ncl tasks list`) — phantom re-fires of cancelled/stale tasks, or an injection surface | bug (serious) | observed 3× in one morning; try repro: cancel a recurring task, watch subsequent slots |
| 3 | Task rows mutate without an acting session: cancelled series recreated as a new live row (`-3362` → `-6414`), `origin_session_id` pointing at a session with no `messaging_group_id`/`thread_id`; no audit trail on task-table writes | bug (serious) | observed; needs admin-level repro |
| 4 | No session attribution on outbound messages: multiple sessions of one agent DM the owner indistinguishably — the root of a day-long false "impersonation" incident. Feature: origin tag per message (e.g. "via task <series>") | feature | confirmed by design; file as enhancement |
| 5 | Concurrent sessions share one group workspace with no write attribution — file edits/staging appear "between two git status calls" of another session; agents read sibling writes as tampering. Feature: per-session write audit log or advisory attribution | feature/bug | observed; confirm with two parallel sessions on clean install |
| 6 | Context reset/compaction happens mid-conversation without notifying the agent or owner ("missing memory of a chunk of today's session") | bug/docs | observed once |
| 7 | Docs don't state what's available inside task `script:` gates — which binaries ship in the agent image (`bash`, `curl`, `jq`?) and whether `ncl` is callable from a script | docs | our health-check gate now self-reports missing jq/ncl (once) and the integrity gate falls back to a manual wake — if either fires on the clean install, file this with that evidence |
| 8 | All `ncl tasks` verbs open to agent callers regardless of `cli_scope` — scheduled tasks are the persistence vector in published injection research; feature: task-mutation approval gate or prompt integrity (hash) | security/feature | per public docs + embracethered research; reference issue #411 |
| 9 | Discord adapter: raw URLs and markdown links render unclickable; proactive rich cards need a two-step send_message→send_card dance | bug | observed old install; confirm on clean |
| 10 | Manually-created messaging-group destinations silently fail outbound (no Discord adapter association) — should error loudly instead | bug | observed old install; confirm on clean |
| 11 | sbx kit: default network allowlist lacks common analytics hosts (GA4 `analyticsdata.googleapis.com`, PostHog, Gmail) — fine as policy, but worth a documented "extending the allowlist" section in the kit README | docs (file on docker/sbx-kits-contrib) | confirmed from spec.yaml |
| 12 | No documented tool for an agent to construct its own clickable Approve/Reject card for an arbitrary decision (only the built-in self-mod `install_packages`/`add_mcp_server` and OneCLI credential flows get real approval buttons, per `src/modules/approvals/`) — worth an upstream ask, since it would let judgment-call approvals (not just outbound-API-backed ones) use real buttons too | feature | confirmed absent from the approvals module's docs; verify no agent-facing equivalent exists on the clean install before filing |
| 13 | No documented upgrade path for sbx-kit installs: is in-place update supported, or is recreate-the-sandbox the intended flow? Also: no export/import for channel wirings, which makes recreate tedious on servers with many channels | docs/feature | ask upstream; recreate assumed in our runbook |

## Filing checklist (per issue)

- [ ] Reproduced on clean sandbox install (or marked "old install only — may be
      fixed/config-specific" in the issue body)
- [ ] Version/image tag + minimal repro steps + expected vs actual
- [ ] No deployment secrets or private channel names in the issue text
- [ ] Cross-referenced related issues (#411 for anything injection-adjacent)
- [ ] Status column updated here with the filed issue URL
