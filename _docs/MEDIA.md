# Media Pipeline

OpenClaw's media pipeline handles image, audio, video, and document processing with multi-provider understanding capabilities.

## Overview

The media pipeline provides:
- Local media storage in `~/.openclaw/media/`
- MIME type detection and validation
- Image processing (resize, format conversion, EXIF handling)
- Audio/video transcription
- Document text extraction (PDF, Office)
- Media understanding via AI providers

## Key Files

| File | Purpose |
|------|---------|
| `src/media/store.ts` | Media storage management |
| `src/media/mime.ts` | MIME type detection |
| `src/media/image-ops.ts` | Image processing |
| `src/media/fetch.ts` | Remote media downloads |
| `src/media/input-files.ts` | Document text extraction |
| `src/media/parse.ts` | Agent output media parsing |
| `src/media-understanding/` | AI-powered media analysis |

## Media Storage

### Limits

| Type | Max Size |
|------|----------|
| Images | 6 MB |
| Audio | 16 MB |
| Video | 16 MB |
| Documents | 100 MB |

Default TTL: 2 minutes for temporary storage.

### Storage Functions

```typescript
// Store from buffer
saveMediaBuffer({
  buffer: Buffer,
  filename?: string,
  mimeType?: string,
  ttl?: number
}): Promise<{ path: string; mimeType: string }>;

// Store from URL
saveMediaSource({
  url: string,
  maxBytes?: number,
  timeout?: number
}): Promise<{ path: string; mimeType: string }>;

// Ensure directory exists
ensureMediaDir(): Promise<void>;
```

### Filename Sanitization

- Cross-platform safe (Windows/SharePoint compatible)
- Pattern: `{sanitized-name}---{uuid}.{ext}`
- Preserves original filename for display

## MIME Type Detection

### Detection Strategy

1. Binary sniffing using `file-type` library
2. File extension mapping
3. HTTP Content-Type headers
4. Smart fallback for container conflicts (XLSX vs ZIP)

### Supported Types

**Images**: JPEG, PNG, GIF, WebP, HEIC, HEIF

**Audio**: MP3, OGG, Opus, M4A, WAV, FLAC, AAC

**Video**: MP4, MOV, WebM

**Documents**: PDF, TXT, MD, JSON, CSV, Office formats

### Audio Format Detection

```typescript
// Detect voice-compatible audio
isVoiceCompatibleAudio(mimeType: string): boolean;
// OGG, Opus formats return true
```

## Image Processing

### Backends

| Backend | Environment | Notes |
|---------|-------------|-------|
| Sharp | Default | Native library for Linux/macOS |
| SIPS | macOS | Better Bun compatibility |

### Capabilities

#### EXIF Orientation

- Reads JPEG EXIF metadata
- Automatic rotation (8 orientations)
- Normalizes before resize

#### Resizing

```typescript
// Resize to JPEG
resizeToJpeg({
  input: Buffer,
  width?: number,
  height?: number,
  quality?: number,  // 1-100
  withoutEnlargement?: boolean
}): Promise<Buffer>;

// Resize to PNG
resizeToPng({
  input: Buffer,
  width?: number,
  height?: number,
  compressionLevel?: number
}): Promise<Buffer>;
```

#### Format Conversion

- HEIC/HEIF to JPEG
- PNG to JPEG (when size exceeds limits)
- Alpha channel preservation for PNG

#### Optimization

```typescript
optimizeImageToPng({
  input: Buffer,
  maxBytes: number
}): Promise<Buffer>;

// Grid search:
// - Sizes: 2048, 1536, 1280, 1024, 800px
// - Compression levels: 6-9
// - Selects smallest under byte limit
```

## Media Fetching

```typescript
fetchMedia({
  url: string,
  maxBytes?: number,    // Default 5 MB
  timeout?: number
}): Promise<{
  buffer: Buffer,
  mimeType: string,
  filename?: string
}>;
```

Features:
- HTTP/HTTPS with redirect following (up to 5)
- Filename from Content-Disposition header
- RFC 2231 filename encoding support
- Progressive size checking during download

## Document Extraction

### Supported Formats

| Format | Extraction |
|--------|------------|
| TXT, MD | Direct text |
| CSV, JSON, XML | Direct text |
| PDF | Text + optional image rendering |
| Office | Text extraction |
| Base64 | Decode + process |

### PDF Processing

```typescript
extractPdfContent({
  buffer: Buffer,
  maxPages?: number,          // Default 4
  maxChars?: number,          // Default 200k
  minTextChars?: number,      // Before image fallback
  maxPixels?: number          // Canvas rendering budget
}): Promise<{
  text: string,
  images?: Buffer[]
}>;
```

Features:
- Text extraction (up to 4 pages default)
- Image rendering when text content is low
- Canvas-based PDF rendering (lazy-loaded)

### Limits

| Setting | Default |
|---------|---------|
| Max chars | 200k per file |
| Max file size | 5 MB |
| PDF pages | 4 |
| PDF min text | 200 chars |
| PDF max pixels | 4M |

## Media Understanding

### Provider Support

| Provider | Image | Audio | Video |
|----------|-------|-------|-------|
| OpenAI | Vision | Transcription | - |
| Anthropic | Vision | - | - |
| Google | Vision | Transcription | Description |
| Groq | - | Whisper | - |
| Deepgram | - | Transcription | - |
| MiniMax | VL-01 | - | - |

### Capabilities

#### Image Description

```typescript
describeImage({
  buffer: Buffer,
  prompt?: string,
  model?: string
}): Promise<string>;
```

Uses vision models (Claude, GPT, Gemini).

#### Audio Transcription

```typescript
transcribeAudio({
  buffer: Buffer,
  language?: string,
  model?: string
}): Promise<string>;
```

Default models:
- Groq: `whisper-large-v3-turbo`
- OpenAI: `gpt-4o-mini-transcribe`
- Deepgram: `nova-3`

#### Video Description

```typescript
describeVideo({
  buffer: Buffer,
  prompt?: string
}): Promise<string>;
```

Currently limited to Google provider.

### Processing Architecture

#### Attachment Normalization

```typescript
normalizeAttachments(ctx: MsgContext): MediaAttachment[];

// Extracts from:
// - MediaPaths (local files)
// - MediaUrls (remote URLs)
// - MediaTypes (MIME hints)
```

#### Concurrent Processing

Default: 2 concurrent media operations (configurable).

```typescript
interface MediaUnderstandingConfig {
  concurrency?: number;  // Default 2
}
```

#### Scope-Based Control

```typescript
// Per-agent capability checking
checkMediaScope(agentId: string, capability: string): boolean;
```

### Output Integration

Results embedded in message context:

```typescript
interface MsgContext {
  MediaUnderstanding?: MediaUnderstanding[];
  MediaUnderstandingDecisions?: Decision[];
  Transcript?: string;
  Body?: string;  // Enriched with file blocks
}
```

## Agent Media Output

### MEDIA Token

Agents can output media references:

```
MEDIA: ./path/to/file.png
MEDIA: "path with spaces"
MEDIA: https://example.com/image.jpg
```

### Parsing

```typescript
parseMediaFromOutput(text: string): {
  text: string,              // Cleaned text
  mediaUrls: string[],       // Extracted URLs
  audioAsVoice: boolean      // [[audio_as_voice]] directive
}
```

### Validation

- Only relative paths (`./`) allowed
- Directory traversal blocked (`..`)
- URLs validated (HTTP/HTTPS only)
- Fenced code blocks excluded

### Audio Voice Tag

```
[[audio_as_voice]]
MEDIA: ./voice.ogg
```

Sends audio as voice message instead of file.

## Media Server

Express-based server for media URLs:

```typescript
// Endpoint
GET /media/:id

// Features
- TTL-based cleanup (2 minutes)
- Single-use file deletion
- MIME type detection
- Size/expiration checks
```

### Hosting

```typescript
interface MediaHostConfig {
  port: number;              // Default 42873
  hostname?: string;         // From Tailscale
}

// Returns URLs like:
// https://{hostname}/media/{id}
```

Requires webhook/Funnel server or `--serve-media` flag.

## Channel-Specific Handling

### Web/WhatsApp

```typescript
// HEIC/HEIF auto-conversion
processInboundImage(buffer: Buffer): Promise<Buffer>;

// Optimization
// - PNG alpha preservation
// - JPEG fallback if PNG exceeds limit
// - Size enforcement with fallback resizing
```

### Telegram

- Downloads via Telegram API
- Stores with metadata

### Discord/Slack

- Downloads from signed URLs
- Respects attachment limits

## Configuration

```json5
{
  gateway: {
    http: {
      endpoints: {
        responses: {
          files: {
            allowUrl: true,
            allowedMimes: ["image/*", "audio/*", "video/*"],
            maxBytes: 5242880,  // 5 MB
            maxChars: 200000,
            pdf: {
              maxPages: 4,
              maxPixels: 4000000,
              minTextChars: 200
            }
          }
        }
      }
    }
  }
}
```

## Design Patterns

1. **Lazy Loading**: Optional deps (Canvas, PDF.js) load on demand
2. **Dual Backends**: Sharp + SIPS for macOS compatibility
3. **Progressive Validation**: Size checks during download
4. **Provider Registry**: Pluggable media understanding
5. **Concurrent Processing**: Configurable parallelism
6. **Scope-Based Gating**: Per-agent capability control
7. **Error Recovery**: Fallback formats (HEIC→JPEG, PNG→JPEG)
8. **Temporary Storage**: TTL-based cleanup for privacy

## Performance

| Operation | Limit | Notes |
|-----------|-------|-------|
| File size | 5 MB | Most operations |
| TTL | 2 min | Temporary files |
| Concurrency | 2 | Media operations |
| PNG optimization | 20 variants | Size × compression |
| Image resize | No enlarge | Prevents quality loss |
