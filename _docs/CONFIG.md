# Configuration System

OpenClaw uses a modular JSON5-based configuration system with environment variable substitution, validation, and legacy migration support.

## Overview

The configuration system provides:
- JSON5 format with comments and trailing commas
- Environment variable substitution
- Include directives for modular configs
- Zod-based schema validation
- Automatic legacy migration
- Runtime overrides
- Atomic writes with backups

## Key Files

| File | Purpose |
|------|---------|
| `src/config/io.ts` | File reading, parsing, validation, writing |
| `src/config/paths.ts` | Config file location resolution |
| `src/config/validation.ts` | Zod schema validation |
| `src/config/zod-schema.ts` | Main schema definition |
| `src/config/defaults.ts` | Default value application |
| `src/config/includes.ts` | Include directive processing |
| `src/config/legacy*.ts` | Legacy migration system |
| `src/config/runtime-overrides.ts` | Programmatic overrides |

## File Locations

**Resolution Order:**
1. `$OPENCLAW_CONFIG_PATH` environment variable
2. `$OPENCLAW_STATE_DIR/openclaw.json`
3. `~/.openclaw/openclaw.json` (default)
4. Legacy: `~/.openclaw/clawdbot.json`, `~/.openclaw/moltbot.json`

**State Directory:**
- `$OPENCLAW_STATE_DIR` or `$CLAWDBOT_STATE_DIR` env var
- Falls back to first existing legacy dir
- Defaults to `~/.openclaw`

## Config Format

JSON5 with comments, trailing commas, and unquoted keys:

```json5
{
  // Gateway configuration
  gateway: {
    port: 18789,
    bind: "loopback",  // or "lan", "tailnet", "auto"
    auth: {
      mode: "token",
      token: "${GATEWAY_TOKEN}"  // env var substitution
    }
  },

  // Model providers
  models: {
    providers: {
      anthropic: {
        apiKey: "${ANTHROPIC_API_KEY}"
      },
      openai: {
        apiKey: "${OPENAI_API_KEY}"
      }
    }
  },

  // Agent configuration
  agents: {
    defaults: {
      model: "anthropic/claude-sonnet-4"
    },
    list: [
      {
        id: "coding-agent",
        workspace: "~/projects"
      }
    ]
  },

  // Channel configuration
  channels: {
    telegram: {
      enabled: true,
      accounts: {
        "my-bot": {
          token: "${TELEGRAM_BOT_TOKEN}"
        }
      }
    }
  }
}
```

## Loading Pipeline

```
loadConfig()
  |-- Read raw JSON5 file
  |-- Parse JSON5 to object
  |-- Process $include directives
  |-- Apply config.env.vars to process.env
  |-- Substitute ${VAR} placeholders
  |-- Validate with Zod schema
  |-- Apply default values
  |-- Normalize paths (~)
  |-- Check duplicate agent directories
  |-- Apply runtime overrides
  +-- Return validated config
```

## Environment Variables

### Substitution Syntax

```json5
{
  models: {
    providers: {
      anthropic: {
        apiKey: "${ANTHROPIC_API_KEY}"  // Replaced with env value
      }
    }
  }
}
```

- Pattern: `${UPPERCASE_VAR_NAME}`
- Only matches: `[A-Z_][A-Z0-9_]*`
- Escape literal: `$${VAR}` → `${VAR}`
- Missing vars throw `MissingEnvVarError`

### Config-Defined Env Vars

```json5
{
  env: {
    vars: {
      MY_VAR: "value"  // Applied to process.env
    },
    shellEnv: {
      enabled: true    // Load from shell if missing
    }
  }
}
```

Order:
1. `config.env.vars` applied to process.env
2. Then `${VAR}` substitution (can reference config-defined vars)

## Include Directives

### Single File

```json5
{
  "$include": "./base.json5"
}
```

### Multiple Files

```json5
{
  "$include": ["./channels.json5", "./models.json5"]
}
```

### Merge Strategy

- Arrays: concatenate
- Objects: merge recursively
- Primitives: source wins
- Max depth: 10
- Circular include protection

## Schema Structure

```
OpenClawConfig
├── meta (version tracking)
├── env (environment variables)
├── wizard (onboarding state)
├── diagnostics (OpenTelemetry)
├── logging (log levels)
├── browser (Chromium settings)
├── ui (assistant avatar, colors)
├── auth (credential profiles)
├── models (providers, aliases)
├── agents (list, defaults, concurrency)
├── tools (definitions, allowlists)
├── channels (per-provider config)
├── plugins (enable/disable)
├── session (scope, reset, TTL)
├── gateway (port, auth, TLS)
├── cron (scheduled tasks)
├── hooks (webhooks)
├── discovery (mDNS)
└── canvasHost (canvas server)
```

## Validation

### Two-Level Validation

1. **Base Validation:**
   - Check legacy issues
   - Run Zod schema validation
   - Check duplicate agent directories
   - Validate identity avatars

2. **Plugin-Aware Validation:**
   - Validate plugin configs against JSON schemas
   - Check channel IDs are known
   - Validate heartbeat targets
   - Collect warnings

### Validation Result

```typescript
interface ValidationResult {
  ok: boolean;
  config?: OpenClawConfig;
  issues?: ConfigValidationIssue[];
  warnings?: ConfigValidationIssue[];
}
```

## Default Values

### Model Aliases

```typescript
{
  "opus": "anthropic/claude-opus-4-5",
  "sonnet": "anthropic/claude-sonnet-4-5",
  "gpt": "openai/gpt-5.2",
  "gemini": "google/gemini-3-pro-preview"
}
```

### Applied Defaults

- Message formatting
- Model cost defaults
- Agent concurrency
- Session scope and reset behavior
- Logging levels
- Context pruning tokens

## Runtime Overrides

Programmatic config modification without touching files:

```typescript
// Set value at path
setConfigOverride("agents.defaults.model", "anthropic/claude-opus-4");

// Remove value
unsetConfigOverride("agents.defaults.model");

// Get current overrides
const overrides = getConfigOverrides();

// Clear all
resetConfigOverrides();
```

Path format:
- Dot notation: `agents.defaults.model`
- Bracket notation: `channels[discord].enabled`
- Blocked: `__proto__`, `prototype`, `constructor`

## Writing Config

### Write Pipeline

```
writeConfigFile()
  |-- Validate config
  |-- Create directory (0o700)
  |-- Serialize to JSON (2-space indent)
  |-- Write to temporary file
  |-- Rotate existing backups (keep 5)
  |-- Atomic rename
  +-- Set permissions (0o600)
```

### Backups

- Keep up to 5 backups
- Names: `config.json.bak`, `.bak.1`, `.bak.2`, etc.
- Automatic rotation on write

### Stamping

```json5
{
  meta: {
    lastTouchedVersion: "2026.1.29",
    lastTouchedAt: "2026-01-29T12:00:00Z"
  }
}
```

## Caching

### Config Cache

- Time-based with configurable TTL
- Default: 200ms
- Control: `OPENCLAW_CONFIG_CACHE_MS`
- Disable: `OPENCLAW_DISABLE_CONFIG_CACHE`

### Session Store Cache

- Separate cache for sessions
- Default TTL: 45 seconds
- Control: `OPENCLAW_SESSION_CACHE_TTL_MS`
- File mtime checking for invalidation

## Legacy Migration

### Migration System

Files:
- `legacy.ts`: Detects legacy issues
- `legacy.rules.ts`: Rule definitions
- `legacy.migrations.ts`: Migration aggregator
- `legacy-migrate.ts`: Main orchestrator

### Migration Process

```
migrateLegacyConfig()
  |-- Apply all migrations
  |-- Validate migrated config
  +-- Return config + applied changes
```

Detected issues:
- Removed routing patterns
- iMessage DM policy changes
- Old gateway token format
- Channel deprecations

## CLI Commands

```bash
# Get config value
openclaw config get agents.defaults.model

# Set config value
openclaw config set agents.defaults.model "anthropic/claude-opus-4"

# Unset config value
openclaw config unset agents.list[0].workspace

# Validate config
openclaw config validate

# Interactive setup
openclaw configure
openclaw configure --section models
```

## Sessions Storage

Separate from config:

| Data | Location |
|------|----------|
| Config | `~/.openclaw/openclaw.json` |
| Sessions | `~/.openclaw/agents/<id>/sessions/*.jsonl` |
| Metadata | `~/.openclaw/agents/<id>/sessions/metadata.json` |

Session format: JSONL (JSON Lines) for streaming updates.

## Error Handling

### Custom Errors

| Error | Cause |
|-------|-------|
| `MissingEnvVarError` | Missing environment variable |
| `ConfigIncludeError` | Error resolving includes |
| `CircularIncludeError` | Circular include detected |
| `DuplicateAgentDirError` | Duplicate agent workspace |

### Recovery

- Invalid config defaults to `{}`
- Validation failures preserved for diagnostics
- Logged once per config path (deduplication)

## Security

- File permissions: 0o600 (config), 0o700 (directory)
- Path traversal protection in includes
- Env var name validation
- Blocked prototype pollution keys
