---
schedule: "43 8 * * *"
script: |
  #!/bin/bash
  set -euo pipefail
  # Deps: bash, git. Push auth is injected by the OneCLI proxy — the vault
  # needs a GitHub secret matched to host `github.com` (git), not only
  # `api.github.com` (REST). See this template's README, Credentials.
  cd /workspace/agent
  if [ ! -d .git ] || ! git remote get-url origin >/dev/null 2>&1; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "git init + remote required - see README, Workspace backup setup"}}'
    exit 0
  fi
  if ! git config user.email >/dev/null 2>&1; then
    echo '{"wakeAgent": false, "data": {"status": "not-configured", "hint": "git identity missing - set git config user.name and user.email, see README"}}'
    exit 0
  fi
  git add -A
  if ! git rev-parse -q --verify HEAD >/dev/null 2>&1 && git diff --cached --quiet; then
    echo '{"wakeAgent": false, "data": {"status": "empty-workspace-nothing-to-back-up"}}'
    exit 0
  fi
  if ! git diff --cached --quiet; then
    git commit -m "Automated workspace backup $(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null
  fi
  # Push everything unpushed — including commits stranded by an earlier failed
  # push (a commit-then-push-fail must NOT read as "nothing to commit" later).
  AHEAD=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "unknown")
  if [ "$AHEAD" = "0" ]; then
    echo '{"wakeAgent": false, "data": {"status": "up-to-date"}}'
  elif git push -u origin HEAD >/dev/null 2>&1; then
    echo '{"wakeAgent": false, "data": {"status": "pushed", "sha": "'"$(git rev-parse HEAD)"'"}}'
  else
    printf '{"wakeAgent": true, "data": {"status": "push-failed", "unpushed_commits": "%s"}}\n' "$AHEAD"
  fi
---
Only invoked when the push failed — a clean, up-to-date, or not-yet-configured
backup never wakes you. The commits are safe locally and this gate retries
them on every future run until the push lands (that retry claim is real: the
gate pushes anything unpushed, not just new changes). Report the failure to
your lead in one line — `github.com` vault entry and network policy are the
usual suspects — and don't attempt to fix git state yourself (no force-push,
no reset) without being asked.
