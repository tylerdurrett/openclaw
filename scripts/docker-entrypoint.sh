#!/bin/bash
# Disable strict modes that could cause script to exit on installer warnings
set +e
set +o pipefail

echo "[entrypoint] Starting..."
echo "[entrypoint] Current user: $(whoami) (uid=$(id -u))"

# Create persistent directories
mkdir -p /data/.local/bin
mkdir -p /data/.claude-config

# Symlink ~/.local to persistent disk so installer writes there
if [ ! -L "$HOME/.local" ]; then
  rm -rf "$HOME/.local" 2>/dev/null || true
  ln -sf /data/.local "$HOME/.local"
  echo "[entrypoint] Symlinked ~/.local -> /data/.local"
fi

export PATH="/data/.local/bin:$PATH"

# Install Claude Code if not present
if [ ! -f /data/.local/bin/claude ]; then
  echo "[entrypoint] Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
  echo "[entrypoint] Install completed (exit code ignored)"
else
  echo "[entrypoint] Claude Code already installed"
fi

echo "[entrypoint] Claude Code at: $(which claude 2>&1 || echo 'not found')"

# Execute the main command
echo "[entrypoint] Starting main process..."
exec "$@"
