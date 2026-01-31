# Gateway System

The Gateway is the central multiplexed server that handles WebSocket/HTTP traffic, manages channel connections, routes messages, and serves the Control UI.

## Overview

The Gateway runs on a single port (default 18789) and provides:
- WebSocket control plane for CLI, mobile apps, and web clients
- HTTP endpoints for OpenAI-compatible APIs
- Channel management (start/stop/status)
- Config reload (hot and full restart)
- Discovery via mDNS/Bonjour
- Control UI browser dashboard

## Architecture

```
                    HTTP/WebSocket Server (port 18789)
                              |
        +---------------------+---------------------+
        |                     |                     |
   WebSocket              HTTP Routes           Control UI
   Protocol               /v1/chat/*              Browser
        |                 /v1/responses           Dashboard
        v                     |
   Request/Response           v
   + Broadcast            API Handlers
        |                     |
        v                     v
   Gateway Methods       OpenAI/Responses
   (70+ RPC methods)     Compatible APIs
```

## Key Files

| File | Purpose |
|------|---------|
| `src/gateway/server.impl.ts` | Server startup orchestration |
| `src/gateway/server-runtime-state.ts` | HTTP/WS server creation |
| `src/gateway/server-methods.ts` | Handler registry + authorization |
| `src/gateway/server/ws-connection.ts` | WebSocket connection lifecycle |
| `src/gateway/server-http.ts` | HTTP server + routing |
| `src/gateway/protocol/index.ts` | Frame definitions + validation |
| `src/gateway/config-reload.ts` | Hot reload system |
| `src/gateway/auth.ts` | Authentication logic |
| `src/cli/gateway-cli/run.ts` | CLI entry point |

## Server Initialization

```typescript
startGatewayServer(port, opts)
  |-- Load and validate config (with legacy migration)
  |-- Apply plugin auto-enable settings
  |-- Load gateway plugins and channel plugins
  |-- Resolve runtime configuration
  |-- Create runtime state (HTTP server, WebSocket server)
  |-- Start sidecars (browser control, Gmail watcher, plugins)
  |-- Start channel managers and discovery systems
  +-- Attach WebSocket handlers and HTTP routes
```

## HTTP Routes

| Route | Handler |
|-------|---------|
| `POST /v1/chat/completions` | OpenAI Chat API |
| `POST /v1/responses` | OpenResponses API |
| `/.openclaw/hooks/*` | Webhook handlers |
| `/.openclaw/` | Tools invoke endpoints |
| `/a2ui/` | Canvas Host file serving |
| `/integrations/slack/events` | Slack event handler |
| `/` | Control UI (browser) |
| WebSocket upgrade | Gateway protocol |

## WebSocket Protocol

### Connection Lifecycle

```
1. HTTP upgrade request arrives
2. Client sends `connect` frame with auth credentials
3. Server validates auth (token/password/Tailscale/device)
4. Server responds with `connect` response
5. Client sends RPC requests, receives responses
6. Server broadcasts events to subscribed clients
```

### Frame Types

```typescript
// Request from client
interface RequestFrame {
  type: "request";
  id: string;
  method: string;
  params: Record<string, unknown>;
}

// Response from server
interface ResponseFrame {
  type: "response";
  id: string;
  ok: boolean;
  payload?: unknown;
  error?: { code: string; message: string };
}

// Broadcast from server (no request)
interface BroadcastFrame {
  type: "broadcast";
  event: string;
  data: unknown;
}
```

## Authentication

### Auth Modes

| Mode | Description |
|------|-------------|
| `token` | Shared secret token |
| `password` | Shared password |
| `tailscale` | Tailscale identity headers |
| `device` | Device-specific token |

### Authorization Scopes

| Scope | Permissions |
|-------|-------------|
| `operator.admin` | Full access (config, skills, sessions, cron, wizard) |
| `operator.read` | Health, status, models, agents, sessions preview |
| `operator.write` | Send, agent run, wake, chat, browser, talk mode |
| `operator.approvals` | Exec approval request/resolve |
| `operator.pairing` | Node and device pairing |

### Auth Hierarchy

```
WebSocket Connect
  |-- Token auth: compare provided token
  |-- Password auth: compare provided password
  |-- Tailscale: verify Tailscale identity headers
  |-- Device token: validate device-specific token
  +-- Local detection: loopback IP auto-permits
```

## Gateway Methods

70+ RPC methods organized by domain:

### Connection & Health
- `health` - System health check
- `system-presence` - Presence update
- `system-event` - System event handling

### Chat & Agent
- `chat.send` - Send chat message
- `chat.history` - Get chat history
- `chat.abort` - Cancel running chat
- `agent` - Run agent turn
- `agent.wait` - Wait for agent completion
- `agents.list` - List configured agents

### Messaging
- `send` - Route message to channels
- `channels.status` - Channel status
- `channels.logout` - Logout channel

### Configuration
- `config.get` - Get config value
- `config.set` - Set config value
- `config.patch` - Patch config
- `config.schema` - Get config schema

### Sessions
- `sessions.list` - List sessions
- `sessions.patch` - Update session
- `sessions.reset` - Reset session
- `sessions.delete` - Delete session

### Nodes & Devices
- `node.list` - List connected nodes
- `node.invoke` - Invoke node action
- `node.pair.*` - Pairing workflow
- `node.describe` - Describe node capabilities

### Skills & Cron
- `skills.status` - Skills status
- `skills.bins` - Binary skills
- `skills.install` - Install skill
- `cron.list` - List cron jobs
- `cron.add` - Add cron job
- `cron.run` - Run cron job

### Other
- `tts.convert` - Text-to-speech
- `browser.request` - Browser automation
- `update.run` - Run CLI update
- `logs.tail` - Tail gateway logs

## Configuration

### Gateway Config

```typescript
interface GatewayConfig {
  port: number;              // Default: 18789
  bind: "loopback" | "lan" | "tailnet" | "auto" | string;

  auth: {
    mode: "token" | "password";
    token?: string;
    password?: string;
    allowTailscale?: boolean;
  };

  controlUi?: {
    enabled: boolean;
    basePath?: string;
  };

  tailscale?: {
    mode: "off" | "serve" | "funnel";
    resetOnExit?: boolean;
  };

  tls?: {
    enabled: boolean;
    autoGenerate?: boolean;
    certPath?: string;
    keyPath?: string;
  };

  http?: {
    chatCompletions?: boolean;
    openResponses?: { enabled: boolean; files?: FileConfig };
  };

  reload?: {
    mode: "off" | "restart" | "hot" | "hybrid";
    debounce?: number;
  };
}
```

### Bind Modes

| Mode | Description |
|------|-------------|
| `loopback` | 127.0.0.1 only (most secure) |
| `lan` | 0.0.0.0 (all interfaces) |
| `tailnet` | Tailscale IP only |
| `auto` | Tailnet if available, else loopback |
| `custom` | Specific IP address |

## Config Reload

### Reload Modes

| Mode | Behavior |
|------|----------|
| `off` | No reloading on config changes |
| `restart` | Full gateway restart |
| `hot` | Apply changes without restart (selective) |
| `hybrid` | Prefer hot, fall back to restart |

### Hot Reload Rules

```
hooks config      -> hot reload hooks
cron              -> hot restart cron service
browser           -> hot restart browser control
heartbeat         -> hot restart heartbeat runner
channels          -> hot restart specific channel
plugins           -> full restart
gateway, discovery -> full restart
agents, routing    -> no reload needed
```

## Channel Management

```typescript
// Start channels on gateway boot
await startChannels();

// Start specific channel account
await startChannel("telegram", "bot-123");

// Stop channel account
await stopChannel("discord", "bot-456");

// Channel lifecycle
interface ChannelManager {
  startAccount(ctx: ChannelContext): Promise<void>;
  stopAccount(ctx: ChannelContext): Promise<void>;
  loginWithQrStart?(ctx): Promise<{ qrCode: string }>;
  logoutAccount(ctx: ChannelContext): Promise<void>;
}
```

## Discovery

### mDNS/Bonjour

The gateway advertises itself via mDNS:
- Instance name from display name
- TXT records: API version, port, bind address
- Optional: CLI path, SSH port

### Tailscale

```typescript
interface TailscaleConfig {
  mode: "off" | "serve" | "funnel";
  resetOnExit?: boolean;
}
```

- **serve**: Gateway accessible via tailnet hostname
- **funnel**: Publicly accessible via Tailscale funnel

## Chat & Streaming

### Chat Run Registry

```typescript
interface ChatRunRegistry {
  pending: Map<sessionKey, ChatRun[]>;
  running: Map<sessionKey, ChatRun>;
  abortControllers: Map<runId, AbortController>;
}
```

### Streaming Flow

```
Client sends chat.send
  |-- Queue in pending (if another run active)
  |-- Start run when ready
  |-- Buffer deltas (threshold-based)
  |-- Stream to client when buffer exceeds threshold
  |-- Final message on completion
  +-- Broadcast to other subscribed clients
```

## Broadcasting

Events broadcast to subscribed clients:

```typescript
interface BroadcastEvent {
  event: string;
  data: unknown;
  dropIfSlow?: boolean;  // Non-critical events
}

// Examples
broadcast({ event: "channel.status", data: status });
broadcast({ event: "chat.delta", data: delta });
broadcast({ event: "presence.update", data: presence });
```

## CLI Commands

```bash
# Start gateway
openclaw gateway run

# With options
openclaw gateway run --port 18789 --bind loopback

# Stop gateway
openclaw gateway stop

# Check status
openclaw gateway status

# Gateway logs
openclaw logs tail

# Discovery
openclaw gateway discover
```

## Design Patterns

1. **Multiplexed Server**: Single HTTP/WS port handles all traffic
2. **Request Handler Registry**: Methods registered by name, dispatched dynamically
3. **Broadcast Channel**: Server -> Client async events
4. **Plugin Extensibility**: Channels, hooks, HTTP handlers from plugins
5. **Scope-Based Authorization**: Methods gated by scopes
6. **Hot Reload**: Config changes trigger selective reload
7. **Session Key Routing**: Messages routed by channel + peer + agent binding
8. **Graceful Shutdown**: SIGTERM -> close connections -> exit
9. **Chat Streaming**: Buffered deltas sent incrementally
10. **TLS & Multi-Auth**: Multiple auth methods supported
