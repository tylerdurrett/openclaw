# Native Applications

OpenClaw provides native companion apps for macOS, iOS, and Android that connect to the Gateway as nodes.

## Architecture Overview

```
                    GATEWAY (central broker)
                    |-- Handles pairing & auth
                    |-- Routes agent commands
                    |-- Manages chat sessions
                    +-- Canvas Host for UI
        +-----------+------------+------------+
        |           |            |            |
     macOS        iOS        Android      Browser
     Menu Bar     App          App        Control UI
     (Operator)   (Node)      (Node)
```

**Roles:**
- **Operator (macOS):** Controls agents, approves executions, configures gateway
- **Node (iOS/Android):** Exposes device capabilities (canvas, camera, location)

## Shared Libraries

### OpenClawKit (`apps/shared/OpenClawKit/`)

Swift Package shared by macOS and iOS:

| Target | Purpose |
|--------|---------|
| `OpenClawProtocol` | Gateway protocol models (auto-generated) |
| `OpenClawKit` | WebSocket, node session, TLS pinning |
| `OpenClawChatUI` | Chat UI components, markdown rendering |

### Protocol (v3)

**Connect Handshake:**
```
Client → Server:
  minProtocol, maxProtocol,
  client (id, displayName, version, platform),
  caps, commands, permissions,
  role, scopes

Server → Client:
  HelloOk (protocol version, server info, snapshot, canvasHostUrl)
```

**Request/Response RPC:**
```typescript
// Request
{ type: "request", id: UUID, method: string, params?: object }

// Response
{ type: "response", id: UUID, ok: boolean, result?: object, error?: object }
```

**Push Events:**
```typescript
{ type: "push", event: string, payload?: object }
// Events: snapshot, chat, canvas, camera, screen, node.invoke, talk, health
```

## macOS App

**Type:** Menu bar companion + Gateway host manager
**Language:** Swift (SwiftUI)
**Location:** `apps/macos/`

### Components

| Component | Purpose |
|-----------|---------|
| `AppState` | Central observable state machine |
| `GatewayConnection` | WebSocket lifecycle |
| `GatewayProcessManager` | Local gateway process |
| `LaunchAgentManager` | launchd integration |
| `PermissionManager` | TCC permission tracking |

### Features

- **Menu bar icon** with status pills
- **Settings window** for channels, instances, sessions, skills
- **Canvas windows** with WebKit rendering
- **Voice wake overlay** controller
- **Agent workspace** for event inspection
- **Screen record + camera capture**

### Node Capabilities

| Capability | Methods |
|------------|---------|
| Canvas | present, hide, navigate, eval, snapshot, A2UI |
| Camera | snap, clip |
| Screen | record |
| System | notify, run (gated by exec approvals) |
| Voice | wake detection, TalkMode |

### Gateway Communication

```swift
// Connect options
role: "operator"
scopes: ["operator.admin", "operator.approvals", "operator.pairing"]
```

### Development

```bash
# Dev builds
./scripts/restart-mac.sh

# Package
./scripts/package-mac-app.sh

# Code signing
# Ad-hoc or Developer ID, Apple Distribution
```

## iOS App

**Type:** Node companion app
**Language:** Swift (SwiftUI)
**Location:** `apps/ios/`

### Components

| Component | Purpose |
|-----------|---------|
| `NodeAppModel` | Main state container |
| `GatewayConnectionController` | Discovery + connection |
| `GatewayDiscoveryModel` | Bonjour discovery |
| `CanvasController` | WKWebView canvas |
| `CameraManager` | Photo/video capture |

### Node Capabilities

| Capability | Methods |
|------------|---------|
| Canvas | navigate, eval, snapshot |
| Camera | snap (photo), clip (video) |
| Screen | snapshot |
| Location | GPS (precise/coarse) |
| Voice | wake, TalkMode |
| Chat | persistent session on "main" |

### Gateway Communication

```swift
// Connect options
role: "node"
clientMode: "node"
caps: ["canvas", "camera", "location", ...]  // Dynamic
commands: ["canvas.*", "camera.*", ...]       // Dynamic
```

### Permissions

| Permission | Purpose |
|------------|---------|
| Camera | Photo/video capture |
| Microphone | Video audio, voice |
| Location | GPS tracking |
| Screen Recording | iOS 17+ |

### Development

```bash
# Generate Xcode project
xcodegen generate

# Build with fastlane
fastlane ios build
```

## Android App

**Type:** Node companion app
**Language:** Kotlin (Jetpack Compose)
**Location:** `apps/android/`
**Min SDK:** 31 (Android 12)

### Components

| Component | Purpose |
|-----------|---------|
| `NodeRuntime` | Gateway + services |
| `MainViewModel` | UI state |
| `GatewaySession` | WebSocket client |
| `CameraManager` | Photo/video |
| `ScreenRecorder` | Screen capture |

### Node Capabilities

| Capability | Methods |
|------------|---------|
| Canvas | navigate, eval, snapshot (WebView) |
| Camera | list, snap (jpg), clip (mp4) |
| Screen | record (mp4) |
| Location | get (fine/coarse) |
| Voice | wake, TalkMode |
| Chat | persistent session on "main" |
| SMS | send (if enabled) |

### Foreground Service

Required to keep WebSocket alive in background:

```kotlin
// Android 13+
Manifest.permission.POST_NOTIFICATIONS

// Notification includes Disconnect action
```

### Discovery

| Method | Requirements |
|--------|--------------|
| NSD (mDNS) | `_openclaw-gw._tcp` |
| Android 13+ | `NEARBY_WIFI_DEVICES` |
| Android 12- | `ACCESS_FINE_LOCATION` |
| Manual | Host/port entry |

### Development

```bash
# Build
./gradlew :app:assembleDebug

# Install
./gradlew :app:installDebug

# Test
./gradlew :app:testDebugUnitTest
```

## Gateway Protocol

### Ports

| Port | Purpose |
|------|---------|
| 18789 | WebSocket (WS) |
| 18790 | WebSocket Secure (WSS) |
| 18793 | Canvas Host |

### TLS

- Optional but supported
- TOFU (Trust-On-First-Use) with pinning store
- Certificate fingerprint validation

### Discovery

| Platform | Method |
|----------|--------|
| macOS/iOS | Bonjour (mDNS) |
| Android | NSD (Network Service Discovery) |
| Wide-Area | DNS-SD with Tailscale |
| Fallback | Manual host/port |

## Session Management

All apps share the same session key:

```
Session key: "main"
```

This enables:
- Cross-device chat continuity
- Shared conversation history
- Unified notifications

## Capability Negotiation

On connect, nodes declare:

```typescript
interface ConnectParams {
  caps: string[];        // ["canvas", "camera", "location"]
  commands: string[];    // ["canvas.*", "camera.snap"]
  permissions: {         // Platform permission state
    camera: "granted" | "denied" | "unknown";
    microphone: "granted" | "denied" | "unknown";
    location: "granted" | "denied" | "unknown";
  };
}
```

Gateway uses this to:
- Route requests to capable nodes
- Skip unsupported features
- Guide permission prompts

## Authentication

| Method | Description |
|--------|-------------|
| Device token | Pairing-based, Keychain stored |
| Shared token | Config-based token |
| Password | Simple password auth |

Storage:
- macOS/iOS: Keychain
- Android: SharedPreferences (encrypted)

## Lifecycle

### macOS

- Always active (menu bar persistent)
- Can host local gateway
- Manages launchd integration

### iOS

- Pauses discovery in background
- Canvas/camera only work foreground
- Voice wake can run background

### Android

- Foreground service keeps WebSocket alive
- Notification with disconnect action
- Auto-reconnect on network change

## Key Files

| Component | Path |
|-----------|------|
| macOS App | `apps/macos/Sources/OpenClaw/` |
| iOS App | `apps/ios/Sources/` |
| Android App | `apps/android/app/src/main/java/ai/openclaw/` |
| Shared Kit | `apps/shared/OpenClawKit/Sources/` |
| Protocol | `OpenClawProtocol/GatewayModels.swift` |
