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
   sbx run --name nanoclaw --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=nanoclaw" nanoclaw
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
   Do the **before-stamping fill-ins now** in `/tmp/nca` (see appendix), then:
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
9. **Discord:** `sbx exec -it -w /home/agent/nanoclaw nanoclaw claude` →
   `/add-discord` with the **new** bot; invite it to the server; wire the
   **lead only** to every public channel + guild catch-all, per the tiers in
   `channel-routing.md`. Sub-agents get no channel wirings.

## Phase 3 — configure and go live (~30 min)

10. After-stamping config: the two `config.env` files and (optional) backup
    `git init/remote` — **point backup at a NEW repo**; the old backup repo
    becomes the frozen evidence archive, not a live target.
11. Test every scripted gate before resuming anything:
    ```bash
    ./bin/ncl tasks list --status paused    # expect all 12
    ./bin/ncl tasks run <task-id> && ./bin/ncl tasks get <task-id>
    ```
    First run of `health-check` also confirms `jq`/`ncl` exist in the image —
    log an upstream issue if not (see UPSTREAM-ISSUES.md #7).
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

## Appendix — ChurchCRM deployment values (fill-ins)

| Where | Value |
|---|---|
| Lead persona **Your project** | ChurchCRM; repos `ChurchCRM/CRM`, `ChurchCRM/docs.churchcrm.io`; docs site docs.churchcrm.io; English primary; ChurchCRM topics only |
| `channel-routing.md` support tier | #user-support, #general-support, #introductions, #showcase, #localization (+ guild catch-all) |
| `channel-routing.md` developer tier | #dev-chat, #security (never auto-reply), GitHub-bugs notification channel |
| `channel-routing.md` team-lead tier | #marketers, #announcements (post-only) |
| `escalation-paths.md` | Security → #security channel + owner DM, never public issues; maintainer = George |
| Coding persona / `config.env` | `COMMUNITY_REPOS="ChurchCRM/CRM"` (add docs repo if triaging it); default branch master |
| Marketing persona / `config.env` | `CONTENT_REPO="ChurchCRM/marketing"`; brand source = ChurchCRM/marketing repo (voice, pillars, personas); site repo ChurchCRM/ChurchCRM.io; GA4 property 253632751 (later, optional) |
| Backup target | New repo, e.g. `DawoudIO/community-agent-backup`; `ChurchCRM/hazel-agent-backup` frozen as evidence archive |
| Deferred (reconnect later if wanted) | Gmail inbox-check, GA4 report, PostHog review — creds stay in old OneCLI vault until then |
