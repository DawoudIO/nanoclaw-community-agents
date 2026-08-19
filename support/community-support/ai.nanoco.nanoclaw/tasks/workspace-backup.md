---
schedule: "40 8 * * *"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, git. Push auth is injected by the OneCLI proxy — the vault
  # needs a GitHub secret matched to host `github.com` (git), not only
  # `api.github.com` (REST). See README → Credentials.
  cd /workspace/agent
  if [ ! -d .git ] || ! git remote get-url origin >/dev/null 2>&1; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "git init + remote + identity required — see README, Workspace backup setup"}}'
    exit 0
  fi
  git add -A
  if git diff --cached --quiet; then
    echo '{"wakeAgent": false, "data": {"status": "nothing-to-commit"}}'
    exit 0
  fi
  if git commit -m "Automated workspace backup $(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null && git push >/dev/null 2>&1; then
    echo '{"wakeAgent": false, "data": {"status": "committed", "sha": "'"$(git rev-parse HEAD)"'"}}'
  else
    echo '{"wakeAgent": true, "data": {"status": "failed"}}'
  fi
---
Only invoked when the backup script itself failed (commit or push error) — a
clean or not-yet-configured backup never wakes you. Report the failure to the
owner in one line and say the next scheduled run will retry; don't attempt to
fix git state yourself (no force-push, no reset) without being asked.
