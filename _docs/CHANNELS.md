# Messaging Channels

OpenClaw uses a plugin-based architecture for messaging channels, providing a unified interface for Telegram, Discord, Slack, Signal, iMessage, WhatsApp, and extensible plugin channels.

## Channel Plugin Architecture

Each channel implements a `ChannelPlugin` interface with specialized adapters:

```typescript
interface ChannelPlugin<Account> {
  id: string;
  meta: ChannelMeta;
  capabilities: ChannelCapabilities;

  // Adapters
  config: ChannelConfigAdapter<Account>;
  outbound: ChannelOutboundAdapter<Account>;
  security: ChannelSecurityAdapter<Account>;
  gateway: ChannelGatewayAdapter<Account>;
  messaging: ChannelMessagingAdapter<Account>;
  directory: ChannelDirectoryAdapter<Account>;
  threading?: ChannelThreadingAdapter<Account>;
  actions?: ChannelActionsAdapter<Account>;
  heartbeat?: ChannelHeartbeatAdapter<Account>;
  streaming?: ChannelStreamingAdapter<Account>;
  pairing?: ChannelPairingAdapter<Account>;
}
```

## Built-in Channels

| Channel | Location | Library |
|---------|----------|---------|
| Telegram | `src/telegram/` | grammY |
| WhatsApp | `src/whatsapp/` | Baileys |
| Discord | `src/discord/` | discord.js |
| Slack | `src/slack/` | Slack Bolt |
| Signal | `src/signal/` | signal-cli REST |
| iMessage | `src/imessage/` | iMessage bridge |
| WebChat | `src/web/` | Browser interface |

Channel order (priority): telegram, whatsapp, discord, googlechat, slack, signal, imessage

## Extension Channels

Located in `extensions/`:

| Extension | Protocol |
|-----------|----------|
| msteams | Microsoft Teams |
| matrix | Matrix protocol |
| mattermost | Mattermost |
| googlechat | Google Chat |
| line | LINE |
| zalo | Zalo |
| voice-call | Voice calls |
| bluebubbles | iMessage (BlueBubbles) |
| tlon | Tlon/Urbit |
| nostr | Nostr protocol |
| twitch | Twitch chat |

## Key Files

| File | Purpose |
|------|---------|
| `src/channels/registry.ts` | Channel order and registration |
| `src/channels/plugins/types.plugin.ts` | ChannelPlugin interface |
| `src/channels/plugins/adapter.*.ts` | Adapter type definitions |
| `src/routing/resolve-route.ts` | Agent routing |
| `src/infra/outbound/deliver.ts` | Message delivery |

## Channel Adapters

### Config Adapter

Account management:

```typescript
interface ChannelConfigAdapter<Account> {
  listAccountIds(cfg): string[];
  resolveAccount(cfg, accountId): Account;
  defaultAccountId(cfg): string | undefined;
  isConfigured(account): boolean;
  isEnabled(account, cfg): boolean;
  describeAccount(account): AccountSnapshot;
}
```

### Outbound Adapter

Message sending:

```typescript
interface ChannelOutboundAdapter<Account> {
  deliveryMode: "direct" | "gateway" | "hybrid";
  textChunkLimit: number;
  chunker?: TextChunker;

  sendPayload(ctx, payload): Promise<SendResult>;
  sendText(ctx, text, opts): Promise<SendResult>;
  sendMedia?(ctx, media, opts): Promise<SendResult>;
  sendPoll?(ctx, poll, opts): Promise<SendResult>;
}
```

### Security Adapter

Access control:

```typescript
interface ChannelSecurityAdapter<Account> {
  resolveDmPolicy(ctx): {
    policy: "pairing" | "allowlist" | "open" | "deny";
    allowFrom: string[];
    allowFromPath: string;
  };

  resolveGroupPolicy?(ctx): {
    policy: "open" | "allowlist" | "deny";
    allowFrom: string[];
  };

  collectWarnings(ctx): SecurityWarning[];
}
```

### Gateway Adapter

Lifecycle management:

```typescript
interface ChannelGatewayAdapter<Account> {
  startAccount(ctx): Promise<void>;
  stopAccount(ctx): Promise<void>;
  loginWithQrStart?(ctx): Promise<{ qrCode: string }>;
  loginWithQrWait?(ctx): Promise<LoginResult>;
  logoutAccount(ctx): Promise<void>;
}
```

### Messaging Adapter

Target resolution:

```typescript
interface ChannelMessagingAdapter<Account> {
  normalizeTarget(target): string;
  targetResolver: {
    looksLikeId(target): boolean;
    hint: string;  // e.g., "username or @username"
  };
}
```

### Directory Adapter

People and groups:

```typescript
interface ChannelDirectoryAdapter<Account> {
  self(): Promise<PeerInfo>;
  listPeers(): Promise<PeerInfo[]>;       // From config
  listPeersLive?(): Promise<PeerInfo[]>;  // From API
  listGroups(): Promise<GroupInfo[]>;
  listGroupsLive?(): Promise<GroupInfo[]>;
}
```

### Threading Adapter

Thread/reply handling:

```typescript
interface ChannelThreadingAdapter<Account> {
  getThreadId(ctx): string | undefined;
  buildReplyContext(ctx): ReplyContext;
}
```

### Actions Adapter

Reactions and message actions:

```typescript
interface ChannelActionsAdapter<Account> {
  listActions(): Action[];
  extractToolSend(ctx): ToolSendAction | undefined;
  handleAction(ctx, action): Promise<void>;
}
```

## Message Routing

### Route Resolution

```typescript
resolveAgentRoute({
  channel: "telegram",
  accountId: "bot-123",
  peer: "user:456",
  guild?: "guild:789",
  team?: "team:abc"
}): {
  agentId: string;
  sessionKey: string;
  binding: BindingDescription;
}
```

### Binding Priority

1. Peer binding (specific user/room)
2. Guild binding (Discord server)
3. Team binding (Slack workspace)
4. Account binding (specific credentials)
5. Channel binding (catch-all for channel)
6. Default agent (fallback)

### Session Key Format

```
agent:{agentId}:{scope}:{channel}
```

Scope options:
- `main` - Collapse all DMs
- `per-peer` - Per user
- `per-channel-peer` - Per channel + user
- `per-account-channel-peer` - Per account + channel + user

## Inbound Message Flow

```
Channel receives message (platform-specific event)
    |
    v
Channel Monitor parses to normalized MsgContext
    |
    v
Extract: from, to, text, media, thread, etc.
    |
    v
resolveAgentRoute() -> agentId + sessionKey
    |
    v
recordInboundSession() -> persist to ~/.openclaw/sessions/
    |
    v
dispatchInboundMessage() -> route to agent
```

### MsgContext

```typescript
interface MsgContext {
  from: string;           // Sender ID
  to: string;             // Recipient ID
  text: string;           // Message text
  channel: string;        // Channel ID
  accountId: string;      // Account ID
  threadId?: string;      // Thread/reply ID
  replyToId?: string;     // Reply target
  mediaPaths?: string[];  // Local media files
  mediaUrls?: string[];   // Remote media URLs
  mediaTypes?: string[];  // MIME types
}
```

## Outbound Message Delivery

```typescript
createChannelHandler({
  cfg,
  channel: "telegram",
  to: "user:123",
  accountId: "bot-456",
  replyToId?: "msg:789",
  threadId?: "thread:abc"
}): ChannelHandler;
```

### Delivery Flow

```
createChannelHandler()
    |
    v
Load adapter: loadChannelOutboundAdapter(channel)
    |
    v
Normalize target: adapter.messaging.normalizeTarget()
    |
    v
Chunk text (respect channel limits)
    |
    v
Send via: adapter.outbound.sendText/sendMedia/sendPayload
```

### Text Chunking

Channels have different limits:

| Channel | Limit | Notes |
|---------|-------|-------|
| Telegram | 4096 | Markdown supported |
| Discord | 2000 | Markdown supported |
| Slack | 40000 | Blocks preferred |
| WhatsApp | 65536 | Plain text only |
| Signal | 2000 | Plain text |
| iMessage | 20000 | Rich text |

## Security

### DM Policy

| Policy | Behavior |
|--------|----------|
| `pairing` | Unknown senders get pairing codes |
| `allowlist` | Only allowed senders can message |
| `open` | Anyone can message |
| `deny` | Block all DMs |

### Allowlist Configuration

```json5
{
  channels: {
    telegram: {
      accounts: {
        "bot-123": {
          allowFrom: ["user:456", "user:789"]
        }
      }
    }
  }
}
```

### Group/Channel Gating

```json5
{
  channels: {
    discord: {
      mentionRequired: true,  // Require bot mention
      guilds: {
        "guild:123": {
          allowFrom: ["channel:456"]
        }
      }
    }
  }
}
```

## Plugin Registration

Extensions register via `register(api: OpenClawPluginApi)`:

```typescript
// extensions/discord/src/index.ts

import { discordPlugin } from "./channel";

export function register(api: OpenClawPluginApi) {
  api.registerChannel({ plugin: discordPlugin });
}
```

### Plugin Structure

```typescript
// extensions/discord/src/channel.ts

export const discordPlugin: ChannelPlugin<ResolvedDiscordAccount> = {
  id: "discord",
  meta: {
    ...getChatChannelMeta("discord"),
    label: "Discord",
    docsPath: "/channels/discord"
  },
  capabilities: {
    chatTypes: ["direct", "channel", "thread"],
    polls: true,
    reactions: true,
    threads: true,
    media: true
  },
  config: { /* ... */ },
  outbound: { /* ... */ },
  security: { /* ... */ },
  gateway: { /* ... */ },
  messaging: { /* ... */ },
  directory: { /* ... */ },
  actions: { /* ... */ }
};
```

## Channel Status

```typescript
interface ChannelStatus {
  channel: string;
  accountId: string;
  state: "running" | "stopped" | "error";
  error?: string;
  lastActivity?: Date;
  self?: PeerInfo;
}
```

### Status Commands

```bash
# All channels
openclaw channels status

# With deep probe
openclaw status --deep

# Specific channel
openclaw channels status telegram
```

## Design Patterns

1. **Pluggable Architecture**: New channels added via extensions
2. **Multi-Account**: Each channel supports multiple credentials
3. **Agent Binding**: Route specific channels to specific agents
4. **Session Persistence**: Per-peer or per-channel session scopes
5. **Unified Interface**: Core reply/tool system agnostic to channel
6. **Gateway Abstraction**: Direct SDK, remote gateway, or hybrid
7. **Security Layered**: Per-channel DM policies, group allowlists
8. **Live & Static Modes**: Directory lookups with optional real-time API
