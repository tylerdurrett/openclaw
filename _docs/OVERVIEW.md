# OpenClaw Architecture Overview

OpenClaw is a personal AI assistant platform that bridges multiple messaging channels (WhatsApp, Telegram, Discord, Slack, iMessage, Signal, and more) with AI agent capabilities. It's built in TypeScript/ESM and totals approximately 292,000 lines of code.

## What Is OpenClaw?

OpenClaw is a **local-first AI gateway** that:
- Acts as a unified control plane for messaging channels and AI agents (powered by Pi agent framework)
- Runs a local Gateway that owns all channel connections and WebSocket control
- Connects messaging surfaces to coding agents with real-time tool execution
- Provides macOS/iOS/Android companion apps with voice wake, talk mode, and canvas support
- Delivers a browser-based Control UI for chat, config, sessions, nodes, and administration

## High-Level Architecture

```
Messaging Channels (WhatsApp/Telegram/Discord/Slack/Signal/iMessage + plugins)
           |
    +---------------------+
    |      Gateway        |  (WebSocket control plane on loopback 127.0.0.1:18789)
    |  (single source of  |
    |      truth)         |  Canvas HTTP server (port 18793)
    +---------+-----------+
              |-- Pi Agent (RPC mode with tool streaming)
              |-- CLI tools (send, agent, config, etc.)
              |-- Control UI (browser dashboard)
              |-- macOS app (menu bar + canvas + voice)
              |-- iOS nodes (pairing + canvas + voice)
              +-- Android nodes (pairing + canvas + voice)
```

## Core Systems

| System | Description | Documentation |
|--------|-------------|---------------|
| **CLI** | Command-line interface with 100+ commands | [CLI.md](CLI.md) |
| **Gateway** | WebSocket/HTTP control plane | [GATEWAY.md](GATEWAY.md) |
| **Channels** | Messaging channel abstractions | [CHANNELS.md](CHANNELS.md) |
| **Agents** | AI providers and agent execution | [AGENTS.md](AGENTS.md) |
| **Media** | Image/audio/video processing | [MEDIA.md](MEDIA.md) |
| **Plugins** | Extension system | [PLUGINS.md](PLUGINS.md) |
| **Config** | Configuration and validation | [CONFIG.md](CONFIG.md) |
| **Security** | Sandboxing and approvals | [SECURITY.md](SECURITY.md) |
| **Native Apps** | macOS, iOS, Android apps | [NATIVE_APPS.md](NATIVE_APPS.md) |

## Directory Structure

```
openclaw/
├── src/                    # Core TypeScript source (~292K LOC)
│   ├── cli/               # CLI wiring and command infrastructure
│   ├── commands/          # 100+ CLI subcommands
│   ├── gateway/           # WebSocket control plane
│   ├── agents/            # Agent configuration and execution
│   ├── providers/         # AI provider integrations
│   ├── channels/          # Shared channel abstractions
│   ├── routing/           # Multi-agent routing
│   ├── media/             # Media processing pipeline
│   ├── telegram/          # Telegram channel
│   ├── discord/           # Discord channel
│   ├── slack/             # Slack channel
│   ├── signal/            # Signal channel
│   ├── imessage/          # iMessage channel
│   ├── whatsapp/          # WhatsApp channel
│   ├── web/               # WebChat interface
│   ├── memory/            # Session memory/history
│   ├── browser/           # Playwright automation
│   ├── canvas-host/       # A2UI canvas rendering
│   ├── plugins/           # Plugin discovery and loading
│   ├── security/          # Sandboxing and approvals
│   ├── config/            # Configuration system
│   ├── infra/             # Infrastructure utilities
│   └── terminal/          # TUI rendering
├── extensions/            # Channel/feature plugins (31 plugins)
│   ├── discord/          # Discord extension
│   ├── telegram/         # Telegram extension
│   ├── msteams/          # Microsoft Teams
│   ├── matrix/           # Matrix protocol
│   ├── memory-lancedb/   # Vector memory backend
│   └── ...
├── apps/                  # Native applications
│   ├── macos/            # SwiftUI menu bar app
│   ├── ios/              # iOS app
│   ├── android/          # Android app
│   └── shared/           # OpenClawKit (shared Swift)
├── docs/                  # Mintlify documentation
├── scripts/               # Build and utility scripts
└── dist/                  # Built output
```

## Key Technologies

### Runtime & Build
- **Node.js 22+** with pnpm 10.23.0
- **Bun** for TypeScript execution (dev/tests)
- **TypeScript** with strict typing
- **Oxlint/Oxfmt** for linting/formatting
- **Vitest** for testing (70% coverage thresholds)

### Messaging & Networking
- **Baileys** for WhatsApp Web
- **grammY** for Telegram
- **discord.js** for Discord
- **Slack Bolt** for Slack
- **Express/Hono** for HTTP servers
- **WebSocket** for loopback-only control plane

### AI & Models
- **Pi Agent Core/AI/Coding** framework
- **Anthropic SDK** (Claude/Pro/Max)
- **OpenAI SDK**
- **AWS Bedrock**
- **Google Gemini**
- Multiple provider abstractions

### Data & Storage
- **SQLite** with sqlite-vec for embeddings
- **lancedb** for memory/search
- File-based session storage
- **JSON5** config format

### Media & Analysis
- **Sharp** for image processing
- **PDF.js** for PDF extraction
- **Playwright Core** for browser automation
- **node-edge-tts** for text-to-speech

### UI & Visualization
- **Lit** for web components
- **SwiftUI** for macOS/iOS
- **Clack prompts** for CLI prompts
- **A2UI** canvas framework

## Data Flow

### Inbound Message Flow

```
Channel (e.g., Telegram) receives message
    |
    v
Channel Monitor parses platform-specific event
    |
    v
Normalize to MsgContext (from, to, text, media, etc.)
    |
    v
resolveAgentRoute() determines agent + session
    |
    v
recordInboundSession() persists to ~/.openclaw/sessions/
    |
    v
dispatchInboundMessage() routes to agent
    |
    v
Agent processes with tools, generates response
    |
    v
Response sent back to channel
```

### Gateway Request Flow

```
Client connects via WebSocket
    |
    v
Authentication (token/password/Tailscale/device)
    |
    v
Client sends RequestFrame (method, params, id)
    |
    v
Authorization check (scopes: read/write/admin/approvals)
    |
    v
Handler lookup from registry
    |
    v
Execute handler (async with context)
    |
    v
ResponseFrame sent back
    |
    v
Optional: Broadcast events to other clients
```

## Configuration

OpenClaw is configured via `~/.openclaw/config.json5`:

```json5
{
  // Gateway settings
  gateway: {
    port: 18789,
    bind: "loopback",  // or "lan", "tailnet", "auto"
    auth: {
      mode: "token",
      token: "your-secret-token"
    }
  },

  // Model providers
  models: {
    providers: {
      anthropic: { apiKey: "ANTHROPIC_API_KEY" },
      openai: { apiKey: "OPENAI_API_KEY" }
    }
  },

  // Agent configuration
  agents: {
    defaults: {
      model: "anthropic/claude-sonnet-4-20250514"
    }
  },

  // Channel configuration
  channels: {
    telegram: { /* ... */ },
    discord: { /* ... */ }
  }
}
```

## Security Model

### Authentication Layers
1. **Gateway Token**: Required for non-loopback binds
2. **Device Tokens**: For paired mobile/desktop nodes
3. **Tailscale Identity**: For tailnet access
4. **Channel Allowlists**: Per-channel sender restrictions

### Authorization Scopes
- `operator.admin`: Full access
- `operator.read`: Health, status, models, sessions
- `operator.write`: Send, agent run, chat
- `operator.approvals`: Exec approval handling
- `operator.pairing`: Device pairing

### Tool Security
- Tool policies (allow/deny lists)
- Sandbox execution for shell commands
- Approval workflows for dangerous operations
- Subagent restrictions

## Development Workflow

```bash
# Install dependencies
pnpm install

# Run in development
pnpm gateway:watch          # Auto-reload on changes
pnpm ui:dev                 # Develop Control UI

# Type checking and build
pnpm build

# Testing
pnpm test                   # Run tests
pnpm test:coverage          # With coverage

# Linting and formatting
pnpm lint
pnpm format
```

## Version & Release

- **Version Format**: YYYY.M.D (date-based)
- **Release Channels**:
  - `stable`: Tagged releases (npm `latest`)
  - `beta`: Prerelease tags (npm `beta`)
  - `dev`: Moving head on `main` branch

## Related Documentation

- [The OpenClaw Story](NARRATIVE.md) — A narrative guide without code
- [CLI Architecture](CLI.md)
- [Gateway System](GATEWAY.md)
- [Messaging Channels](CHANNELS.md)
- [AI Agent System](AGENTS.md)
- [Media Pipeline](MEDIA.md)
- [Plugin System](PLUGINS.md)
- [Configuration System](CONFIG.md)
- [Security and Sandboxing](SECURITY.md)
- [Native Applications](NATIVE_APPS.md)
