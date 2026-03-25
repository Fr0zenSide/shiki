---
title: "AIKit — Shared Model-Agnostic AI Package"
status: draft
priority: P0
project: shiki
created: 2026-03-25
references: "Superwhisper (modes + model library), LM Studio (runtime engines + model browser + MCP)"
---

# AIKit — Shared Model-Agnostic AI Package

## Vision

AIKit is the **universal AI runtime layer** for all Shiki projects. Like CoreKit is for DI/logging and NetKit is for networking, AIKit is for AI — LLM inference, model management, provider routing, and MCP integration. Every app (Brainy, Flsh, WabiSabi, Maya) imports AIKit instead of talking to models directly.

**Core principle**: If a better model appears tomorrow, you swap it in settings. Zero code changes.

## Architecture

```
┌─────────────────────────────────────────────┐
│                   App Layer                  │
│  Brainy · Flsh · WabiSabi · Maya · Shikki   │
├─────────────────────────────────────────────┤
│                    AIKit                     │
│  ┌──────────┐ ┌──────────┐ ┌─────────────┐ │
│  │ Provider  │ │  Model   │ │  Language   │ │
│  │ Protocol  │ │ Registry │ │ Preferences │ │
│  └────┬─────┘ └────┬─────┘ └──────┬──────┘ │
│       │            │               │         │
│  ┌────┴────────────┴───────────────┴──────┐ │
│  │           Runtime Engine Layer          │ │
│  ├────────┬─────────┬────────┬────────────┤ │
│  │ CoreML │  MLX    │ Ollama │  HTTP API  │ │
│  │ (M1+)  │ (M1+)  │(Linux) │(OpenAI/    │ │
│  │        │        │        │ Claude/etc) │ │
│  ├────────┴─────────┴────────┴────────────┤ │
│  │              MCP Client                │ │
│  │  (Koharu, LM Studio, custom servers)   │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

## Core Protocols

### 1. AIProvider (replaces AIService)

```swift
/// Universal AI provider — any model, any backend.
public protocol AIProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var capabilities: AICapabilities { get }
    var status: AIProviderStatus { get async }

    func complete(request: AIRequest) async throws -> AIResponse
    func stream(request: AIRequest) async throws -> AsyncThrowingStream<AIChunk, Error>
}

public struct AICapabilities: OptionSet, Sendable, Codable {
    static let textGeneration  = AICapabilities(rawValue: 1 << 0)
    static let translation     = AICapabilities(rawValue: 1 << 1)
    static let ocr             = AICapabilities(rawValue: 1 << 2)
    static let imageGeneration = AICapabilities(rawValue: 1 << 3)
    static let voiceToText     = AICapabilities(rawValue: 1 << 4)
    static let textToVoice     = AICapabilities(rawValue: 1 << 5)
    static let inpainting      = AICapabilities(rawValue: 1 << 6)
    static let embedding       = AICapabilities(rawValue: 1 << 7)
    static let vision          = AICapabilities(rawValue: 1 << 8)
    static let toolUse         = AICapabilities(rawValue: 1 << 9)
}

public enum AIProviderStatus: Sendable {
    case ready
    case loading(progress: Double)
    case downloading(progress: Double, totalBytes: Int64)
    case error(String)
    case unavailable
}
```

### 2. AIRequest / AIResponse

```swift
public struct AIRequest: Sendable {
    public var messages: [AIMessage]
    public var systemPrompt: String?
    public var temperature: Double
    public var maxTokens: Int
    public var model: ModelIdentifier?  // nil = use provider default
    public var tools: [AITool]?         // for tool use / function calling
    public var responseFormat: ResponseFormat?  // json, text
}

public struct AIMessage: Sendable, Codable {
    public enum Role: String, Sendable, Codable { case system, user, assistant, tool }
    public var role: Role
    public var content: String
    public var images: [Data]?  // for vision models
}

public struct AIResponse: Sendable {
    public var content: String
    public var model: String
    public var tokensUsed: TokenUsage
    public var latencyMs: Int
    public var toolCalls: [AIToolCall]?
}

public struct TokenUsage: Sendable, Codable {
    public var prompt: Int
    public var completion: Int
    public var total: Int
}
```

### 3. ModelRegistry — The Model Library

```swift
/// Discovers, downloads, and manages AI models.
public protocol ModelRegistry: Sendable {
    /// List all known models (local + available for download).
    func listModels(filter: ModelFilter?) async throws -> [ModelDescriptor]

    /// Get a specific model by ID.
    func getModel(id: ModelIdentifier) async throws -> ModelDescriptor

    /// Download a model to local storage.
    func download(id: ModelIdentifier, onProgress: @escaping (Double) -> Void) async throws

    /// Delete a local model.
    func deleteLocal(id: ModelIdentifier) async throws

    /// Search HuggingFace / model registries.
    func search(query: String, format: ModelFormat?) async throws -> [ModelDescriptor]
}

public struct ModelDescriptor: Sendable, Codable, Identifiable {
    public let id: ModelIdentifier
    public var name: String
    public var author: String
    public var description: String
    public var capabilities: AICapabilities
    public var format: ModelFormat          // .gguf, .mlx, .coreml, .safetensors
    public var parameters: String           // "4B", "7B", "30B"
    public var quantization: String?        // "Q8_0", "4bit", etc.
    public var sizeBytes: Int64
    public var architecture: String         // "llama", "qwen", "mistral"
    public var domain: ModelDomain          // .llm, .embedding, .voice, .vision
    public var isLocal: Bool                // downloaded to disk
    public var localPath: URL?
    public var huggingFaceId: String?       // "nvidia/nemotron-3-nano-4b"
    public var tags: [String]               // ["staff-pick", "new"]
    public var downloadCount: Int?
    public var updatedAt: Date?

    /// Performance stats per usage context (populated over time)
    public var performanceStats: [UsageContext: PerformanceStat]
}

public struct ModelIdentifier: Sendable, Codable, Hashable {
    public var provider: String   // "lmstudio", "ollama", "huggingface", "openai"
    public var modelId: String    // "nvidia/nemotron-3-nano-4b" or "gpt-5.4-mini"
}

public enum ModelFormat: String, Sendable, Codable {
    case gguf, mlx, coreml, safetensors, api  // api = remote, no file
}

public enum ModelDomain: String, Sendable, Codable {
    case llm, embedding, voice, vision, inpainting
}
```

### 4. PerformanceTracker — Augmented Context

```swift
/// Tracks model performance per usage context across sessions.
public struct UsageContext: Sendable, Codable, Hashable {
    public var app: String          // "brainy", "flsh"
    public var task: String         // "manga-translation", "article-summary", "voice-note"
    public var inputLanguage: String?
    public var outputLanguage: String?
}

public struct PerformanceStat: Sendable, Codable {
    public var avgLatencyMs: Int
    public var avgTokensPerSecond: Double
    public var qualityScore: Double?       // User-rated or automated (0-10)
    public var totalInvocations: Int
    public var lastUsedAt: Date
}
```

### 5. RuntimeEngine — The Backend Layer

```swift
/// A runtime that can load and run models.
public protocol RuntimeEngine: Sendable {
    var id: String { get }
    var displayName: String { get }
    var supportedFormats: [ModelFormat] { get }

    /// Check if this engine is available on the current platform.
    var isAvailable: Bool { get }

    /// Load a model and return a provider.
    func loadModel(_ descriptor: ModelDescriptor) async throws -> any AIProvider

    /// Unload a model from memory.
    func unloadModel(_ id: ModelIdentifier) async throws

    /// List currently loaded models.
    func loadedModels() -> [ModelIdentifier]
}
```

**Implementations planned:**

| Engine | Format | Platform | Notes |
|---|---|---|---|
| `CoreMLEngine` | .coreml | macOS/iOS (M1+) | Neural Engine, ANE acceleration |
| `MLXEngine` | .mlx | macOS (M1+) | Apple MLX, fast local inference |
| `LlamaCppEngine` | .gguf | macOS/Linux | Metal acceleration on macOS |
| `OllamaEngine` | .gguf | Any (HTTP) | Linux fallback, self-hosted |
| `OpenAIEngine` | .api | Any | GPT-5.x, remote |
| `AnthropicEngine` | .api | Any | Claude, remote |
| `GeminiEngine` | .api | Any | Google, remote |
| `LMStudioEngine` | .api | LAN | OpenAI-compatible, local server |
| `MCPEngine` | .api | Any | Koharu, custom MCP servers |

### 6. MediaLanguagePreferences

```swift
/// Per-media-type language preferences.
/// "I read manga in FR, articles in EN, watch anime in JP+FR sub"
public struct MediaLanguagePreferences: Sendable, Codable {
    public var profiles: [MediaProfile]
    public var defaultSourceBehavior: SourceBehavior  // .keepOriginal or .translate

    public init() {
        profiles = []
        defaultSourceBehavior = .keepOriginal  // VO first, always
    }
}

public struct MediaProfile: Sendable, Codable, Identifiable {
    public let id: String
    public var mediaType: MediaType
    public var sourceBehavior: SourceBehavior
    /// Preferred consumption language (for translation target).
    public var preferredLanguage: String     // "fr", "en"
    /// Acceptable source languages (content you can read/watch without translation).
    public var acceptedSourceLanguages: [String]  // ["fr", "en"]
    /// Subtitle language when source is foreign.
    public var subtitleLanguage: String?     // "fr"
    /// Whether auto-translate is enabled for this media type.
    public var autoTranslate: Bool           // false by default — opt-in
    /// Quality threshold: skip translation if below this quality score.
    public var qualityThreshold: Double?     // e.g. 0.8 — prefer no translation over bad translation
}

public enum MediaType: String, Sendable, Codable, CaseIterable {
    case manga
    case manhwa
    case bd            // bande dessinée (French comics)
    case article
    case book
    case anime
    case series
    case movie
    case youtube
    case podcast
}

public enum SourceBehavior: String, Sendable, Codable {
    /// Always show original (VO). Translation is manual opt-in.
    case keepOriginal
    /// Auto-translate to preferred language.
    case autoTranslate
    /// Show original + translation side by side.
    case sideBySide
}
```

**Example configuration (user's actual preferences):**

```swift
let prefs = MediaLanguagePreferences(profiles: [
    MediaProfile(
        mediaType: .manga,
        sourceBehavior: .autoTranslate,  // manga in FR
        preferredLanguage: "fr",
        acceptedSourceLanguages: ["fr"],
        autoTranslate: true,
        qualityThreshold: 0.8  // only if quality is high
    ),
    MediaProfile(
        mediaType: .article,
        sourceBehavior: .keepOriginal,   // articles in VO
        preferredLanguage: "en",
        acceptedSourceLanguages: ["fr", "en"],
        autoTranslate: false  // magic button, not default
    ),
    MediaProfile(
        mediaType: .anime,
        sourceBehavior: .keepOriginal,   // JP VO + FR sub
        preferredLanguage: "ja",         // source = JP
        acceptedSourceLanguages: ["ja", "fr", "en"],
        subtitleLanguage: "fr"
    ),
    MediaProfile(
        mediaType: .youtube,
        sourceBehavior: .keepOriginal,
        preferredLanguage: "en",
        acceptedSourceLanguages: ["en", "fr"],
        subtitleLanguage: "fr",          // only if needed
        autoTranslate: false
    ),
])
```

### 7. ProviderRouter — Smart Dispatch

```swift
/// Routes AI requests to the best available provider.
public struct ProviderRouter: Sendable {
    /// Select best provider for a given task.
    func route(
        request: AIRequest,
        context: UsageContext,
        preferences: ProviderPreferences
    ) async throws -> any AIProvider

    /// Fallback chain: try providers in order until one succeeds.
    func routeWithFallback(
        request: AIRequest,
        providers: [any AIProvider]
    ) async throws -> AIResponse
}

public struct ProviderPreferences: Sendable, Codable {
    /// Prefer local models over API.
    public var preferLocal: Bool = true
    /// Maximum acceptable latency (ms). 0 = no limit.
    public var maxLatencyMs: Int = 0
    /// Budget: max cost per request (USD). 0 = free only.
    public var maxCostPerRequest: Double = 0
    /// Required capabilities.
    public var requiredCapabilities: AICapabilities = []
}
```

## Package Structure

```
packages/AIKit/
├── Package.swift
├── Sources/AIKit/
│   ├── Protocols/
│   │   ├── AIProvider.swift
│   │   ├── RuntimeEngine.swift
│   │   ├── ModelRegistry.swift
│   │   └── ProviderRouter.swift
│   ├── Models/
│   │   ├── AIRequest.swift
│   │   ├── AIResponse.swift
│   │   ├── ModelDescriptor.swift
│   │   ├── AICapabilities.swift
│   │   ├── PerformanceTracker.swift
│   │   └── MediaLanguagePreferences.swift
│   ├── Engines/
│   │   ├── LMStudioEngine.swift       (OpenAI-compatible, NetKit)
│   │   ├── OllamaEngine.swift         (HTTP, Linux fallback)
│   │   ├── OpenAIEngine.swift         (GPT-5.x)
│   │   ├── AnthropicEngine.swift      (Claude)
│   │   ├── MCPEngine.swift            (generic MCP client)
│   │   └── CoreMLEngine.swift         (#if canImport(CoreML))
│   ├── Registry/
│   │   ├── HuggingFaceRegistry.swift  (browse + download models)
│   │   ├── LocalModelStore.swift      (track downloaded models)
│   │   └── ModelDownloader.swift      (async download with progress)
│   └── Mocks/
│       ├── MockAIProvider.swift
│       ├── MockModelRegistry.swift
│       └── MockRuntimeEngine.swift
└── Tests/AIKitTests/
    ├── AIProviderTests.swift
    ├── ProviderRouterTests.swift
    ├── ModelDescriptorTests.swift
    ├── MediaLanguagePreferencesTests.swift
    └── PerformanceTrackerTests.swift
```

## Dependencies

- **NetKit** (HTTP for API engines, model downloads)
- **CoreKit** (CacheRepository for model metadata, AppLog)
- **DataKit** (performance stats persistence)
- Optional: `CoreML` (via `#if canImport`)
- Optional: `MLX` (via conditional dependency or shell-out)

## Implementation Waves

### Wave 1 — Core Protocols + Models (~600 LOC, 20 tests)
AIProvider, AIRequest/Response, ModelDescriptor, AICapabilities, ProviderStatus

### Wave 2 — LM Studio + OpenAI Engines (~400 LOC, 15 tests)
LMStudioEngine (reuses Brainy's LocalAIService pattern), OpenAIEngine, streaming support

### Wave 3 — Model Registry + HuggingFace (~500 LOC, 15 tests)
HuggingFaceRegistry, LocalModelStore, ModelDownloader with progress

### Wave 4 — Media Language Preferences (~300 LOC, 15 tests)
MediaLanguagePreferences model, MediaProfile, SourceBehavior logic

### Wave 5 — Performance Tracker + Router (~400 LOC, 15 tests)
UsageContext, PerformanceStat, ProviderRouter with fallback chain

### Wave 6 — MCP Engine + Ollama (~300 LOC, 10 tests)
MCPEngine (generic MCP client for Koharu/custom), OllamaEngine (Linux)

### Wave 7 — CoreML/MLX Engine (~300 LOC, 10 tests)
CoreMLEngine (#if canImport), MLX integration exploration

**Total: ~2,800 LOC, ~100 tests, 7 waves**

## Migration Path

1. Brainy's `AIService` → wraps `AIProvider` (backward-compatible)
2. Flsh's `Transcriber` → `AIProvider` with `.voiceToText` capability
3. ShikiCore's `AgentProvider` → routes through `ProviderRouter`
4. All apps share the same model downloads directory (`~/.aikit/models/`)

## Relationship to Existing Packages

| Package | Role | AIKit relationship |
|---|---|---|
| CoreKit | DI, logging, cache | AIKit uses for caching model metadata |
| NetKit | HTTP, WebSocket | AIKit uses for API engines + model download |
| DataKit | Local storage | AIKit uses for performance stats |
| SecurityKit | Keychain | AIKit uses for API key storage |
| ShikiCore | Agent orchestration | ShikiCore uses AIKit's ProviderRouter |
| **AIKit** | **AI runtime** | **The missing piece** |
