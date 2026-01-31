#!/bin/bash
set -e

echo "[entrypoint] Starting..."
echo "[entrypoint] Current user: $(whoami) (uid=$(id -u))"
echo "[entrypoint] /data permissions: $(ls -la /data 2>&1 | head -5)"

# Configure npm to use persistent disk
export NPM_CONFIG_PREFIX=/data/.npm-global
export PATH="/data/.npm-global/bin:$PATH"

# Create directories if needed (first deploy)
echo "[entrypoint] Creating directories..."
mkdir -p /data/.npm-global
mkdir -p /data/.claude-config

# Always update Claude Code to latest on deploy
echo "[entrypoint] Installing/updating Claude Code..."
npm install -g @anthropic-ai/claude-code@latest

echo "[entrypoint] Claude Code installed at: $(which claude 2>&1 || echo 'not found')"

# Execute the main command
echo "[entrypoint] Starting main process..."
exec "$@"
