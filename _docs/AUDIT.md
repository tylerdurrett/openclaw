# OpenClaw Security Audit Report

**Date:** 2026-01-31
**Auditor:** Automated Security Analysis
**Scope:** Full codebase review of openclaw repository

---

## Executive Summary

OpenClaw is a multi-channel messaging gateway with AI agent capabilities. This audit examined authentication, input validation, file system operations, command execution, secrets management, and dependency security across the codebase.

**Overall Assessment:** The codebase demonstrates security-conscious design with several strong security practices in place. However, some areas require attention, particularly around dynamic code execution, insecure randomness in non-test contexts, and subprocess spawning patterns.

### Risk Summary

| Severity | Count | Description |
|----------|-------|-------------|
| Critical | 3 | Dynamic code execution, potential command injection |
| High | 4 | Insecure randomness, shell usage patterns |
| Medium | 6 | Token handling, configuration exposure risks |
| Low | 8 | Informational findings, hardening opportunities |

---

## Critical Findings

### C1. Dynamic Code Execution in Browser Automation

**Location:** [pw-tools-core.interactions.ts:227-256](src/browser/pw-tools-core.interactions.ts#L227-L256)

**Description:** The browser automation module uses `new Function()` and `eval()` to execute arbitrary code within browser contexts:

```typescript
const elementEvaluator = new Function(
  "el",
  "fnBody",
  `
  "use strict";
  try {
    var candidate = eval("(" + fnBody + ")");
    return typeof candidate === "function" ? candidate(el) : candidate;
  } catch (err) { ... }
  `,
);
```

**Risk:** While this is used for legitimate browser automation (Playwright page.evaluate), the pattern allows arbitrary code execution. If `fnText` is controllable by untrusted input, this could lead to code injection.

**Mitigation:**
- Ensure `fnText` parameter is never sourced from untrusted user input
- Consider using Playwright's native `page.evaluate()` with pre-defined functions instead of dynamic function construction
- Document the trust boundary clearly

**Status:** Requires code path analysis to determine if user input can reach this function

---

### C2. Token Comparison Without Constant-Time Guarantee in Hook Handler

**Location:** [server-http.ts:80](src/gateway/server-http.ts#L80)

**Description:** The hook token validation uses direct string comparison:

```typescript
if (!token || token !== hooksConfig.token) {
  res.statusCode = 401;
```

**Risk:** Unlike the gateway authentication which uses `timingSafeEqual`, this comparison is vulnerable to timing attacks that could allow token extraction.

**Mitigation:** Use timing-safe comparison for all token validations:
```typescript
import { timingSafeEqual } from "node:crypto";

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  return timingSafeEqual(Buffer.from(a), Buffer.from(b));
}
```

**Status:** Should be fixed

---

### C3. Shell Mode Fallback on Windows

**Location:** [lobster-tool.ts:59-64](extensions/lobster/src/lobster-tool.ts#L59-L64)

**Description:** The Lobster tool spawns subprocesses with a fallback to `shell: true` on Windows:

```typescript
const child = spawn(execPath, argv, {
  cwd,
  stdio: ["ignore", "pipe", "pipe"],
  env,
  shell: useShell,  // Can be true on Windows
  windowsHide: useShell ? true : undefined,
});
```

**Risk:** When `shell: true` is used, command injection becomes possible if any `argv` values contain shell metacharacters. The `pipeline` parameter from user input flows into `argv`.

**Mitigation:**
- Never use `shell: true` with user-controlled arguments
- Validate and sanitize the `pipeline` parameter to only allow safe characters
- Consider using absolute paths and avoiding shell expansion entirely

**Status:** Requires input validation hardening

---

## High-Risk Findings

### H1. Insecure Randomness in Production Code

**Locations:**
- [session-slug.ts:104](src/agents/session-slug.ts#L104) - Session key generation
- [session-slug.ts:131](src/agents/session-slug.ts#L131) - Slug fallback
- [uuid.ts:26](ui/src/ui/uuid.ts#L26) - UUID generation for UI

**Description:** `Math.random()` is used for generating identifiers in production contexts:

```typescript
// session-slug.ts:131
const fallback = `${createSlugBase(3)}-${Math.random().toString(36).slice(2, 5)}`;

// uuid.ts:26
for (let i = 0; i < bytes.length; i++) bytes[i] = Math.floor(Math.random() * 256);
```

**Risk:** `Math.random()` is not cryptographically secure. Predictable session identifiers could allow session hijacking or identifier collision attacks.

**Mitigation:** Use `crypto.randomUUID()` or `crypto.randomBytes()` for all security-relevant identifiers:
```typescript
import crypto from "node:crypto";
const secureId = crypto.randomUUID();
```

**Note:** The pairing code generation in [pairing-store.ts:173-180](src/pairing/pairing-store.ts#L173-L180) correctly uses `crypto.randomInt()`.

**Status:** Should be fixed for session-related code

---

### H2. Subprocess Spawning Without Full Input Sanitization

**Locations:**
- [signal/daemon.ts:52](src/signal/daemon.ts#L52)
- [cli/dns-cli.ts:18,44](src/cli/dns-cli.ts#L18)
- [extensions/zalouser/src/zca.ts:33,95,172](extensions/zalouser/src/zca.ts)

**Description:** Multiple subprocess spawn calls pass user-controllable paths without validation:

```typescript
// signal/daemon.ts
const child = spawn(opts.cliPath, args, {
  stdio: ["ignore", "pipe", "pipe"],
});

// dns-cli.ts
const res = spawnSync("sudo", ["tee", filePath], {
  input: content,
});
```

**Risk:** If `cliPath` or `filePath` can be influenced by untrusted input, command injection or arbitrary file write may be possible.

**Mitigation:**
- Validate all paths against an allowlist of safe directories
- Use `path.resolve()` and verify the resolved path is within expected boundaries
- Never construct command arguments from user input without validation

**Status:** Requires code path analysis

---

### H3. Query Parameter Token Logging Warning

**Location:** [server-http.ts:86-91](src/gateway/server-http.ts#L86-L91)

**Description:** The code correctly warns about tokens in query parameters but still accepts them:

```typescript
if (fromQuery) {
  logHooks.warn(
    "Hook token provided via query parameter is deprecated for security reasons. " +
    "Tokens in URLs appear in logs, browser history, and referrer headers. ..."
  );
}
```

**Risk:** Tokens in URLs are logged in server access logs, proxy logs, and browser history, leading to credential leakage.

**Mitigation:** Consider rejecting query parameter tokens entirely after a deprecation period, or make it opt-in via config.

**Status:** Informational - deprecation warning is good practice

---

### H4. No Rate Limiting on Authentication Endpoints

**Description:** The gateway authentication does not implement rate limiting for failed authentication attempts.

**Risk:** Brute force attacks against token/password authentication are possible, especially when exposed via Tailscale Serve/Funnel.

**Mitigation:**
- Implement exponential backoff after failed attempts
- Add account lockout after N failed attempts
- Consider IP-based rate limiting

**Status:** Enhancement recommended

---

## Medium-Risk Findings

### M1. File Permission Model Relies on OS Enforcement

**Location:** [pairing-store.ts:97,102](src/pairing/pairing-store.ts#L97-L102)

**Description:** Credentials are written with restrictive permissions:

```typescript
await fs.promises.mkdir(dir, { recursive: true, mode: 0o700 });
await fs.promises.chmod(tmp, 0o600);
```

**Assessment:** This is good practice. However, Windows ACL enforcement differs from POSIX. The code includes Windows-specific ACL checks in [audit-fs.ts](src/security/audit-fs.ts).

**Status:** Adequate with existing audit checks

---

### M2. Environment Variable Substitution in Config

**Location:** [env-substitution.ts](src/config/env-substitution.ts)

**Description:** Config supports `${VAR_NAME}` syntax for environment variable injection. The pattern only matches uppercase variables with a strict regex.

**Assessment:** The implementation is reasonably secure:
- Only `[A-Z_][A-Z0-9_]*` patterns are substituted
- Missing vars throw errors rather than returning empty strings
- Escape syntax (`$${VAR}`) is supported

**Status:** Adequate

---

### M3. Credentials Stored on Filesystem

**Locations:**
- WhatsApp: `~/.openclaw/credentials/whatsapp/[account-id]/creds.json`
- OAuth: `~/.openclaw/credentials/[channel]-pairing.json`
- AllowFrom: `~/.openclaw/credentials/[channel]-allowFrom.json`

**Description:** Sensitive credentials are stored in JSON files on the filesystem.

**Risk:** If the user's home directory is compromised or backed up to cloud storage, credentials may leak.

**Mitigation:**
- The code already sets `0o600`/`0o700` permissions
- The security audit warns about synced folders (iCloud, Dropbox, etc.)
- Consider adding optional integration with system keychain (macOS Keychain, Windows Credential Manager)

**Status:** Adequate with existing warnings

---

### M4. Path Traversal Prevention in Channel Keys

**Location:** [pairing-store.ts:52-58](src/pairing/pairing-store.ts#L52-L58)

**Description:** Channel IDs are sanitized before use in file paths:

```typescript
function safeChannelKey(channel: PairingChannel): string {
  const raw = String(channel).trim().toLowerCase();
  if (!raw) throw new Error("invalid pairing channel");
  const safe = raw.replace(/[\\/:*?"<>|]/g, "_").replace(/\.\./g, "_");
  if (!safe || safe === "_") throw new Error("invalid pairing channel");
  return safe;
}
```

**Assessment:** This provides basic path traversal protection by removing `..` and special characters.

**Status:** Adequate

---

### M5. Control UI Exposed Without Device Auth Can Be Disabled

**Location:** [audit.ts:334-343](src/security/audit.ts#L334-L343)

**Description:** The config allows disabling device authentication for Control UI:

```typescript
if (cfg.gateway?.controlUi?.dangerouslyDisableDeviceAuth === true) {
  findings.push({
    checkId: "gateway.control_ui.device_auth_disabled",
    severity: "critical",
    title: "DANGEROUS: Control UI device auth disabled",
```

**Assessment:** The security audit correctly flags this as critical. The naming convention (`dangerouslyDisableDeviceAuth`) makes the risk clear.

**Status:** Adequate warning mechanism

---

### M6. Browser CDP Connection Over HTTP Warning

**Location:** [audit.ts:387-395](src/security/audit.ts#L387-L395)

**Description:** Remote Chrome DevTools Protocol connections over HTTP are flagged:

```typescript
if (url.protocol === "http:") {
  findings.push({
    checkId: "browser.remote_cdp_http",
    severity: "warn",
    title: "Remote CDP uses HTTP",
```

**Assessment:** CDP over HTTP exposes browser session tokens in plaintext. The warning is appropriate.

**Status:** Adequate warning mechanism

---

## Low-Risk Findings

### L1. Secrets Detection Baseline

**Location:** `.secrets.baseline`, `.detect-secrets.cfg`

**Description:** The project uses `detect-secrets` for automated secret detection in CI/CD.

**Assessment:** Good practice. Baseline helps prevent accidental credential commits.

**Status:** Good

---

### L2. Node.js Version Requirement

**Location:** [package.json:153](package.json#L153), [SECURITY.md:34-43](SECURITY.md#L34-L43)

**Description:** Requires Node.js 22.12.0+ which includes security patches:
- CVE-2025-59466: async_hooks DoS vulnerability
- CVE-2026-21636: Permission model bypass vulnerability

**Assessment:** Good practice enforcing secure runtime version.

**Status:** Good

---

### L3. Dependency Pinning and Overrides

**Location:** [package.json:244-254](package.json#L244-L254)

**Description:** Critical dependencies are pinned and overridden:

```json
"overrides": {
  "tar": "7.5.4"
},
"pnpm": {
  "minimumReleaseAge": 2880,
  "overrides": {
    "@sinclair/typebox": "0.34.47",
    "hono": "4.11.4",
    "tar": "7.5.4"
  }
}
```

**Assessment:** The `tar` package has had multiple security vulnerabilities. Pinning to a known-good version is appropriate. The `minimumReleaseAge` of 2880 minutes (48 hours) provides supply chain attack protection.

**Status:** Good

---

### L4. Timing-Safe Authentication

**Location:** [auth.ts:35-38](src/gateway/auth.ts#L35-L38)

**Description:** Gateway authentication uses timing-safe comparison:

```typescript
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  return timingSafeEqual(Buffer.from(a), Buffer.from(b));
}
```

**Assessment:** Correct implementation preventing timing attacks on token comparison.

**Status:** Good

---

### L5. Tailscale Identity Verification

**Location:** [auth.ts:134-165](src/gateway/auth.ts#L134-L165)

**Description:** Tailscale authentication verifies identity via whois lookup:

```typescript
async function resolveVerifiedTailscaleUser(params: {
  req?: IncomingMessage;
  tailscaleWhois: TailscaleWhoisLookup;
}): Promise<...>
```

**Assessment:** The code verifies that the claimed Tailscale identity matches the whois response, preventing header spoofing.

**Status:** Good

---

### L6. Request Body Size Limits

**Location:** [hooks.ts:10,31-34](src/gateway/hooks.ts#L10)

**Description:** Hook requests have configurable body size limits:

```typescript
const DEFAULT_HOOKS_MAX_BODY_BYTES = 256 * 1024;
const maxBodyBytes = cfg.hooks?.maxBodyBytes ?? DEFAULT_HOOKS_MAX_BODY_BYTES;
```

**Assessment:** Prevents memory exhaustion from large payloads.

**Status:** Good

---

### L7. Built-in Security Audit Command

**Location:** [audit.ts](src/security/audit.ts), [audit-extra.ts](src/security/audit-extra.ts)

**Description:** The `openclaw security audit` command performs comprehensive security checks:
- File system permissions
- Gateway authentication configuration
- Channel security policies
- Secrets in config files
- Synced folder detection
- Plugin trust verification

**Assessment:** Excellent self-assessment tooling.

**Status:** Good

---

### L8. File Locking for Concurrent Access

**Location:** [pairing-store.ts:114-133](src/pairing/pairing-store.ts#L114-L133)

**Description:** Uses `proper-lockfile` for concurrent file access:

```typescript
async function withFileLock<T>(
  filePath: string,
  fallback: unknown,
  fn: () => Promise<T>,
): Promise<T> {
  await ensureJsonFile(filePath, fallback);
  let release: (() => Promise<void>) | undefined;
  try {
    release = await lockfile.lock(filePath, PAIRING_STORE_LOCK_OPTIONS);
    return await fn();
  } finally { ... }
}
```

**Assessment:** Prevents race conditions in credential file updates.

**Status:** Good

---

## Recommendations

### Immediate Actions (Critical/High)

1. **Fix timing-safe comparison in hook handler** - Replace direct string comparison with `timingSafeEqual`

2. **Remove `shell: true` fallback** - Implement proper argument escaping for Windows instead of enabling shell mode

3. **Replace `Math.random()` in session code** - Use `crypto.randomUUID()` or `crypto.randomBytes()`

4. **Document browser automation trust boundary** - Clearly document that `fnText` must never come from untrusted input

### Short-term Improvements (Medium)

5. **Add rate limiting to authentication** - Implement exponential backoff for failed auth attempts

6. **Consider deprecating query parameter tokens** - Add a config option to reject tokens in URLs

7. **Add optional keychain integration** - Allow storing credentials in OS keychain instead of files

### Long-term Hardening

8. **Implement Content Security Policy** - For the Control UI web interface

9. **Add security headers** - X-Content-Type-Options, X-Frame-Options for HTTP responses

10. **Consider process sandboxing** - For browser automation and subprocess execution

---

## Positive Security Practices Observed

1. **Timing-safe token comparison** in gateway authentication
2. **Restrictive file permissions** (0o600/0o700) for credentials
3. **Path traversal prevention** in channel key sanitization
4. **Environment variable separation** from config files
5. **Comprehensive built-in security audit** command
6. **Secret detection** in CI/CD pipeline
7. **Dependency pinning** and minimum release age
8. **Node.js version enforcement** with security patches
9. **Clear security warnings** in config (e.g., `dangerouslyDisableDeviceAuth`)
10. **Tailscale identity verification** via whois

---

## Files Reviewed

### Core Security Files
- [src/gateway/auth.ts](src/gateway/auth.ts) - Gateway authentication
- [src/security/audit.ts](src/security/audit.ts) - Security audit framework
- [src/security/audit-extra.ts](src/security/audit-extra.ts) - Extended audit checks
- [src/pairing/pairing-store.ts](src/pairing/pairing-store.ts) - Credential storage

### HTTP/API Layer
- [src/gateway/server-http.ts](src/gateway/server-http.ts) - HTTP server
- [src/gateway/hooks.ts](src/gateway/hooks.ts) - Webhook handling

### Subprocess Execution
- [extensions/lobster/src/lobster-tool.ts](extensions/lobster/src/lobster-tool.ts)
- [src/signal/daemon.ts](src/signal/daemon.ts)
- [src/cli/dns-cli.ts](src/cli/dns-cli.ts)

### Browser Automation
- [src/browser/pw-tools-core.interactions.ts](src/browser/pw-tools-core.interactions.ts)

### Configuration
- [src/config/env-substitution.ts](src/config/env-substitution.ts)
- [SECURITY.md](SECURITY.md)
- [package.json](package.json)

---

## Conclusion

OpenClaw demonstrates a security-conscious development approach with several strong practices including timing-safe comparisons, proper file permissions, and comprehensive self-audit tooling. The critical findings around dynamic code execution and timing attacks in hook validation should be addressed promptly. The high-risk findings around insecure randomness and subprocess handling warrant attention in the next development cycle.

The built-in `openclaw security audit --deep` command provides excellent operational security guidance for deployments.
