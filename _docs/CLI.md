# CLI Architecture

The OpenClaw CLI is built on Commander.js with lazy loading, route-first optimization, and plugin extensibility. It provides 100+ commands for interacting with the gateway, channels, agents, and system configuration.

## Entry Point

The CLI starts with `runCli()` in `src/cli/run-main.ts`:

```
runCli(argv)
  |-- Load .env & normalize environment
  |-- tryRouteCli() [route-first optimization]
  |   |-- Match against pre-optimized routes
  |   |-- If match: run route.run(), exit
  |   +-- If no match: continue
  |-- buildProgram()
  |   |-- createProgramContext()
  |   |-- configureProgramHelp()
  |   |-- registerPreActionHooks()
  |   +-- registerProgramCommands()
  |-- registerSubCliByName() [primary command lazy load]
  |-- registerPluginCliCommands() [conditional]
  +-- program.parseAsync(argv)
       |-- preAction hooks run
       |   |-- ensureConfigReady()
       |   |-- ensurePluginRegistryLoaded() [conditional]
       |   +-- emitCliBanner()
       +-- Command action() runs
```

## Key Files

| File | Purpose |
|------|---------|
| `src/cli/run-main.ts` | Main entry point |
| `src/cli/route.ts` | Route-first optimization |
| `src/cli/argv.ts` | Argument parsing utilities |
| `src/cli/program/build-program.ts` | Program builder |
| `src/cli/program/command-registry.ts` | Command registration |
| `src/cli/program/register.subclis.ts` | Lazy loading system |
| `src/cli/program/preaction.ts` | Lifecycle hooks |
| `src/cli/program/help.ts` | Help formatting |

## Command Groups

### Core Commands (Always Registered)

| Command | Description |
|---------|-------------|
| `setup` | Initialize OpenClaw config and workspace |
| `onboard` | Interactive wizard setup |
| `configure` | Config management |
| `config` | CLI config access |
| `maintenance` | Maintenance operations |
| `message` | Send messages and channel actions |
| `memory` | Memory/vector database management |
| `agent` | Run agent turns via Gateway |
| `browser` | Browser automation |
| `status` | System status |
| `health` | Health check |
| `sessions` | Session listing |

### Subcommand Groups (Lazy-Loaded)

| Group | Description |
|-------|-------------|
| `gateway` | Gateway control (run, stop, status) |
| `daemon` | Gateway service (legacy) |
| `logs` | Gateway logs |
| `system` | System events/heartbeat/presence |
| `models` | Model configuration |
| `approvals` | Exec approvals |
| `nodes` | Node commands |
| `devices` | Device pairing + token management |
| `sandbox` | Sandbox tools |
| `tui` | Terminal UI |
| `cron` | Cron scheduler |
| `dns` | DNS helpers |
| `docs` | Docs helpers |
| `hooks` | Hooks tooling |
| `webhooks` | Webhook helpers |
| `pairing` | Pairing helpers |
| `plugins` | Plugin management |
| `channels` | Channel management |
| `directory` | Directory commands |
| `security` | Security helpers |
| `skills` | Skills management |
| `update` | CLI update helpers |
| `completion` | Shell completion generation |

## Lazy Loading System

The CLI uses lazy loading to reduce startup time. Only invoked subcommands are loaded:

```typescript
// src/cli/program/register.subclis.ts

// 1. Parse argv to find primary command
const primaryCommand = getPrimaryCommand(argv);  // e.g., "gateway"

// 2. Register only that subcommand's lazy placeholder
if (primaryCommand === "gateway") {
  registerLazySubCli("gateway", lazyGatewayCli);
}

// 3. When invoked, load actual subcommand
function registerLazySubCli(name, loader) {
  program.command(name)
    .action(async () => {
      program.commands = program.commands.filter(c => c.name() !== name);
      const subcli = await loader();
      subcli(program);
      await program.parseAsync(argv);
    });
}
```

## Route-First Optimization

High-frequency commands bypass full program initialization:

```typescript
// src/cli/route.ts

const routes: Route[] = [
  { match: ["health"], run: healthRoute },
  { match: ["status"], run: statusRoute },
  { match: ["sessions"], run: sessionsRoute },
  { match: ["agents", "list"], run: agentsListRoute },
  { match: ["memory", "status"], run: memoryStatusRoute },
];

export async function tryRouteCli(argv: string[]): Promise<boolean> {
  for (const route of routes) {
    if (matchesRoute(argv, route.match)) {
      await route.run(argv);
      return true;  // Handled, skip full init
    }
  }
  return false;  // Continue with full init
}
```

## Pre-action Hooks

Lifecycle hooks run before every command action:

```typescript
// src/cli/program/preaction.ts

program.hook("preAction", async (thisCommand, actionCommand) => {
  // 1. Set process title for debugging
  setProcessTitle(`openclaw-${actionCommand.name()}`);

  // 2. Display banner (unless quiet mode)
  if (!isQuietMode) emitCliBanner();

  // 3. Set verbose flag
  if (hasVerboseFlag(argv)) enableVerboseLogging();

  // 4. Ensure config ready
  await ensureConfigReady();

  // 5. Load plugins (for certain commands)
  if (needsPlugins(actionCommand)) {
    await ensurePluginRegistryLoaded();
  }
});
```

## Command Registration Patterns

### Simple Command

```typescript
program
  .command("agent")
  .description("Run an agent turn")
  .requiredOption("-m, --message <text>", "Message body")
  .option("--channel <channel>", "Delivery channel")
  .action(async (opts) => {
    await agentCliCommand(opts, defaultRuntime, deps);
  });
```

### Nested Commands

```typescript
const agents = program
  .command("agents")
  .description("Manage isolated agents");

agents
  .command("list")
  .description("List configured agents")
  .action(async (opts) => { /* ... */ });

agents
  .command("add [name]")
  .description("Add a new isolated agent")
  .action(async (name, opts) => { /* ... */ });
```

### Multi-Group Commands

```typescript
const message = program.command("message");
const helpers = createMessageCliHelpers(message, channelOptions);
registerMessageSendCommand(message, helpers);
registerMessageReactionsCommands(message, helpers);
registerMessagePollCommands(message, helpers);
```

## Argument Parsing Utilities

```typescript
// src/cli/argv.ts

// Detect help/version flags
hasHelpOrVersion(argv);  // true if -h, -v, --help, --version

// Extract primary command
getPrimaryCommand(["openclaw", "gateway", "run"]);  // "gateway"

// Get command path
getCommandPath(argv, 2);  // ["gateway", "run"]

// Parse flags
hasFlag(argv, "--verbose");
getFlagValue(argv, "--port");
getPositiveIntFlagValue(argv, "--timeout");
```

## Context Management

```typescript
// src/cli/program/context.ts

interface ProgramContext {
  programVersion: string;
  channelOptions: string[];        // ["telegram", "discord", ...]
  messageChannelOptions: string;   // "telegram|discord|..."
  agentChannelOptions: string;     // "telegram|discord|...|last"
}
```

## Dependency Injection

```typescript
// src/cli/deps.ts

type CliDeps = {
  sendMessageWhatsApp: typeof sendMessageWhatsApp;
  sendMessageTelegram: typeof sendMessageTelegram;
  sendMessageDiscord: typeof sendMessageDiscord;
  sendMessageSlack: typeof sendMessageSlack;
  sendMessageSignal: typeof sendMessageSignal;
  sendMessageIMessage: typeof sendMessageIMessage;
};

// Usage
const deps = createDefaultDeps();
await sendCommand(opts, deps);
```

## Plugin Integration

Plugins can contribute CLI commands:

```typescript
// Plugin's index.ts
export function register(api: OpenClawPluginApi) {
  api.registerCliCommand({
    name: "my-command",
    description: "Custom command from plugin",
    action: async (opts) => { /* ... */ }
  });
}

// Loading in CLI
await ensurePluginRegistryLoaded();
const plugins = getActivePluginRegistry();
for (const plugin of plugins) {
  plugin.registerCliCommands(program);
}
```

## Help Formatting

Custom help formatting with color and examples:

```typescript
// src/cli/program/help.ts

function configureProgramHelp(program: Command) {
  program.configureHelp({
    formatHelp: (cmd, helper) => {
      // Custom formatting with colors
      return formatHelpWithExamples(cmd, helper, {
        examples: [
          { cmd: "openclaw send -m 'Hello'", desc: "Send a message" },
          { cmd: "openclaw gateway run", desc: "Start the gateway" }
        ],
        docsLink: "https://docs.openclaw.ai/cli"
      });
    }
  });
}
```

## Error Handling

```typescript
// src/cli/cli-utils.ts

async function runCommandWithRuntime<T>(
  fn: () => Promise<T>
): Promise<T> {
  try {
    return await fn();
  } catch (error) {
    if (error instanceof UserFacingError) {
      console.error(chalk.red(error.message));
      process.exit(1);
    }
    throw error;
  }
}
```

## Design Patterns

1. **Lazy Loading**: Subcommands load only when invoked
2. **Route-First Optimization**: High-frequency commands bypass full parsing
3. **Plugin Architecture**: Commands can hook into extensibility system
4. **Composable Helpers**: Command registration functions compose larger CLIs
5. **Pre-action Hooks**: Lifecycle management centralized
6. **Dependency Injection**: Channel implementations injected, not imported
7. **Structured Logging**: All output through subsystem logger
