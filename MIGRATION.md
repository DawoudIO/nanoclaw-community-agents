# Migration: existing NanoClaw install → sandboxed rebuild

Step-by-step for replacing a live NanoClaw deployment with this template set
running in a Docker Sandbox (`sbx`) micro-VM. Written for the ChurchCRM
deployment (appendix has its concrete values) but generic in structure.

**Stance on OneCLI and credentials — keep, don't churn:**

- **The old OneCLI stays running and untouched.** Its vault (Gmail OAuth, GA4,
  Twitter, PostHog, the old GitHub token) and its gateway request logs are
  both live infrastructure for the old system until cutover *and* forensic
  evidence. Nothing in it gets deleted.
- **The sandbox brings its own OneCLI** (dashboard + gateway + Postgres inside
  the micro-VM) with a fresh, empty vault. That separation is the isolation
  working — do not wire the sandbox to the old OneCLI; the old vault holds
  exactly the trust domain you're migrating away from.
- **Rotate only what needs rotating:** the GitHub bot token (provenance doubt
  + moving to a 3-token least-privilege split anyway) and the Discord bot
  (fresh application, so old and new systems never fight over one bot).
  Gmail/GA4/Twitter/PostHog: no evidence of compromise, not needed day-1,
  reconnect into the new vault later only if/when their optional tasks are
  enabled.

---

## Driving this with Claude Code (recommended) vs. by hand

This runbook is written to be executed by a Claude Code session: open one **on
the machine that will host the sandbox** (it also needs access to the old
install for Phase 0), point it at this file, and let it run the mechanical
steps while you handle the human-only ones. Two Claude surfaces are involved:

- **Host-side Claude Code** — runs Phases 0, 1, 3, 4: snapshots, evidence tar,
  `docker pull`, template tar-stream, `sbx exec` stamping/wiring, gate test
  runs, resume sequence, old-host shutdown.
- **In-sandbox Claude** (`sbx exec -it -w /home/agent/nanoclaw nanoclaw
  claude`) — the kit's own customization path: `/add-discord`, wiring, and any
  in-VM debugging.

**Human-only steps — never delegate these** (they involve credentials or
browser auth, which agents must not handle): creating the 3 GitHub PATs;
creating + inviting the Discord bot; pasting keys into the OneCLI dashboard
(browser, via the published 10254 port); approving the kit's first-boot image
pulls; answering the lead's welcome interview; revoking the old tokens at
cutover. Also keep the `sbx run` terminal yours — it's interactive on first
boot and the session *is* the system.

Note the break-glass doctrine below applies to **operations after go-live** —
during setup, CLI-driving is the intended path, not an exception.

## Phase 0 — while the old system still runs (~30 min)

1. **Create the new credentials** (old ones stay valid until cutover):
   - Three new GitHub PATs on the bot account, per the scope table in the
     root README (lead: issues write; coding: read + `security_events`;
     marketing: fine-grained, content repo only).
   - A fresh Discord bot application (Developer Portal → New Application →
     Bot). Don't reuse the old bot.
2. **Preserve evidence from the host:**
   ```bash
   cd <old-nanoclaw>/groups/<lead-folder>
   git checkout -b quarantine/<date>-pre-rebuild && git add -A
   git commit -m "Quarantine snapshot before rebuild - working tree as found"
   git push origin quarantine/<date>-pre-rebuild
   ```
   ```bash
   tar -czf ~/nanoclaw-evidence-<date>.tgz <old-nanoclaw>/groups \
     <old-nanoclaw's DB/data dir> <old OneCLI's logs/data dir>
   ```
   The gateway request log is the piece that settles "which container made
   which API call" — make sure it's in the tar.
3. **Optional courtesy stand-down** to the old lead agent (informational,
   demands nothing): migration is planned host-level maintenance; hold
   everything; log-and-report only. Do not request evidence curation or an
   export list from it — the quarantine branch preserves everything, and
   curation happens later from the branch.

## Phase 1 — bring up the sandbox (~20 min + image pulls)

4. ```bash
   sbx run --name nanoclaw --kit "docker.io/sbx/nanoclaw-kit:latest" nanoclaw
   # (prebuilt image, no "alpha" tag string - see README step 1 for why,
   # and its honest limit: the underlying software has no non-alpha release
   # yet either way)
   ```
   Approve the image pulls, follow the setup wizard (Claude provider), and
   **record the printed port mappings** (OneCLI dashboard 10254, gateway
   10255, webhook 3000). Keep this terminal open — it is the system.
5. **Confirm you're actually sandboxed:**
   ```bash
   sbx policy ls nanoclaw --type network   # default-deny allowlist active
   docker ps                                # host daemon shows NO agent containers
   ```
   Agent containers exist only inside the VM's inner Docker daemon.
6. **Load the templates** (repo is private, so stream from a local clone):
   ```bash
   git clone https://github.com/DawoudIO/nanoclaw-community-agents.git /tmp/nca
   ```
   Optional: pre-stamp file fill-ins in `/tmp/nca` (the welcome interview
   covers them conversationally — the appendix is your answer sheet either
   way). **Cron/timezone edits are the only thing that must happen now.** Then:
   ```bash
   tar -C /tmp/nca -cf - support engineering marketing \
     | sbx exec -i nanoclaw tar -C /home/agent/nanoclaw/templates -xf -
   ```

## Phase 2 — stamp, wire, credentials (~30 min)

7. Stamp all three groups and wire the four agent-to-agent destinations
   (root README step 3). Check each create response's `templateReport`.
8. **New vault, minimal contents:** open the sandbox OneCLI dashboard via the
   published 10254 mapping. Add only: the three new GitHub PATs (host
   `api.github.com`) and, if using workspace backup, a `github.com` (git)
   entry. Set all three agents to `selective` secret mode and assign each its
   own token.
9. **Discord — and the owner DM comes absolutely first:**
   `sbx exec -it -w /home/agent/nanoclaw nanoclaw claude` → `/add-discord`
   with the **new** bot. The **first wiring is your own DM with the lead** —
   the control plane; nothing else proceeds until you've verified the round
   trip (you DM the lead, it replies; it proactively DMs you, you see it).
   Then DM the lead to trigger its `welcome` onboarding — first question will
   be the project's GitHub repo; MIGRATION's appendix is your answer sheet —
   and let it propose/confirm config conversationally. Only after that, wire
   the public channels + guild catch-all per the confirmed tiers — **with
   `--sender-scope all` on every public wiring** (the owner DM stays
   known-senders-only), so new community members never hit a per-sender
   approval prompt: the v1 install generated a steady stream of "new sender —
   allow?" asks for exactly this reason. Sub-agents get no channel wirings;
   the lead relays their config.

   From this point, **everything runs through Discord** — config, approvals,
   drift questions, reports. The sandbox's Claude CLI is break-glass admin
   only (see below).

## Phase 3 — configure and go live (~30 min)

10. After-stamping config: the two `config.env` files and the backup —
    **reusing `ChurchCRM/hazel-agent-backup` with a version split**: v1
    history is preserved on a `v1` branch, `main` restarts as the v2 backup
    target. From any machine with push access:
    ```bash
    git clone https://github.com/ChurchCRM/hazel-agent-backup.git /tmp/hab
    cd /tmp/hab
    git branch v1 && git push origin v1        # v1 history preserved (plus the quarantine branch from Phase 0)
    git checkout --orphan v2-root && git rm -rfq .
    printf '# Community agent workspace backup (v2)\n\nv1 history: branch `v1`. Quarantine snapshot: `quarantine/*`.\n' > README.md
    git add README.md && git commit -m "v2 root - workspace backup for the rebuilt agent system"
    git push -f origin HEAD:main               # main = clean v2 root; nothing lost, v1 branch keeps it all
    ```
    Then in the lead's group folder inside the sandbox: `git init`,
    `git remote add origin https://github.com/ChurchCRM/hazel-agent-backup.git`,
    identity + `.gitignore`, and let the backup task's first run push onto the
    new main.
11. Test every scripted gate before resuming anything:
    ```bash
    ./bin/ncl tasks list --status paused    # expect all 14
    ./bin/ncl tasks run <task-id> && ./bin/ncl tasks get <task-id>
    ```
    The `health-check` gate self-reports a missing `jq`/`ncl` (once, on its
    first run) and the integrity check falls back to a manual-pass wake —
    log an upstream issue if either fires (see UPSTREAM-ISSUES.md #7).
12. Resume in the README's safety order. Smoke tests: support-channel
    question → unprompted reply; dev-channel mention → tagged-only reply;
    DM the lead to ping both sub-agents and relay answers.

## Phase 4 — cutover (~10 min)

13. Stop the old NanoClaw host process (old OneCLI can keep running — its
    vault holds the not-rotated credentials for future reconnection, and
    nothing routes through it anymore).
14. **Revoke** the old GitHub bot token and delete the old Discord bot's
    token (or the application). This is the moment the old trust domain ends.
15. Verify in Discord: old bot offline, new bot answering. Verify on GitHub:
    a test action from the lead lands under the bot account via the new PAT.
16. While testing, log every platform quirk in UPSTREAM-ISSUES.md — confirm
    on this clean install, then file upstream.

---

## Break-glass admin: the Claude CLI — how it helps, how it hurts

`sbx exec -it -w /home/agent/nanoclaw nanoclaw claude` opens a Claude Code
session inside the sandbox with direct access to the install — files, `ncl`,
the group workspaces. Reserve it for a **bad state**: the owner DM broken, an
agent stuck in a verification deadlock, task/wiring surgery, log forensics.

**How it helps:**
- It operates on the *system* instead of negotiating with an *agent* — the
  decisive lesson from the old install's deadlock: when an agent can't verify
  you, stop arguing in-channel and act at the layer you control.
- It works when Discord doesn't: wiring repair, `/add-discord`, reading
  journals and task tables directly.
- It stays inside the sandbox boundary — same egress allowlist, no new trust
  domain, no credentials exposed (the vault still injects at the proxy).

**How it hurts:**
- Every CLI change is an out-of-framework edit — exactly what drift detection
  flags. Pair each intervention with a one-line DM to the lead afterward ("I
  changed X via CLI at Y"), or expect (and calmly answer) an ask-don't-lock
  question from the integrity gate.
- It bypasses every gate: no OneCLI request-holds, no single-voice review, no
  public-action ledger entry. Nothing stops a typo'd `ncl tasks` command or a
  bad file edit. Its power is unaudited unless you narrate it.
- Habit decay is the real risk: if routine config drifts into CLI edits, the
  owner DM stops being the single authoritative thread, config becomes
  untracked again, and you've rebuilt the old system's "who changed this?"
  ambiguity inside the new one. **Discord for operations, CLI for surgery.**
- A CLI session is itself an agent with tools — its conclusions deserve the
  same verify-don't-vibe discipline as anything else.

---

## Appendix — ChurchCRM deployment values (fill-ins)

| Where | Value |
|---|---|
| Lead persona **Your project** | ChurchCRM; repo map — product `ChurchCRM/CRM`, docs `ChurchCRM/docs.churchcrm.io`, site `ChurchCRM/ChurchCRM.io`, marketing `ChurchCRM/marketing`; docs site docs.churchcrm.io; English primary; ChurchCRM topics only. Keeping all four current is in scope |
| `channel-routing.md` support tier | #user-support, #general-support, #introductions, #showcase, #localization (+ guild catch-all) |
| `channel-routing.md` developer tier | #dev-chat, #security (never auto-reply), GitHub-bugs notification channel |
| `channel-routing.md` team-lead tier | #marketers, #announcements (post-only) |
| `escalation-paths.md` | Security → #security channel + owner DM, never public issues; maintainer = George |
| Coding persona / `config.env` | `COMMUNITY_REPOS="ChurchCRM/CRM ChurchCRM/docs.churchcrm.io ChurchCRM/ChurchCRM.io ChurchCRM/marketing"` — all four functions triaged, cross-repo currency rule applies; default branch master; label scheme: existing CRM labels only, milestones stay human |
| Marketing persona / `config.env` | `CONTENT_REPO="ChurchCRM/marketing"`; brand source = ChurchCRM/marketing repo (voice, pillars, personas); site repo ChurchCRM/ChurchCRM.io; GA4 property 253632751 (later, optional) |
| Backup target | New repo, e.g. `DawoudIO/community-agent-backup`; `ChurchCRM/hazel-agent-backup` frozen as evidence archive |
| Social platforms (snapshot + posting) | Track: x.com/getChurchCRM, facebook.com/getChurchCRM, instagram.com/getchurchcrm, linkedin.com/company/getchurchcrm, both YouTube channels. Post to: X + LinkedIn via intent-URL, Facebook manual (LinkedIn quirk: no URL in intent body — LinkedIn auto-adds the preview; owner switches to company page in the composer). Server invite for DM redirects: discord.gg/tuWyFzj3Nj. Add the platform hosts to the sandbox allowlist for the snapshot task |
| Discord invite for GitHub replies | discord.gg/tuWyFzj3Nj — same server invite, offered from GitHub issues when real-time chat would help |
| PostHog (when enabled) | Project id from the old install's config; host us.posthog.com; allowlist entry required |
| OneCLI dashboard address | George checks in remotely via Tailscale (old install ran at `http://100.68.197.18:10254`). On the new sandbox host, run `tailscale serve --tcp=10254 tcp://localhost:10254 --bg` once, then give the welcome interview `http://<new-host's-tailscale-ip>:10254` — never `127.0.0.1`. Confirm the fresh sbx install's OneCLI gateway version satisfies the `/v1` API check in `docs/onecli-upgrades.md` before relying on credential flows — the old install ran gateway v1.45.0, which predates OneCLI's v2.0.0 line |
| Discord bot token in OneCLI | Old vault's Custom tab shows it as a generic secret (host `discord.com`, `Authorization` header) alongside PostHog/LinkedIn/Twitter — that's normal, `/add-discord` manages it, not a manual step |
| `github_bot_username` | `churchcrm-hazel` — already a dedicated service account, not George's personal one (confirmed in the old install's own notes). Re-verify with the new `GET /user` identity check anyway; don't assume it carried over correctly |
| Docs style | Current-state only — never "added in X.x", "as of version", "what's new" or any version-history language in docs.churchcrm.io (George, confirmed v1) |
| Brand assets | Official logo only: churchcrm.io/media/logo-ChurchCRM-large.png (dark background — wrap in white container on light backgrounds) + the 512px icon mark. Never generate a placeholder logo |
| Support knowledge seeds | QueryView is deprecated — mention the deprecation + new direction (built-in dashboard reports / custom plugins) whenever QueryView issues arrive. 55 supported locales (list rebuildable from the repo) |
| Goals (welcome step 3) | All four: support yes; growth yes — users (church admins/pastors) first, contributors second; proactive detection yes (PostHog); security yes |
| Models ($20 plan) | Lead + marketing: Sonnet-class; coding: Haiku-class; no Opus on scheduled tasks. The old 4-agent setup (Sara era) hit plan limits — this config + script gates is the fix; tune by pausing tasks per the README's priority order, not by deleting agents |
| **The one export from the old system** | `churchcrm/metrics-history.json` (social follower counts over time — the only data that can't be rebuilt from the web). Convert to one-JSON-object-per-line and place the **durable copy in the lead's** `plugin-data/community-support/social-metrics-history.jsonl` (captured by the workspace backup); optionally seed marketing's working cache too. Everything else — memory, transcripts, notes — is deliberately NOT migrated: agents rebuild context from GitHub on cold start |
| Deferred (reconnect later if wanted) | Gmail inbox-check, GA4 report — creds stay in old OneCLI vault until then |
| X/Twitter posting | The old OAuth 1.0a free-tier path is dead (X discontinued the free API tier Feb 2026; new access is pay-per-use, ~$0.20 per link post). Default for the rebuild: **intent-URL flow** (free, zero keys — same as the LinkedIn flow, approver clicks Post). Opt into pay-per-use (~$6/mo at daily cadence) only if one-click posting matters |
| `posthog-weekly-review` | **Keep — proactive issue detection** ("find issues before users report them"). Enable when ready: PostHog key into the new vault + `us.posthog.com` added to the sandbox allowlist + `POSTHOG_PROJECT_ID` in config.env. The standalone CRM skill (per 2026-08-19, `.claude/commands/` in ChurchCRM/CRM) is complementary for on-demand deep dives — it still needs its own PostHog key |
| Deterministic GitHub→Discord notifications | Restore as GitHub Actions webhooks (they were deleted in CRM PR #9042 and moved into the agent — inverted; agent notifications silently die when token limits hit). The generic version of that same workflow now ships as `examples/github-discord-notify.yml` in this template set — same secrets (`DISCORD_BUGS_WEBHOOK`/`DISCORD_SECURITY_WEBHOOK`), reusable as-is. Since George already knows this history, no separate ask needed here — but the welcome interview still asks explicitly on any fresh (non-migration) install. Agent keeps judgment replies only |
| New: release announcements | `release-announcement-watch` (new lead task) posts stable ChurchCRM/CRM releases to `churchcrm-announcements` automatically — no CI needed for this one, framing/contributor-credit needs agent judgment even though the trigger is mechanical |
