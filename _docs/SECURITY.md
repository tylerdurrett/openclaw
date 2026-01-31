# Security and Sandboxing

OpenClaw implements a multi-layered security architecture with exec approvals, sandbox isolation, and tool policy enforcement.

## Overview

Security features:
- Exec approval workflow for command execution
- Docker-based sandbox isolation
- Tool policy enforcement with allow/deny lists
- Gateway authentication and authorization
- External content injection detection
- Filesystem permission validation

## Key Files

| File | Purpose |
|------|---------|
| `src/security/audit.ts` | Security audit system |
| `src/security/audit-fs.ts` | Filesystem security checks |
| `src/security/external-content.ts` | Injection detection |
| `src/infra/exec-approvals.ts` | Approval workflow |
| `src/agents/sandbox/` | Docker sandbox system |
| `src/agents/tool-policy.ts` | Tool access control |

## Security Audit

### Gateway Configuration

Checks for:
- Bind address beyond loopback without auth
- Missing token/password for non-local binds
- Tailscale Funnel vs Serve modes
- Control UI security (HTTP auth, device identity)
- Trusted proxy configuration

### Filesystem Security

```typescript
// Checks performed
- Permission validation (0o700 for dirs, 0o600 for files)
- Symlink detection in critical paths
- Windows ACL inspection (icacls)
- Group/world writable detection
```

### Channel Security

- DM policy enforcement (open, disabled, pairing)
- Multi-user session isolation
- Discord slash command access groups
- Telegram group command allowlists
- Plugin security warnings

## Exec Approvals

### Security Modes

| Mode | Description |
|------|-------------|
| `deny` | All commands rejected (default) |
| `allowlist` | Only pre-approved commands |
| `full` | All commands allowed |

### Ask Modes

| Mode | Description |
|------|-------------|
| `off` | No prompting |
| `on-miss` | Prompt for non-allowlisted |
| `always` | Always prompt |

### Allowlist System

```json5
{
  tools: {
    exec: {
      security: "allowlist",
      ask: "on-miss",
      allowlist: [
        "/usr/bin/jq",
        "/usr/local/bin/*",
        "**/*.sh"
      ]
    }
  }
}
```

Pattern matching:
- Exact paths: `/usr/bin/jq`
- Glob patterns: `/usr/local/bin/*`
- Wildcards: `**/*.sh`

### Safe Binaries

Pre-approved: `jq`, `grep`, `cut`, `sort`, `uniq`, `head`, `tail`, `tr`, `wc`

### Command Analysis

```
Shell parsing respects:
- Quoting rules
- Escaping
- Parentheses
- Chain operators (&&, ||, ;)
- Pipe segments
```

Disallowed tokens: `>`, `<`, backticks, `$()`, `|`

### Approval Decisions

| Decision | Effect |
|----------|--------|
| `allow-once` | Single execution |
| `allow-always` | Add to allowlist |
| `deny` | Block execution |

### Storage

- Location: `~/.openclaw/exec-approvals.json` (0o600)
- Socket: `~/.openclaw/exec-approvals.sock`
- Token-based auth for socket requests
- Hash-based conflict detection

## Sandbox Execution

### Sandbox Modes

| Mode | Description |
|------|-------------|
| `off` | No sandboxing |
| `non-main` | Only non-main sessions |
| `all` | All sessions sandboxed |

### Scope Options

| Scope | Isolation |
|-------|-----------|
| `session` | Per-session container |
| `agent` | Per-agent container |
| `shared` | Single shared container |

### Docker Configuration

```json5
{
  tools: {
    sandbox: {
      enabled: true,
      mode: "all",
      scope: "session",
      docker: {
        image: "openclaw/sandbox:latest",
        network: "none",
        capDrop: ["ALL"],
        readOnly: true,
        tmpfs: ["/tmp", "/var/tmp", "/run"],
        memoryLimit: "512m",
        cpuShares: 2,
        pidLimit: 100
      }
    }
  }
}
```

### Resource Limits

| Resource | Options |
|----------|---------|
| Memory | `memoryLimit`, `memorySwapLimit` |
| CPU | `cpuShares` (0.5-4 typical) |
| Processes | `pidLimit` |

### Security Profiles

- Seccomp profile (syscall restriction)
- AppArmor profile
- All capabilities dropped by default

### Workspace Access

| Mode | Description |
|------|-------------|
| `none` | Read-only copy |
| `ro` | Read-only bind mount |
| `rw` | Full read-write |

### Container Lifecycle

- Auto-prune idle containers (>N hours)
- Auto-prune old containers (>N days)
- Skills synced on startup
- Optional setup commands

## Tool Policy

### Policy Layers

1. Sandbox-specific (highest)
2. Agent-specific
3. Global policy
4. Default policy (lowest)

### Tool Groups

| Group | Tools |
|-------|-------|
| `group:fs` | read, write, edit, apply_patch |
| `group:runtime` | exec, process |
| `group:memory` | memory_search, memory_get |
| `group:web` | web_search, web_fetch |
| `group:sessions` | sessions_list/history/send/spawn |
| `group:ui` | browser, canvas |
| `group:automation` | cron, gateway |
| `group:messaging` | message |
| `group:nodes` | nodes |
| `group:openclaw` | All native tools |

### Profile Presets

| Profile | Included |
|---------|----------|
| `minimal` | session_status only |
| `coding` | group:fs, group:runtime, group:sessions, group:memory, image |
| `messaging` | group:messaging, session tools |
| `full` | All tools |

### Configuration

```json5
{
  tools: {
    allow: ["group:fs", "group:runtime"],
    deny: ["gateway", "cron"],
    elevated: []
  }
}
```

### Subagent Restrictions

Default deny list:
- Session management tools
- Gateway/admin tools
- Memory tools (passed via spawn context)
- Scheduling tools (cron)

## External Content Security

### Injection Detection

Pattern matching for:
- "ignore previous instructions"
- "you are now a..."
- "new instructions:"
- Dangerous keywords: `exec`, `elevated`, `rm -rf`, `delete`

### Content Wrapping

```xml
<external-content source="email">
  [User content here]
</external-content>
```

### Handling

- Suspicious patterns logged
- Content labeled with source
- Not blocked (to avoid false positives)

## Approval Forwarding

Distributes exec approvals to messaging channels:

### Configuration

```json5
{
  tools: {
    exec: {
      approvals: {
        forwarding: {
          mode: "both",  // "session", "targets", "both"
          agents: ["*"],
          targets: [
            { channel: "discord", account: "bot-123", target: "channel:456" }
          ]
        }
      }
    }
  }
}
```

### Request Flow

```
Command blocked
    |
    v
Approval request created
    |
    v
Forwarder receives via gateway
    |
    v
Resolve delivery target
    |
    v
Send formatted message to channel
    |
    v
User replies: /approve <id> allow-once|allow-always|deny
    |
    v
Response routed back
    |
    v
Execution proceeds or fails
```

## Gateway Security

### Authentication

| Method | Description |
|--------|-------------|
| Token | Shared secret token |
| Password | Shared password |
| Tailscale | Identity headers |
| Device | Device-specific token |

### Authorization Scopes

| Scope | Permissions |
|-------|-------------|
| `operator.admin` | Full access |
| `operator.read` | Health, status, models |
| `operator.write` | Send, agent run, chat |
| `operator.approvals` | Exec approvals |
| `operator.pairing` | Device pairing |

### Bind Security

| Bind | Auth Required |
|------|---------------|
| `loopback` | No |
| `lan` | Yes |
| `tailnet` | Yes |
| `funnel` | Yes + password |

## File Permissions

| Path | Permissions | Purpose |
|------|-------------|---------|
| `~/.openclaw/` | 0o700 | State directory |
| `~/.openclaw/openclaw.json` | 0o600 | Config file |
| `~/.openclaw/exec-approvals.json` | 0o600 | Approvals |
| `~/.openclaw/credentials/` | 0o700 | Credentials |
| `~/.openclaw/sessions/` | 0o700 | Sessions |

## Security Principles

1. **Defense in Depth**: Multiple overlapping controls
2. **Least Privilege**: Defaults to deny, require explicit allow
3. **Fail Secure**: Unparseable commands rejected
4. **Audit Trail**: All approvals tracked
5. **External Content Warning**: Prominent security notices
6. **No Hardcoded Secrets**: Token generation, configurable paths
7. **Cross-Platform**: POSIX + Windows ACL validation
8. **Gradual Enablement**: Safe defaults, explicit opt-in
