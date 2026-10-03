#!/usr/bin/env bash
# Clone both repos on the VM and hand off to NanoClaw's installer.
# Usage: ./deploy.sh <public-ip>
# Optional env: SSH_KEY (default ~/.ssh/id_ed25519), SSH_USER (default ubuntu),
#               NANOCLAW_GIT_URL, AGENTS_GIT_URL.
#
# nanoclaw.sh is interactive. This script allocates a TTY and execs it after
# the template copy. It does not install Node, pnpm, or Docker, and it does
# not write a systemd unit or a compose file.
set -euo pipefail

HOST="${1:?usage: ./deploy.sh <public-ip>}"
SSH_USER="${SSH_USER:-ubuntu}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_ed25519}"
NANOCLAW_GIT_URL="${NANOCLAW_GIT_URL:-https://github.com/DawoudIO/nanoclaw.git}"
AGENTS_GIT_URL="${AGENTS_GIT_URL:-https://github.com/DawoudIO/nanoclaw-community-agents.git}"

ssh -tt -i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${HOST}" \
  bash -s -- "${NANOCLAW_GIT_URL}" "${AGENTS_GIT_URL}" <<'REMOTE'
set -euo pipefail
NANOCLAW_GIT_URL="$1"
AGENTS_GIT_URL="$2"
cd "$HOME"

cloud-init status --wait

if [[ ! -d nanoclaw/.git ]]; then
  git clone "${NANOCLAW_GIT_URL}" nanoclaw
else
  git -C nanoclaw pull --ff-only
fi
if [[ ! -d nanoclaw-community-agents/.git ]]; then
  git clone "${AGENTS_GIT_URL}" nanoclaw-community-agents
else
  git -C nanoclaw-community-agents pull --ff-only
fi

bash "$HOME/nanoclaw-community-agents/scripts/install-templates.sh" "$HOME/nanoclaw"
cd "$HOME/nanoclaw"
exec bash ./nanoclaw.sh --template-path opensource/community-manager
REMOTE
