#!/bin/bash
set -e

echo "[entrypoint] Starting..."
echo "[entrypoint] Current user: $(whoami) (uid=$(id -u))"
echo "[entrypoint] /data permissions: $(ls -la /data 2>&1 | head -5)"

# Create directories if needed (first deploy)
echo "[entrypoint] Creating directories..."
mkdir -p /data/.claude-code
mkdir -p /data/.claude-config

# Set Claude Code install location
export CLAUDE_INSTALL_DIR=/data/.claude-code
export PATH="/data/.claude-code/bin:$PATH"

# Install/update Claude Code using official installer
if [ ! -f /data/.claude-code/bin/claude ]; then
  echo "[entrypoint] Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash 2>&1 || {
    echo "[entrypoint] Claude Code install failed, continuing anyway..."
  }
else
  echo "[entrypoint] Claude Code already installed, skipping..."
fi

echo "[entrypoint] Claude Code at: $(which claude 2>&1 || echo 'not found')"

# Execute the main command
echo "[entrypoint] Starting main process..."
exec "$@"
