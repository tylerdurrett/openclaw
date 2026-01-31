# AI Agent System

OpenClaw's agent system is built on `@mariozechner/pi-coding-agent` and provides sophisticated AI provider integration, tool execution, and multi-agent capabilities.

## Architecture Overview

```
                    Channel Layer
                         |
                         v
            Session Management & Routing
                         |
                         v
        Embedded Pi Agent Runner (runEmbeddedPiAgent)
        |-- Model selection & auth handling
        |-- Failover & retry logic
                         |
                         v
            Tool Creation & Execution Layer
            |-- OpenClaw coding tools
            |-- Channel-specific tools
            |-- Tool policy filtering
                         |
                         v
          PI AI SDK Integration (@mariozechner/pi-*)
                         |
                         v
              AI Provider Integration Layer
              |-- Anthropic, OpenAI, Google
              |-- AWS Bedrock, GitHub Copilot
              |-- Model catalog, auth profiles
```

## Key Files

| File | Purpose |
|------|---------|
| `src/agents/pi-embedded-runner/run.ts` | Main agent execution |
| `src/agents/pi-embedded-subscribe.ts` | Event streaming |
| `src/agents/model-selection.ts` | Model resolution |
| `src/agents/models-config.providers.ts` | Provider setup |
| `src/agents/model-auth.ts` | Authentication |
| `src/agents/pi-tools.ts` | Tool creation |
| `src/agents/pi-tools.policy.ts` | Tool permissions |
| `src/agents/system-prompt.ts` | System prompt |
| `src/agents/agent-scope.ts` | Agent registry |

## Supported Providers

### Built-in Providers

| Provider | Models | Auth |
|----------|--------|------|
| Anthropic | Claude 3/4, Sonnet, Opus, Haiku | API key, OAuth |
| OpenAI | GPT-4, GPT-4o, o1-preview | API key |
| Google | Gemini 2.0, 1.5 Pro/Flash | API key |
| AWS Bedrock | Claude, Llama, Mistral | AWS SDK |
| GitHub Copilot | Claude, GPT | Token exchange |

### Additional Providers

| Provider | Notes |
|----------|-------|
| Qwen Portal | OAuth integration |
| MiniMax | VL-01 vision |
| Moonshot | Chinese LLM |
| Venice | Privacy-focused |
| Ollama | Local models |
| Xiaomi | Chinese provider |

## Model Selection

### Resolution Flow

```
User specifies model (e.g., "opus-4.5" or "anthropic/claude-opus-4-5")
    |
    v
parseModelRef() -> { provider, model }
    |
    v
Check agent-specific override (config.agents.list[id].model)
    |
    v
Check global default (config.agents.defaults.model)
    |
    v
Validate against allowlist (config.models.allowlist)
    |
    v
Resolve from catalog (vision, thinking capabilities)
```

### Model Aliasing

```json5
{
  agents: {
    defaults: {
      models: {
        "opus-4.5": { alias: "anthropic/claude-opus-4-5-20250514" },
        "sonnet": { alias: "anthropic/claude-sonnet-4-20250514" }
      }
    }
  }
}
```

### Model Configuration

```typescript
interface ModelRefConfig {
  primary: string;           // Primary model
  fallbacks?: string[];      // Fallback chain
}

// Usage
{
  model: {
    primary: "anthropic/claude-sonnet-4",
    fallbacks: [
      "openai/gpt-4o",
      "google/gemini-2.0-flash"
    ]
  }
}
```

## Authentication

### Auth Profile System

Stored in `~/.openclaw/agents/auth.json`:

```typescript
interface AuthProfile {
  id: string;
  provider: string;
  mode: "api-key" | "oauth" | "aws-sdk" | "token";
  apiKey?: string;
  oauthToken?: { access_token: string; refresh_token?: string };
  lastUsed?: Date;
  failureCount: number;
  cooldownUntil?: Date;
}
```

### Auth Resolution Hierarchy

1. Explicit provider apiKey (config)
2. Environment variables (ANTHROPIC_API_KEY, etc.)
3. CLI credential imports:
   - Claude CLI (~/.claude/.credentials.json)
   - Codex CLI (~/.codex/auth.json)
   - Qwen CLI (~/.qwen/oauth_creds.json)
4. macOS Keychain
5. Auth profiles store

### Profile Rotation

On auth failure:
```
Try Profile 1 (last-used)
    |-- Auth fails
    v
Try Profile 2 (next in order)
    |-- Auth fails
    v
Try Profile 3 (etc.)
    |-- All fail
    v
Fallback to next model in chain
```

Cooldown:
- First failure: 30s cooldown
- Exponential backoff: 2x per failure
- Auto-recovery after timeout

## Agent Execution

### Main Execution Flow

```typescript
runEmbeddedPiAgent(params)
    |
    v
enqueueSession(async () => {
  1. Resolve model & provider
  2. Ensure models.json is current
  3. Select auth profile
  4. Build system prompt
  5. Create tools
  6. Create session
  7. Run attempt:
     a. Build request payload
     b. Stream response from provider
     c. Handle tool calls
     d. Subscribe to session events
  8. Handle errors/failures
  9. Return result
})
```

### Session Management

```typescript
interface SessionKey {
  agentId: string;
  sessionId: string;
}

// Format: agent:{agentId}:{sessionId}
const key = "agent:default:main:telegram";
```

### Lanes for Concurrency

- Global lane: limits concurrent agent runs
- Session lane: per-session concurrency control

## Tool System

### Tool Categories

#### Coding Tools (from pi-coding-agent)

| Tool | Description |
|------|-------------|
| `read` | Read file contents |
| `write` | Write file contents |
| `edit` | In-place file editing |
| `exec` | Shell command execution |
| `apply_patch` | Apply unified diff |

#### OpenClaw Tools

| Tool | Description |
|------|-------------|
| `message` | Cross-channel messaging |
| `sessions_list` | Session discovery |
| `sessions_send` | Inter-session messaging |
| `sessions_spawn` | Subagent spawning |
| `session_status` | Session state query |
| `sessions_history` | Conversation replay |
| `web_search` | Web search |
| `web_fetch` | Web content retrieval |
| `browser` | Browser automation |
| `canvas` | Drawing/visualization |
| `image` | Image generation |
| `gateway` | Infrastructure commands |
| `agents_list` | Agent listing |
| `cron` | Scheduled tasks |
| `tts` | Text-to-speech |
| `nodes` | Node exploration |

### Tool Policy

```typescript
interface SandboxToolPolicy {
  allow?: string[];      // Whitelist (if set, deny ignored)
  alsoAllow?: string[];  // Additional allows
  deny?: string[];       // Blacklist
}
```

Pattern matching:
- Exact: `"exec"`, `"read"`
- Wildcard: `"sessions_*"`, `"memory_*"`
- All: `"*"`
- Groups: `"@workspace"`, `"@messaging"`

### Policy Resolution

1. Subagent policy (strict defaults)
2. Group-level policy (from channel config)
3. Agent-specific policy (from agent config)
4. Global policy (from root tools config)
5. Model-specific overrides

### Subagent Restrictions

```typescript
const DEFAULT_SUBAGENT_TOOL_DENY = [
  "sessions_list",
  "sessions_history",
  "sessions_send",
  "sessions_spawn",
  "gateway",
  "agents_list",
  "whatsapp_login",
  "session_status",
  "cron",
  "memory_search",
  "memory_get"
];
```

## System Prompt

### Sections

1. **Identity** - User information
2. **Time** - Timezone and current date
3. **Memory Recall** - Guidelines for memory tools
4. **Skills** - Custom SKILL.md instructions
5. **Tooling** - Available tools and usage
6. **Workspace** - Current directory and git status
7. **Messaging** - Channel routing
8. **Reply Tags** - Special formatting
9. **Runtime** - Execution environment

### Thinking Modes

| Mode | Description |
|------|-------------|
| `off` | No thinking |
| `minimal` | Brief thinking |
| `low` | Light reasoning |
| `medium` | Moderate reasoning |
| `high` | Deep reasoning |
| `xhigh` | Extended reasoning |

Model-dependent defaults from catalog.

## Streaming & Events

### Event Types

```typescript
// Text streaming
"text_delta" -> accumulate streamed text
"text_end" -> finalize assistant text
"message_end" -> complete message

// Tool execution
"tool_call" -> invoke agent tool
"tool_result" -> process tool output

// Block replies
"onBlockReply" -> stream chunks to user

// Reasoning
"onReasoningStream" -> stream thinking process
```

### Block Reply Chunking

- Paragraph-aware breaks
- `<think>` and `<final>` tag stripping
- Markdown/plain text formatting
- Duplicate detection for messaging tools

## Context Window Management

```typescript
evaluateContextWindowGuard({
  contextWindowTokens: 200000,
  usedTokens: 150000,
  estimatedTokens: 20000
}) -> {
  status: "healthy" | "warning" | "critical",
  availableTokens: number,
  shouldCompact: boolean
}
```

- Hard minimum: 4000 tokens
- Warning threshold: configurable
- Auto-compaction on overflow

### Compaction Flow

```
Context overflow detected
    |
    v
Run compaction algorithm
    |
    v
Summarize early turns
    |
    v
Keep recent interactions intact
    |
    v
Rebuild session with condensed history
    |
    v
Retry if still overflowing
```

## Subagents

### Spawn Flow

```
Parent agent calls sessions_spawn(agentId, task)
    |
    v
Create child session with parent reference
    |
    v
Inherit tool policy (more restrictive)
    |
    v
Execute in isolated session
    |
    v
Parent waits for completion (async)
    |
    v
Results flow back via messages
```

### Subagent Restrictions

- Cannot spawn further subagents
- Limited tool access
- No direct memory access
- Task-scoped context only

## Error Handling & Failover

### Error Classification

| Type | Action |
|------|--------|
| `auth` | Rotate auth profile |
| `billing` | Fail with message |
| `rate-limit` | Retry with backoff |
| `context-overflow` | Compact and retry |
| `timeout` | Retry or fail |

### Failover Chain

```
Primary model fails
    |
    v
Try fallback 1
    |-- Success: continue
    |-- Fail: next
    v
Try fallback 2
    |-- Success: continue
    |-- Fail: next
    v
...continue until exhausted or success
```

## Configuration

### Agent Config

```json5
{
  agents: {
    defaults: {
      model: "anthropic/claude-sonnet-4",
      thinkingDefault: "low"
    },
    list: [
      {
        id: "coding-agent",
        workspace: "/path/to/workspace",
        model: "anthropic/claude-opus-4",
        tools: {
          allow: ["read", "write", "exec"],
          deny: ["gateway"]
        },
        sandbox: { enabled: true },
        subagents: {
          allowlist: ["helper-agent"],
          modelOverride: "anthropic/claude-haiku"
        }
      }
    ]
  }
}
```

### Provider Config

```json5
{
  models: {
    providers: {
      anthropic: {
        apiKey: "ANTHROPIC_API_KEY",
        baseUrl: "https://api.anthropic.com",
        auth: "api-key"
      },
      openai: {
        apiKey: "OPENAI_API_KEY"
      },
      bedrock: {
        region: "us-east-1",
        auth: "aws-sdk"
      }
    },
    bedrockDiscovery: {
      enabled: true,
      region: "us-east-1"
    }
  }
}
```

## Design Patterns

1. **Pluggable Providers**: 15+ AI providers with unified interface
2. **Robust Auth**: Multi-layer auth with fallback and rotation
3. **Sophisticated Tools**: Flexible policy-based access
4. **Real-time Streaming**: Block replies, reasoning, tool results
5. **Context Management**: Auto-compaction, history limiting
6. **Hierarchical Agents**: Subagents with inherited policies
7. **Thinking Models**: First-class support with token tracking
8. **Error Resilience**: Automatic failover with backoff
9. **Sandboxing**: Fine-grained tool execution control
10. **Configuration Layers**: Per-agent, per-channel, global policies
