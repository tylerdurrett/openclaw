# Plugin System

OpenClaw uses a plugin architecture for extensibility, allowing channels, tools, and functionality to be added via extension packages.

## Overview

Plugins are TypeScript/ESM packages that:
- Register new messaging channels
- Contribute CLI commands
- Add gateway methods
- Provide HTTP handlers
- Extend configuration schemas

## Plugin Structure

```
extensions/discord/
├── package.json
├── src/
│   ├── index.ts      # Plugin entry point
│   ├── channel.ts    # Channel plugin definition
│   └── ...
└── tsconfig.json
```

### Package.json

```json
{
  "name": "@openclaw/discord",
  "version": "2026.1.29",
  "type": "module",
  "openclaw": {
    "extensions": ["./index.ts"]
  },
  "dependencies": {
    "discord.js": "^14.0.0"
  },
  "devDependencies": {
    "openclaw": "workspace:*"
  }
}
```

Key fields:
- `openclaw.extensions`: Entry point(s) for plugin loading
- `dependencies`: Runtime dependencies
- `devDependencies`: Use `workspace:*` for openclaw SDK

## Plugin Registration

### Entry Point

```typescript
// extensions/discord/src/index.ts

import { OpenClawPluginApi } from "openclaw/plugin-sdk";
import { discordPlugin } from "./channel";

export function register(api: OpenClawPluginApi) {
  // Register channel
  api.registerChannel({ plugin: discordPlugin });

  // Register CLI commands
  api.registerCliCommand({
    name: "discord",
    description: "Discord management",
    action: async (opts) => { /* ... */ }
  });

  // Register gateway methods
  api.registerGatewayMethod("discord.status", async (ctx) => {
    return { status: "ok" };
  });
}
```

### Plugin API

```typescript
interface OpenClawPluginApi {
  // Channel registration
  registerChannel(opts: { plugin: ChannelPlugin }): void;

  // CLI commands
  registerCliCommand(cmd: CliCommandDef): void;

  // Gateway methods
  registerGatewayMethod(
    name: string,
    handler: GatewayMethodHandler
  ): void;

  // HTTP routes
  registerHttpHandler(
    path: string,
    handler: HttpHandler
  ): void;

  // Configuration
  extendConfig(schema: ConfigSchema): void;

  // Hooks
  registerHook(hook: HookDef): void;

  // Logging
  log: Logger;
}
```

## Plugin Discovery

### Discovery Paths

1. Built-in: `extensions/*/`
2. External: `OPENCLAW_PLUGIN_CATALOG_PATHS` env var
3. Config: `config.plugins.paths`

### Discovery Flow

```
Scan extension directories
    |
    v
Read package.json for openclaw.extensions
    |
    v
Validate plugin structure
    |
    v
Deduplicate by channel ID (extension overrides core)
    |
    v
Cache in plugin registry
```

## Plugin Loading

### Lazy Loading

Plugins load on demand:

```typescript
// Load plugins for CLI
await ensurePluginRegistryLoaded();

// Get loaded plugins
const plugins = getActivePluginRegistry();
```

### Load Conditions

Plugins load when:
- `openclaw message` command runs
- `openclaw channels` command runs
- Gateway starts
- Plugin explicitly requested

## Channel Plugins

### Plugin Definition

```typescript
export const discordPlugin: ChannelPlugin<ResolvedDiscordAccount> = {
  id: "discord",

  meta: {
    label: "Discord",
    docsPath: "/channels/discord",
    icon: "discord-icon",
    aliases: ["dc"]
  },

  capabilities: {
    chatTypes: ["direct", "channel", "thread"],
    polls: true,
    reactions: true,
    threads: true,
    media: true,
    nativeCommands: true
  },

  config: {
    listAccountIds: (cfg) => [...],
    resolveAccount: (cfg, id) => {...},
    isConfigured: (account) => {...},
    isEnabled: (account, cfg) => {...}
  },

  outbound: {
    deliveryMode: "direct",
    textChunkLimit: 2000,
    sendText: async (ctx, text) => {...},
    sendMedia: async (ctx, media) => {...}
  },

  security: {
    resolveDmPolicy: (ctx) => ({
      policy: "allowlist",
      allowFrom: ctx.account.allowFrom
    }),
    collectWarnings: (ctx) => [...]
  },

  gateway: {
    startAccount: async (ctx) => {...},
    stopAccount: async (ctx) => {...},
    logoutAccount: async (ctx) => {...}
  },

  messaging: {
    normalizeTarget: (target) => target.replace("@", ""),
    targetResolver: {
      looksLikeId: (t) => /^\d+$/.test(t),
      hint: "user ID or @username"
    }
  },

  directory: {
    self: async () => ({...}),
    listPeers: async () => [...],
    listGroups: async () => [...]
  },

  actions: {
    listActions: () => ["react", "reply"],
    handleAction: async (ctx, action) => {...}
  }
};
```

## Available Extensions

### Channel Extensions

| Extension | Purpose |
|-----------|---------|
| discord | Discord Bot API |
| telegram | Telegram Bot API |
| slack | Slack Socket Mode |
| signal | Signal CLI |
| imessage | iMessage bridge |
| msteams | Microsoft Teams |
| matrix | Matrix protocol |
| mattermost | Mattermost |
| googlechat | Google Chat |
| line | LINE messenger |
| zalo | Zalo messenger |
| voice-call | Voice calls |
| bluebubbles | iMessage (BlueBubbles) |
| tlon | Tlon/Urbit |
| nostr | Nostr protocol |
| twitch | Twitch chat |

### Feature Extensions

| Extension | Purpose |
|-----------|---------|
| memory-lancedb | Vector memory backend |
| memory-core | Core memory functions |
| llm-task | LLM-based task execution |
| open-prose | Writing/prose tools |
| diagnostics-otel | OpenTelemetry diagnostics |
| lobster | Enhanced CLI features |
| copilot-proxy | GitHub Copilot proxy |

### Auth Extensions

| Extension | Purpose |
|-----------|---------|
| google-antigravity-auth | Google auth helper |
| google-gemini-cli-auth | Gemini CLI auth |
| qwen-portal-auth | Qwen Portal OAuth |

## Plugin Configuration

### Enabling Plugins

```json5
{
  plugins: {
    enabled: ["@openclaw/discord", "@openclaw/memory-lancedb"],
    disabled: ["@openclaw/msteams"],
    paths: ["/custom/plugins/"]
  }
}
```

### Plugin-Specific Config

Plugins can extend the config schema:

```typescript
api.extendConfig({
  discord: {
    type: "object",
    properties: {
      botToken: { type: "string" },
      presence: {
        type: "object",
        properties: {
          status: { enum: ["online", "idle", "dnd"] }
        }
      }
    }
  }
});
```

## Plugin SDK

### Importing

```typescript
import {
  OpenClawPluginApi,
  ChannelPlugin,
  ChannelCapabilities,
  ChannelMeta
} from "openclaw/plugin-sdk";
```

### Exports

The SDK exports:
- Type definitions for plugins
- Channel adapter interfaces
- Configuration schema types
- Logging utilities
- Common helpers

### Resolution

Plugins access SDK via jiti alias (no workspace dependency at runtime):

```typescript
// Resolved at runtime:
// "openclaw/plugin-sdk" -> src/plugin-sdk/index.ts
```

## Gateway Method Plugins

```typescript
api.registerGatewayMethod("my-plugin.status", async (ctx) => {
  const { params, broadcast, log } = ctx;

  // Process request
  const status = await getPluginStatus(params);

  // Optionally broadcast to clients
  broadcast({ event: "my-plugin.status-update", data: status });

  return { ok: true, data: status };
});
```

## HTTP Handler Plugins

```typescript
api.registerHttpHandler("/my-plugin/webhook", async (req, res) => {
  const payload = await req.json();

  // Process webhook
  await handleWebhook(payload);

  res.json({ received: true });
});
```

## CLI Command Plugins

```typescript
api.registerCliCommand({
  name: "my-plugin",
  description: "My plugin commands",
  subcommands: [
    {
      name: "status",
      description: "Show plugin status",
      options: [
        { flags: "-v, --verbose", description: "Verbose output" }
      ],
      action: async (opts) => {
        console.log(await getStatus(opts));
      }
    }
  ]
});
```

## Hook Plugins

```typescript
api.registerHook({
  event: "message.inbound",
  handler: async (ctx) => {
    // Pre-process incoming messages
    ctx.message.text = transformText(ctx.message.text);
    return ctx;
  }
});
```

## Development

### Creating a Plugin

```bash
# Create extension directory
mkdir -p extensions/my-plugin/src

# Create package.json
cat > extensions/my-plugin/package.json << 'EOF'
{
  "name": "@openclaw/my-plugin",
  "version": "2026.1.29",
  "type": "module",
  "openclaw": {
    "extensions": ["./src/index.ts"]
  }
}
EOF

# Create entry point
cat > extensions/my-plugin/src/index.ts << 'EOF'
import { OpenClawPluginApi } from "openclaw/plugin-sdk";

export function register(api: OpenClawPluginApi) {
  api.log.info("My plugin loaded!");
}
EOF
```

### Testing Plugins

```bash
# Test plugin loads
pnpm openclaw plugins list

# Enable plugin
pnpm openclaw config set plugins.enabled '["@openclaw/my-plugin"]'

# Check status
pnpm openclaw plugins status
```

## Design Patterns

1. **Lazy Loading**: Plugins load on demand
2. **Override Mechanism**: Extensions override core with same ID
3. **Type Safety**: Full TypeScript support via SDK
4. **Isolation**: Plugins run in same process but isolated context
5. **Hot Reload**: Gateway supports hot reload of plugins
6. **Config Extension**: Plugins can extend config schema
7. **Logging Integration**: Plugins use shared logging system
8. **Discovery Convention**: Standard package.json field for entry points
