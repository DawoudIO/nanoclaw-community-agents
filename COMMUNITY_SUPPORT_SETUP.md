# ChurchCRM Community Support Setup — Native Installation

**Date**: 2026-08-22  
**Status**: Working native Mac installation (no sbx/Docker required)  
**Process**: Tested and documented

---

## Quick Start

**Prerequisites**:
- Node.js 18+
- **Ollama running on `http://localhost:11434`** with `llama3.2` model pulled (for local agent)
  - **Check if Ollama is running**: `curl http://localhost:11434` should return status 200
  - **Check if llama3.2 is pulled**: `ollama list` should show `llama3.2` in the output
  - **If not pulled yet**: `ollama pull llama3.2` (takes 5–10 min depending on network speed)
  - **Critical**: Local agent will crash-loop if llama3.2 is not available — always verify this before setup
- GitHub bot account (dedicated, not personal)
- Discord bot token
- OneCLI vault for credentials

**Install**:

```bash
# Clone nanoclaw
cd /Users/gdawoud/Development
git clone https://github.com/nanocoai/nanoclaw.git nanoclaw-v2
cd nanoclaw-v2

# Copy the ChurchCRM templates (support, local, engineering, marketing)
cp -r /Users/gdawoud/Development/nanoclaw-community-agents/{support,local,engineering,marketing} templates/

# Start the setup wizard
bash nanoclaw.sh
```

**Then**:
1. Select `support/community-support` template
2. Choose `local` for build method
3. Run the welcome interview (one question at a time)
4. Agent will stamp sub-agents and wire Discord channels autonomously

---

## Why Native, Not sbx?

**sbx (Docker Sandboxes)** had incompatibility issues with prebuilt `sbx/nanoclaw-kit`:
- `spec.yaml` format incompatible with current sbx versions
- Docker storage errors on image unpack
- Workaround (local installation) is faster to develop and test

**Decision**: Use native Mac installation for now. Once system is stable and tested, we can package it as a custom sbx kit if needed.

---

## Process Overview

### Phase 1: Copy Templates (Updated)

The `nanoclaw-community-agents` repo has the improved templates with:
- ✅ Step-by-step conversational onboarding (ask one question at a time)
- ✅ Agent autonomy to stamp sub-agents (local, engineering, marketing)
- ✅ Agent autonomy to wire Discord channels

Copy them to `nanoclaw-v2/templates/` before stamping:

```bash
cp -r nanoclaw-community-agents/{support,local,engineering,marketing} nanoclaw-v2/templates/
```

### Phase 2: Stamp the Lead Agent

```bash
cd nanoclaw-v2
bash nanoclaw.sh
```

Choose: `support/community-support` template, build locally.

This creates the lead agent in the default group.

### Phase 3: Welcome Interview

The lead agent will DM you (the owner) with the welcome interview:

1. **GitHub repo** — What's the main product repo?
2. **Repo map** — Which repos exist (docs, site, marketing, wiki)?
3. **Goals** — Which of 4 goals are active? (support, growth, issue detection, security)
4. **Timezone** — What timezone do you work in?
5. **Channel routing** — Which channels map to support/dev/security tiers?
6. **Contacts** — Security contact + human backstop
7. **OneCLI dashboard** — URL for credential setup
8. **Bot account** — GitHub bot username
9. **Credentials** — Register GitHub PATs, Discord token, analytics keys (GA4, PostHog)
10. **Sub-agents** — **(Automatic)** Agent stamps local/engineering/marketing if those goals are active
11. **Discord wiring** — **(Automatic)** Agent wires channels to support/dev/security tiers
12. **Workspace backup** — Agent sets up daily backup repo if requested
13. **Go-live** — Review what's configured, activate ready tasks

**Key improvement**: Each question comes one at a time. You answer, confirm understanding, move to next. No interrogation, easy to correct.

### Phase 4: Sub-Agents Stamp Themselves

**Agent autonomy**: The lead agent no longer asks permission to stamp sub-agents. Based on the goals you chose:

- **Local agent** stamps if any goal chosen (metrics, mirrors, backups, holding acks)
- **Engineering agent** stamps if support/detection/security goals chosen (triage, security advisory)
- **Marketing agent** stamps if growth goal chosen (content drafts)

Each agent:
1. Receives config from lead agent
2. Writes `config.env` + `project-config.md` in its own workspace
3. Confirms to lead agent it's ready
4. Reports back to owner via lead

### Phase 5: Discord Channels Wire Automatically

**Agent autonomy**: The lead agent wires Discord channels directly based on channel IDs you provided during onboarding.

Routing:
- **Support tier** (auto-reply): support-chat, support-questions, support-install, support-localization
- **Developer tier** (mention-only): dev-chat, dev-plugins, dev-bugs
- **Security tier** (mention-only): security
- **General/Announcements**: announcements, general

Lead agent tests each route and reports status.

### Phase 6: Tasks Activate

Once config + credentials verified:

- **Always on** (regardless of goals): `unanswered-watch`, `github-first-response`, `owner-tldr`, `health-check`, `workspace-backup`, `weekly-identity-integrity-check`
- **If support chosen**: `daily-github-triage`, `docs-gap-review`, `release-announcement-watch`
- **If growth chosen**: `content-draft-cycle`, `weekly-analytics-report`, `dev-metrics-report`, `good-first-issue-health`
- **If detection chosen**: `posthog-weekly-review`, `repo-mirror-sync`
- **If security chosen**: `security-advisory-sweep`

---

## Configuration Files

After setup, the agent creates:

**Lead agent workspace** (`groups/community-support/`):
- `plugin-data/community-support/config.env` — shell vars (COMMUNITY_REPOS, GITHUB_BOT_USERNAME)
- `plugin-data/community-support/project-config.md` — prose config (owner DM, repo map, channels, goals, analytics, tone, target audience)
- `plugin-data/community-support/public-actions.log` — ledger of public replies/comments
- `plugin-data/community-support/social-metrics-history.jsonl` — weekly follower counts
- `plugin-data/community-support/owner-instructions.jsonl` — owner DM ledger (ack #N tracking)

**Sub-agent workspaces** (same structure, separate directories):
- `plugin-data/community-local/config.env` + `project-config.md`
- `plugin-data/community-coding/config.env` + `project-config.md`
- `plugin-data/community-marketing/config.env` + `project-config.md`

---

## What's Different From Previous Attempts

| Aspect | Before | Now |
|--------|--------|-----|
| Installation | sbx + prebuilt kit (compatibility issues) | Native Mac (proven working) |
| Onboarding | All questions at once (overwhelming) | One question at a time (conversational) |
| Sub-agents | Manual stamping + DM back-and-forth | Automatic, based on goals chosen |
| Discord wiring | Manual config + testing | Automatic, tested by agent |
| Agent autonomy | Limited; agent asked permission | Full autonomy for routine automation |

---

## Testing Checklist

After setup, verify:

- [ ] Lead agent responds in owner DM
- [ ] Sub-agents stamped (if their goals active)
- [ ] Discord channels receive test messages
- [ ] `daily-github-triage` fires on schedule
- [ ] `owner-tldr` digest lands at 07:00 in owner's timezone
- [ ] First support question gets acknowledgment within `ACK_GRACE_MINUTES`
- [ ] Workspace backup runs daily

---

## Known Issues & Workarounds

**No sbx compatibility issues** — Native installation avoids them entirely.

**Credentials must be in OneCLI vault** — Never paste raw keys in chat or files. Use the OneCLI dashboard (`http://100.68.197.18:10254/` or Tailscale private IP) to register all tokens/keys.

---

## Next Steps

1. ✅ Copy templates to `nanoclaw-v2/templates/`
2. ⏳ Stamp the lead agent (`bash nanoclaw.sh`)
3. ⏳ Go through owner interview in DM (step-by-step flow)
4. ⏳ Verify sub-agents stamped and Discord wired
5. ⏳ Run for 24 hours, monitor logs for errors
6. ⏳ (Later) Create custom sbx kit if needed

---

## Troubleshooting

### Local Ops Agent Crash-Loop (exitCode=1)

**Symptom**: The Community Local Ops agent spawns but exits immediately within 1 second, then retries every ~60 seconds:
```
13:58:53 Spawning session → 13:58:54 Session ended, exitCode=1
13:59:54 Spawning session → 13:59:55 Session ended, exitCode=1
```

**Root Cause**: Ollama is running, but the required `llama3.2` model is not pulled. The agent config expects `llama3.2` and fails instantly if it's not available.

**Fix**:
```bash
# Check what models are installed
ollama list

# If llama3.2 is missing, pull it
ollama pull llama3.2

# Verify it's installed
ollama list | grep llama3.2
```

Once `llama3.2` is pulled, the Local Ops agent will start successfully and the crash-loop stops.

**Prevention**: Always run `ollama list` before setup to confirm `llama3.2` is available. The Prerequisites section lists this as critical.

---

## FAQ

**Q: Do I need sbx/Docker?**  
A: Not for this installation. Native Mac works. If you later want to containerize for deployment, we can create a custom sbx kit after testing.

**Q: Can I add more goals later?**  
A: Yes. DM the agent "add growth goal" and it re-runs just that part of the interview, stamps marketing if it wasn't already, etc.

**Q: What if a sub-agent fails to stamp?**  
A: Agent will report the error to owner DM. Check the specific agent's logs and re-run stamping for that agent only.

**Q: How do I update the templates?**  
A: Pull the latest from `nanoclaw-community-agents`, copy to `nanoclaw-v2/templates/`, then the agent picks up changes on next interaction (no restart needed unless code changed).

---

**Last updated**: 2026-08-22  
**Tested on**: Mac (native, no sbx)  
**Ready for**: Fresh ChurchCRM community support agent installation
