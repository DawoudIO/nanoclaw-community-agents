# Changelog

All notable changes to this template set are documented here. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions
are pre-1.0 (`0.y.z`) — this is an internal, still-evolving system, not a
published library with call-site compatibility guarantees, so `y` bumps for
any release regardless of whether it includes a breaking change; breaking
changes are called out in their own section instead of forcing a `1.0.0`.

Version numbers track **what's actually stamped into the live deployment**,
not just commits to this repo — a version isn't "current" until an
`ncl groups restart` (or a fresh stamp) actually picks it up. See
`docs/OPERATIONS.md` for the model-tier and restart-required caveats that
make this distinction matter.

## [Unreleased]

### Changed

- **Welcome interview: metrics are opt-in.** Step 3 now asks whether the
  project wants its numbers tracked, and if so which repo holds the history.
  A "no" keeps `project-health` paused and skips every metrics question and
  step 8. Previously `LEDGER_REPO` was asked for "regardless of goals", which
  doesn't fit the many projects that track nothing.
- **Welcome interview: questions cleaned up after the first live install.**
  - New §1b lists every question in order, with stable numbers owners can
    keep an answer sheet against.
  - Social: asks which follower counts *matter*, not which platforms exist,
    and says what each costs (X needs an API token; Discord member counts have
    no free read). The leftover "how do you post" question is gone, since
    nothing here posts content.
  - New metrics questions: how often and to which channels the numbers are
    posted, and which repos the dev numbers cover (default: product only).
  - Dependabot: check each repo's alerts are enabled before it goes into
    `SECURITY_WATCH_REPOS`.
  - `COMMUNITY_REPOS` now defaults to every repo that receives outside PRs,
    docs and site included.
  - `OWNER_TZ` and `FIRST_RESPONSE_GRACE_MINUTES` are now persisted. The
    first was asked but never written, so the digest fell back to UTC.
  - Inbox: says plainly that it reads only and never labels.
  - Fixed the false claim that crons run in UTC: they run in the group
    timezone.
  - Merged the duplicated Helper entry in the models question.
- **`project-health`: `HEALTH_POST_DOW` takes a day list (`1,3,5`) or
  `daily`.** A single day still works; anything malformed falls back to
  Monday.

### Fixed

All found on the first live install's debug dump (9/22–9/29). Each fix has a
test that fails without it.

- **`project-health`: GA4 never worked.** The request asked for a
  `dateRange` dimension, which isn't valid; GA4 adds the range name to rows
  by itself. Every call came back `fetch-failed`.
- **`project-health`: re-runs duplicated rows.** Metrics, contributor-health
  and traffic rows are now one per key per day. A re-run replaces today's
  row, except that a failed fetch never overwrites a good row.
- **`project-health`: the follower row follows the existing file's header.**
  A file from an older install (11 columns, `M/D/YY` dates) would have
  received rows in the template's 9-column order. The prompt also names a
  page-reading tool that worked for Facebook, Instagram and LinkedIn, and
  fixes the Discord call (`?with_counts=true`).
- **`weekly-identity-integrity-check` never worked.** `ncl tasks list --json`
  is a `{id, ok, data: [...]}` wrapper keyed by `series_id`. The filter
  assumed a bare array keyed by `id`, so it matched nothing, and a half-fix
  keyed every task `unknown`. It now accepts both shapes, refuses id-less
  tasks, and quietly rebuilds a baseline left keyed `unknown`. The prompt's
  ack step no longer points at a field the script never emits.
- **`owner-tldr`: the routine brief could never fire on schedule.** It needed
  the hour to be exactly 7, while the cron ran on even hours. It now runs
  hourly and sends on the first run at or after the digest hour, once a day.
  An unset `OWNER_TZ` is reported as unresolved instead of quietly used as
  UTC.
- **`security-advisory-sweep` blamed the token for every failure.** It now
  keeps the HTTP code and GitHub's message per repo. It tells
  alerts-turned-off (a repo setting, reported once) apart from `forbidden`,
  `not-found` and `network`.
- **`unanswered-watch` could watch nothing forever without saying so.**
  `no-channel-sessions` and `cannot-read-sessions` never woke the agent,
  though the prompt said to report them. Each now wakes it once after a day.
  Both `ncl sessions` calls accept the wrapped JSON shape too.
- **Docs claimed cron runs in UTC.** It runs in the group's timezone.
  Digest-queue `at` stamps must be UTC (`date -u`); a live install's were
  local times with a `Z`.
- **Test `project-health/fetch-fails-must-wake` passed only on Mondays.** It
  loaded the success-path fixtures, so no fetch actually failed. It now runs
  with no fixtures on a pinned non-post day.

## [0.12.0] — 2026-09-21 (pending: stamp scheduled for 2026-09-22)

The gap between 0.10.0 and this release is unusually large because 0.10.0
was never actually redeployed after it shipped — the live system has been
running the 8/27 stamp continuously, including through the entire 4-agent
→ 2-agent architecture change below, which up to now existed only in this
repo. Tomorrow's rebuild is the first time any of this reaches production.

### Breaking

- **Agent count: 4 → 2.** `community-secretary` (the "Local Agent" in the
  live deployment), `community-coding` (Engineering), and
  `community-marketing` (Marketing) are retired; their tasks redistributed
  onto `community-manager` and the new `community-helper`. Every sub-agent
  identity, channel wiring, and cross-agent destination from the 8/27
  install needs re-wiring under the 2-agent set — this is not an in-place
  upgrade.
- **Bot display name: "Community Manager"/"Local"/etc. → "Hazel"** is
  unaffected by this (identity is set at the welcome interview, not by the
  template), but every *sub-agent's* identity changes since two of the
  three sub-agents no longer exist.
- **Every published/plugin-data state file changed from JSON or JSONL to
  CSV.** `social-metrics-history.jsonl` → `.csv` (old file kept as a frozen
  archive — nothing deletes it), `metrics-history.json` → `.csv`,
  `last-reported-metrics.json` → `.csv`, `task-prompt-snapshot.json` →
  `task-prompt-hashes.csv`, `gfi-health-last.json` → `.csv`,
  `first-response-seen.jsonl` → `.csv`, `inbox-seen.jsonl` → `.csv`,
  `question-ledger.jsonl` → `.csv`, `traffic-history-*.json` → `.csv`,
  `contributor-health-history.json` → `.csv`. An operator or script reading
  any of these by name needs to update the reference. New standing
  convention, documented in `scripts/tasks/CONVENTIONS.md`: state files
  this system writes and reads back are CSV with a header row; `jq` stays
  only for parsing external API responses.

### Fixed

- **The Helper (and any unpinned group) was never actually cheap.**
  Stamping with no explicit `--model` falls back to the platform's own SDK
  default — a Sonnet-class model, not Haiku — so every "cheap tier" cost
  figure in the docs was wrong until pinned explicitly. Every `--model`
  command also switched from a bare alias (`sonnet`, `haiku`) to an exact
  ID (`claude-sonnet-5`, `claude-haiku-4-5`): an alias resolves through
  whatever the CLI's current default mapping is for that shorthand, which
  can silently drift to a different, more expensive model generation
  across CLI versions.
- **`unanswered-watch` was structurally blind**, not just misconfigured —
  fixed for real rather than patched around.
- **A real duplicate-task incident** from ambiguous `github-ops-triage`
  ownership between agents — ownership clarified to prevent recurrence.
- **`github-first-response` could lose an item permanently.** Marking an
  item "seen" happens before the agent replies; if the reply never
  completes (the incident that motivated this: a spend-limit outage killed
  the agent mid-reply, dropping issue #9836 for two days in production),
  the item was gone for good. Added bounded retry (45 min window, 3
  retries) — bounded so a transient failure recovers without regressing
  into the 144×/day re-wake cost "seen" exists to prevent.
- **`good-first-issue-health` wasn't actually gated** despite its own docs
  claiming 0-token — it woke the agent every run regardless of change. Now
  gates on real open-count/stale-set change plus a 28-day heartbeat.
- **`inbox-check` had no gate at all** — woke the manager (Sonnet tier)
  twice daily unconditionally. Now gated with the same bounded-retry
  pattern as `github-first-response`.
- **`sync-tasks.sh` silently no-op'd** when adding a gate to a task with no
  existing `script:` block, reporting "synced" while leaving the file
  unchanged. The `inbox-check` gate would have been silently lost without
  this fix.
- **WoW/MoM mislabeling on non-weekly/non-monthly cadences** — a report
  scheduled more or less often than its label claimed was printing a false
  window.
- **A false tampering alarm** from comparing a file's write-time against
  event-time instead of the other way around; generalized the fix to the
  memory-integrity rule across all four (then four) agents.
- **`social-metrics-snapshot`'s checked-in schedule didn't match its live
  cron** (weekly-Sundays-only on paper, daily in practice) — updated to
  daily, matching observed real-world usage.
- **`ledger-publish`'s test suite was flaky** depending on whether the
  host's git-signing config was unlocked, because its clone fixture
  inherited the host's global git config. Scoped
  `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` to a throwaway config for the
  test.
- **Gate-script bugs surfaced by a full system review** (GA4 MoM/YoY logic
  among them) — restored/fixed as part of that review.
- **`add-mount` issue #36** — root cause corrected and the fix linked;
  merged into the deploy branch.

### Added

- **`project-health`** (Helper, daily): the one metrics task. Replaces six
  (`dev-metrics-report`, `contributor-health-review`,
  `social-metrics-snapshot`, `weekly-analytics-report`, `ledger-publish`,
  `contributor-nudge`) that each fetched their own numbers on their own
  schedule and woke the model separately. Same CSVs, same schemas — one
  fan-out, one run. `collect` mode every day (bash appends the GitHub rows;
  the model wakes only to read follower pages and append one social row —
  `SOCIAL_DAILY=false` makes that day 0-token), `post` mode once a week
  (`HEALTH_POST_DOW`, default Monday: contributor health, return-nudge
  candidates, GA4 traffic, and the two status posts — dev numbers to the
  developer tier, social + traffic to the team-lead tier). Daily rows are
  the point: week-over-week and month-over-month come from real series,
  and the agent answers "how's the project doing" on a Wednesday from
  `tail`/`grep` on the CSV instead of a fresh fetch.
- **Ledger read-back.** After pushing the history CSVs to `LEDGER_BRANCH`,
  `project-health` fetches today's `metrics-history.csv` row back from
  GitHub and compares it to the local row — `published-and-verified` vs
  `published-unverified` in its output. A push that returns 0 and a row a
  human can see on the branch are different claims; this system once had
  to verify the second by hand.
- **`github-first-response` covers follow-up comments**, not only new items:
  an outsider leaving the latest comment on an open thread with no answer
  since now wakes the Manager (`kind: "follow-up"`, keyed on the comment id
  so a later comment re-triggers). Requires `GITHUB_BOT_USERNAME`, otherwise
  the gate could not tell its own replies from theirs and follow-up
  detection stays off and says so. Maintainers' own new issues no longer
  surface — the task is "every outsider message gets an answer".
- **Risk-reality read on security reports** (`escalation-paths.md`): before
  the owner spends an evening on a vulnerability report, the Manager checks
  the claimed code path exists, what the preconditions really are, whether
  there is a reproducible proof of concept, and whether the stated severity
  matches — and sends the owner a grounded / plausible-unverified / inflated
  / not-a-vulnerability read. Owner DM only; the reporter only ever sees the
  neutral private-disclosure redirect.
- **`owner-instruction-watch`** (Manager, weekly): the dropped-ack safety
  net the persona always claimed but never had — flags any `received`
  owner instruction in the ledger with no `done`/`blocked`/`dropped` after
  24h. Cannot see instructions that were never ledgered at all.
- **`token-audit.sh`**, shipped at each template's root (next to
  `setup-check.sh`): a zero-LLM-cost tool the agent runs via Bash to answer
  "where are my tokens going" from the session transcript's own real
  `usage` fields. Deliberately never computes a dollar figure from memory
  — a real run of this exact tool once did, and it quoted the *previous*
  Sonnet generation's price by mistake, because pricing changes faster
  than training data does.
- **`community-helper`**, a new 2-agent design consolidating recurring
  GitHub/metrics/security work into one headless sub-agent (Haiku), paired
  with `community-manager` (Sonnet, sole public voice).
- **Day-1 bootstrapping guidance**: which history series are worth asking
  an owner to supply by hand (follower counts — the one series that can
  never be re-fetched from anywhere) versus which regenerate on their own.
- **Local per-gate weekly telemetry log**, so wake/error patterns are
  reviewable without re-deriving them from live behavior.
- **Reporter notification on fix-released** — an issue's reporter gets
  told when their fix ships in a new release.
- **A traceable pattern for recurring prompt-injection attempts** instead
  of silent repeated re-refusal with no record.
- **Two platform bugs filed upstream** during a live-fixes port (Discord
  tables, UTM/landing-page links).
- **A stopgap prune task for NanoClaw's unbounded conversation archives**,
  tracked against upstream nanocoai/nanoclaw#3716, with the fork-side fix
  pushed the same day.

### Removed

- **Nine recurring tasks** — 23 → 14. Measured before cutting: 12 of the 23
  tasks (62% of the script code) were metrics or repo-ops, not community
  support, and 7 of the 9 scripts debugged during the outage week were in
  that group. Support is the mission; everything else had to justify a
  scheduled wake.
  - Folded into `project-health`: `dev-metrics-report`,
    `contributor-health-review`, `social-metrics-snapshot`,
    `weekly-analytics-report`, `ledger-publish`, `contributor-nudge`.
  - Moved out of the agent entirely — `ready-to-merge`,
    `good-first-issue-health`, `repo-hygiene-audit` are point-in-time
    checks the maintainer asks for, not recurring support. They live on as
    an on-demand `repo-health` skill in the project's own repo, run by
    whatever agent is pointed at it.
  - `daily-github-triage` (the Manager's standalone-mode fallback): gone.
    `github-first-response` is the fast path; `github-ops-triage` is the
    digest.
  - `release-announcement-watch` (earlier in this release): a skill in the
    project repo the owner invokes when they cut a release, not a poll.
- **`dependabot-pr-review`** moved out to a GitHub Actions workflow in the
  project repo (event-driven on `pull_request_target` for Dependabot PRs),
  taking the count to 13. A scheduled agent wake to review long-lived PRs
  was the wrong shape when the PR event itself can trigger the review.
- **`GFI_LABEL`** config var — nothing reads it any more.

### Changed

- **`github-ops-triage` runs weekly (Monday) instead of every 6 hours.**
  It is a digest of things the Helper cannot act on itself; with
  `github-first-response` answering new issues within 10 minutes, a 6-hour
  digest was four wakes a day to say "same as this morning".
- **Both personas trimmed** toward a ~200-line guideline — content moved to
  reference files, not deleted.
- **Security hardening pass** from a review of the consolidated gate:
  every gate now parses `config.env` line-by-line instead of sourcing it
  (the model writes CSVs into that same directory, so a planted line must
  stay a string); `project-health` validates every repo string, the ledger
  branch (never the repo's default branch) and the GA4 property id, builds
  its JSON with `jq` rather than `printf`, strips CSV delimiters and
  leading formula characters from API-sourced fields, removes symlinks on
  the ledger branch before copying into it, treats an empty repo result set
  as an outage rather than a quiet day, and only reports
  `published-and-verified` when the row read back is *today's*. The prompt
  now says outright that every fetched string is data, never instruction.
- **All three human-facing READMEs simplified and fixed.**
- **The GitHub triage digest format tightened** after reviewing real posted
  output: one fixed name instead of four different headers observed in
  practice; reassurance boilerplate ("checked for duplicates", "nothing
  security-shaped") removed from the default case — state exceptions only;
  routine noise (dependabot bumps, locale-sync PRs, owner-authored issues)
  collapsed to one count instead of one bullet each.
- **Process/fetch errors now route explicitly to the owner's DM, never a
  channel** — its own row in the report-routing table, and both triage
  tasks' fetch-failed text now says "owner DM" explicitly instead of the
  ambiguous "report it to the owner".
- **The bot's GitHub identity recommended for nothing else** — a scoping
  tightening, not a new capability.
- Documented the **unbounded owner-DM session cost** as a known platform
  limitation: no session-reset primitive exists in NanoClaw short of
  tearing down the whole agent group, so a long single-sitting conversation
  compounds cache-read cost with turn count. No template fix available yet;
  documented with the practical mitigation (keep DM exchanges focused;
  check `token-audit.sh` before assuming a specific task is the driver).
- **Dropped Discord online-headcount tracking** from the social report —
  noise, not a real metric.

## [0.10.0] — 2026-08-27

The version actually running in production as of this writing. Stamped via
the welcome interview on 2026-08-27, as four agents:
`community-manager` (public identity "Hazel"), `community-secretary`
("Local"), `community-coding` ("Engineering"), `community-marketing`
("Marketing"). Never redeployed since — every fix and redesign in 0.12.0
above exists only in this repo until tomorrow's (2026-09-22) rebuild.
