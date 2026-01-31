#!/bin/bash
set -e

# Configure npm to use persistent disk
export NPM_CONFIG_PREFIX=/data/.npm-global
export PATH="/data/.npm-global/bin:$PATH"

# Create directories if needed (first deploy)
mkdir -p /data/.npm-global
mkdir -p /data/.claude-config

# Always update Claude Code to latest on deploy
echo "Installing/updating Claude Code..."
npm install -g @anthropic-ai/claude-code@latest

# Execute the main command
exec "$@"
