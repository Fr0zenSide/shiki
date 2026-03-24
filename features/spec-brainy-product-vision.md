# Brainy — Full Product Spec

> **Author**: @shi (full team)
> **Date**: 2026-03-24
> **Status**: Ready for @Daimyo review
> **Repo**: `projects/brainy/`
> **License**: AGPL-3.0 (OBYW.one)

---

## 1. What Is Brainy?

Brainy is a **personal data sovereignty server**. Not a reader app — a protocol inversion.

**Today:** Companies own your data. You are the client. They are the server.
**Brainy:** You own your data. You are the server. Companies are the client.

Brainy is a local MCP server that holds YOUR consumption data (preferences, reading/watching/listening stats, browsing history) in an encrypted vault. Companies (Spotify, Netflix, YouTube, any platform) connect as MCP clients to personalize their service — but only with your permission, only the data you choose to share, revocable in one click.

"C'est donnant donnant" — companies share the stats they've built on you back INTO your vault. You get richer data. They get better personalization. Fair exchange. Break the deal? `brainy revoke spotify --delete-remote` sends an automated GDPR deletion request.

It also replaces Pocket, Raindrop, Infuse, browser bookmarks, YouTube playlists, manga readers, and podcast apps. Everything you consume, track, and remember — in one local-first, AI-augmented system.

**Core principle**: My data, my knowledge, my media, my reading list. My culture is not your marketing. One encrypted vault. Privacy first. No GAFAM.

### Replaces

| Product | Brainy Feature |
|---------|---------------|
| Pocket / Raindrop | Link vault + read-it-later + collections |
| Infuse / VLC | Video player with metadata + tracking |
| Aidoku / Suwatte | Manga/manhwa reader with source plugins |
| YouTube playlists | Video collection + offline download + tracking |
| Spotify playlists | Audio collection (local mirror) |
| Browser tabs | Link vault + personal search engine |
| Trakt / Simkl | Movie/series/anime watch tracker |
| Overcast / Pocket Casts | Podcast player + offline cache |

---

## 2. Architecture

### 2.1 Package Structure

```
brainy/
├── Package.swift
├── Sources/
│   ├── BrainyCore/           ← SPM library — shared across ALL targets
│   │   ├── Models/           ← Unified media types, entities
│   │   ├── Storage/          ← libSQL layer (vault, migrations, queries)
│   │   ├── Sources/          ← BrainySource protocol + built-in sources
│   │   ├── Sync/             ← P2P sync engine (v1.0)
│   │   └── AI/               ← Local LLM interface (v0.3)
│   │
│   ├── Brainy/               ← CLI executable (RSS reader, vault management)
│   ├── BrainyTube/           ← macOS GUI — video player (exists today)
│   ├── BrainyReader/         ← macOS GUI — manga/book reader (v0.2)
│   ├── BrainyMCP/            ← MCP server — data sovereignty protocol (v0.1 CORE)
│   ├── BrainyApp/            ← macOS GUI — unified shell (v0.3+)
│   └── BrainyDaemon/         ← Background sync/ingest daemon (v0.2)
│
├── Tests/
│   ├── BrainyCoreTests/      ← Core logic, models, storage, sources
│   ├── BrainyTests/          ← CLI tests (exists today)
│   └── BrainyTubeTests/      ← Video player tests (BrainyTube spec)
│
└── Plugins/                  ← Community source plugins (v0.2+)
    ├── MangaSources/
    └── AudioSources/
```

### 2.2 BrainyCore — The Engine

BrainyCore is the single SPM library that ALL executables depend on. It owns:

- **Data models** — unified `MediaItem` hierarchy for all 7 media types
- **Storage** — libSQL database (encrypted vault), migrations, raw SQL queries
- **Source protocol** — `BrainySource` for fetching content from external providers
- **Progress engine** — multi-dimensional tracking (content + person + session)
- **Cache manager** — offline file storage for media assets
- **AI interface** — protocol for local LLM queries (search, filter, recommend)
- **MCP server** — data sovereignty protocol. Exposes preferences, stats, history to authorized clients. Permission-scoped, audit-logged, one-click revocable. GDPR automation built-in.

**Why libSQL, not CoreData**: Portable across all targets (macOS, iOS, tvOS, Linux CLI). No Apple lock-in. Raw SQL with parameterized queries — same philosophy as the rest of the Shiki stack. Encrypted at rest via libSQL encryption extension.

### 2.3 Current State (What Exists)

The project already has working code:

| Target | Status | LOC (approx) |
|--------|--------|---------------|
| `BrainyCore` | Working — `Models.swift` (Feed, Article, Video) + `Storage.swift` (libSQL) | ~320 |
| `Brainy` (CLI) | Working — RSS feed management, AI augmentation, TUI renderer | ~600 |
| `BrainyTube` | Working — macOS video player (YouTube download + grid/single player) | ~1,200 |
| Tests | Partial — `BrainyTests/` covers CLI only | ~100 |

**Key dependencies already in use**: libsql-swift, FeedKit, ArgumentParser, NetKit.

---

## 3. Media Type System

### 3.1 Unified `MediaItem` Model

All 7 media types share a common base and specialize via an associated `MediaDetail` enum. This is NOT a class hierarchy — it is a flat struct with a discriminated union for type-specific data.

```swift
public struct MediaItem: Sendable, Identifiable, Codable, Equatable {
    public let id: String                    // UUID
    public let vaultId: String               // Which vault owns this
    public var title: String
    public var sourceURL: String?            // Original URL (nullable for local files)
    public var mediaType: MediaType
    public var detail: MediaDetail           // Type-specific payload
    public var tags: [String]
    public var collections: [String]         // Collection IDs
    public var rating: Int?                  // 1-5 personal rating
    public var notes: String?               // Personal notes
    public var isFavorite: Bool
    public var isArchived: Bool
    public let addedAt: Date
    public var updatedAt: Date

    // Computed from Progress table
    public var lastAccessedAt: Date?
    public var consumptionStatus: ConsumptionStatus  // .new, .inProgress, .completed, .dropped
}

public enum MediaType: String, Sendable, Codable, CaseIterable {
    case article        // Long-form web content, newsletters
    case link           // Browser tab dump, bookmarks
    case video          // YouTube, local files, streaming
    case manga          // Manga, manhwa, manhua, webtoon, comic
    case book           // PDF, EPUB, web novels
    case audio          // Podcasts, music playlists, audiobooks
    case screen         // Movies, series, anime (watch tracking only — no playback)
}

public enum MediaDetail: Sendable, Codable, Equatable {
    case article(ArticleDetail)
    case link(LinkDetail)
    case video(VideoDetail)
    case manga(MangaDetail)
    case book(BookDetail)
    case audio(AudioDetail)
    case screen(ScreenDetail)
}
```

### 3.2 Type-Specific Details

```swift
public struct ArticleDetail: Sendable, Codable, Equatable {
    public var feedId: String?               // RSS feed ID if from a feed
    public var content: String?              // Extracted clean text
    public var summary: String?              // AI-generated or RSS summary
    public var author: String?
    public var siteName: String?
    public var wordCount: Int?
    public var estimatedReadTime: Int?       // Minutes
    public var isRead: Bool
    public var readAt: Date?
    public var publishedAt: Date?
}

public struct LinkDetail: Sendable, Codable, Equatable {
    public var description: String?
    public var siteName: String?
    public var faviconPath: String?
    public var screenshotPath: String?       // Optional page screenshot
    public var isVisited: Bool
    public var visitedAt: Date?
    public var capturedFrom: CaptureSource   // .browser, .shareSheet, .manual, .import
}

public enum CaptureSource: String, Sendable, Codable {
    case browser, shareSheet, manual, importFile
}

public struct VideoDetail: Sendable, Codable, Equatable {
    public var videoId: String               // YouTube ID or local hash
    public var channelName: String?
    public var duration: TimeInterval?
    public var thumbnailPath: String?
    public var videoPath: String?            // Local downloaded file
    public var subtitlePath: String?
    public var downloadStatus: DownloadStatus
    public var quality: VideoQuality
    public var codecPreference: VideoCodecPreference
    public var detectedCodec: String?
    public var downloadedAt: Date?
    public var lastPosition: TimeInterval?   // Resume playback position
}

public struct MangaDetail: Sendable, Codable, Equatable {
    public var sourceId: String              // Which BrainySource provides this
    public var mangaId: String               // Source-specific ID
    public var author: String?
    public var artist: String?
    public var status: SeriesStatus          // .ongoing, .completed, .hiatus, .cancelled
    public var coverPath: String?
    public var totalChapters: Int?
    public var lastReadChapter: Double?      // 45.5 for chapter 45.5
    public var genres: [String]
    public var language: String              // ISO 639-1
    public var isNSFW: Bool
}

public enum SeriesStatus: String, Sendable, Codable {
    case ongoing, completed, hiatus, cancelled, unknown
}

public struct BookDetail: Sendable, Codable, Equatable {
    public var author: String?
    public var publisher: String?
    public var isbn: String?
    public var coverPath: String?
    public var filePath: String?             // Local EPUB/PDF
    public var totalPages: Int?
    public var currentPage: Int?
    public var format: BookFormat
}

public enum BookFormat: String, Sendable, Codable {
    case epub, pdf, webNovel, cbz, cbr
}

public struct AudioDetail: Sendable, Codable, Equatable {
    public var artist: String?
    public var album: String?
    public var duration: TimeInterval?
    public var filePath: String?             // Local audio file
    public var streamURL: String?            // Podcast/streaming URL
    public var coverPath: String?
    public var audioType: AudioType
    public var lastPosition: TimeInterval?   // Resume position
    public var episodeNumber: Int?           // For podcasts
    public var podcastFeedURL: String?       // For podcast discovery
}

public enum AudioType: String, Sendable, Codable {
    case music, podcast, audiobook, playlist
}

public struct ScreenDetail: Sendable, Codable, Equatable {
    public var tmdbId: Int?                  // TheMovieDB ID (optional, for metadata)
    public var screenType: ScreenType
    public var totalEpisodes: Int?
    public var lastWatchedEpisode: Int?
    public var lastWatchedSeason: Int?
    public var status: SeriesStatus
    public var genres: [String]
    public var coverPath: String?
    public var externalURL: String?          // Where to watch (no playback, just tracking)
    public var year: Int?
}

public enum ScreenType: String, Sendable, Codable {
    case movie, series, anime, documentary
}
```

### 3.3 Consumption Status

```swift
public enum ConsumptionStatus: String, Sendable, Codable {
    case new            // Never accessed
    case inProgress     // Started but not finished
    case completed      // Finished (read, watched, listened)
    case dropped        // Abandoned intentionally
    case onHold         // Paused, intend to resume
}
```

---

## 4. Data Model — libSQL Schema

### 4.1 Core Tables

```sql
-- Vault metadata (supports multi-vault in future)
CREATE TABLE IF NOT EXISTS vaults (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    encryption_key_hash TEXT,          -- NULL = unencrypted
    created_at TEXT NOT NULL,
    last_opened_at TEXT
);

-- The main table — one row per piece of content
CREATE TABLE IF NOT EXISTS media_items (
    id TEXT PRIMARY KEY,
    vault_id TEXT NOT NULL,
    title TEXT NOT NULL,
    source_url TEXT,
    media_type TEXT NOT NULL,          -- article, link, video, manga, book, audio, screen
    detail_json TEXT NOT NULL,          -- JSON-encoded MediaDetail
    tags TEXT NOT NULL DEFAULT '[]',    -- JSON array of strings
    collections TEXT NOT NULL DEFAULT '[]',  -- JSON array of collection IDs
    rating INTEGER,
    notes TEXT,
    is_favorite INTEGER NOT NULL DEFAULT 0,
    is_archived INTEGER NOT NULL DEFAULT 0,
    consumption_status TEXT NOT NULL DEFAULT 'new',
    added_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    last_accessed_at TEXT,
    FOREIGN KEY (vault_id) REFERENCES vaults(id)
);

CREATE INDEX idx_media_type ON media_items(media_type);
CREATE INDEX idx_consumption ON media_items(consumption_status);
CREATE INDEX idx_added ON media_items(added_at DESC);
CREATE INDEX idx_vault ON media_items(vault_id);

-- Collections (folders/playlists/shelves)
CREATE TABLE IF NOT EXISTS collections (
    id TEXT PRIMARY KEY,
    vault_id TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    icon TEXT,                          -- SF Symbol name or emoji
    color TEXT,                         -- Hex color
    media_types TEXT NOT NULL DEFAULT '[]',  -- Filter: which types allowed
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_smart INTEGER NOT NULL DEFAULT 0,    -- Smart collection = saved query
    smart_query TEXT,                   -- SQL WHERE clause for smart collections
    created_at TEXT NOT NULL,
    FOREIGN KEY (vault_id) REFERENCES vaults(id)
);

-- Sources (RSS feeds, manga sources, podcast feeds)
CREATE TABLE IF NOT EXISTS sources (
    id TEXT PRIMARY KEY,
    vault_id TEXT NOT NULL,
    name TEXT NOT NULL,
    source_type TEXT NOT NULL,          -- rss, manga, youtube, podcast, web
    config_json TEXT NOT NULL,          -- Source-specific configuration
    last_fetched_at TEXT,
    fetch_interval_seconds INTEGER NOT NULL DEFAULT 3600,
    is_enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    FOREIGN KEY (vault_id) REFERENCES vaults(id)
);

-- Progress tracking (multi-dimensional)
CREATE TABLE IF NOT EXISTS progress (
    id TEXT PRIMARY KEY,
    media_item_id TEXT NOT NULL,
    person_tag_id TEXT,                 -- NULL = solo consumption
    progress_type TEXT NOT NULL,        -- page, chapter, episode, timestamp, percentage
    progress_value REAL NOT NULL,       -- The numeric value
    progress_max REAL,                  -- Total (total pages, total chapters, duration)
    session_duration_seconds INTEGER,   -- How long this session lasted
    device TEXT,                        -- Which device
    created_at TEXT NOT NULL,
    FOREIGN KEY (media_item_id) REFERENCES media_items(id) ON DELETE CASCADE,
    FOREIGN KEY (person_tag_id) REFERENCES person_tags(id) ON DELETE SET NULL
);

CREATE INDEX idx_progress_item ON progress(media_item_id, created_at DESC);

-- Person dimension ("who did I consume this with?")
CREATE TABLE IF NOT EXISTS person_tags (
    id TEXT PRIMARY KEY,
    vault_id TEXT NOT NULL,
    name TEXT NOT NULL,                 -- "alone", "wife", "brother", "Faustin"
    icon TEXT,                          -- Emoji or SF Symbol
    created_at TEXT NOT NULL,
    FOREIGN KEY (vault_id) REFERENCES vaults(id)
);

-- Sessions (time-bounded consumption periods)
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    vault_id TEXT NOT NULL,
    media_item_id TEXT NOT NULL,
    person_tag_ids TEXT NOT NULL DEFAULT '[]',  -- JSON array
    started_at TEXT NOT NULL,
    ended_at TEXT,
    duration_seconds INTEGER,
    device TEXT,
    notes TEXT,
    FOREIGN KEY (vault_id) REFERENCES vaults(id),
    FOREIGN KEY (media_item_id) REFERENCES media_items(id) ON DELETE CASCADE
);

-- Cached files (offline assets)
CREATE TABLE IF NOT EXISTS cache_entries (
    id TEXT PRIMARY KEY,
    media_item_id TEXT NOT NULL,
    file_type TEXT NOT NULL,            -- thumbnail, cover, video, audio, page, chapter
    file_path TEXT NOT NULL,            -- Relative to vault directory
    file_size_bytes INTEGER,
    cached_at TEXT NOT NULL,
    last_accessed_at TEXT,
    FOREIGN KEY (media_item_id) REFERENCES media_items(id) ON DELETE CASCADE
);

-- FTS5 full-text search on titles, notes, and content
CREATE VIRTUAL TABLE IF NOT EXISTS media_fts USING fts5(
    title, notes, content,
    content='media_items',
    content_rowid='rowid'
);
```

### 4.2 Progress Tracking — How It Works

Progress is append-only. Every reading/watching/listening session appends a row to `progress`. The current state of any media item is derived from the latest progress entry.

**Multi-person dimension**: When watching anime with your brother, the session records `person_tag_ids: ["brother-uuid"]`. Query: "which episodes did I watch with my brother?" = `SELECT * FROM sessions WHERE person_tag_ids LIKE '%brother-uuid%' AND media_item_id = ?`.

**Per-type progress**:

| Media Type | progress_type | progress_value | progress_max |
|------------|--------------|----------------|-------------|
| Article | percentage | 0.75 | 1.0 |
| Video | timestamp | 1234.5 | 3600.0 |
| Manga | chapter | 45.5 | 200.0 |
| Book | page | 142 | 350 |
| Audio | timestamp | 845.2 | 2400.0 |
| Screen (series) | episode | 8 | 24 |
| Screen (movie) | percentage | 1.0 | 1.0 |
| Link | percentage | 1.0 | 1.0 |

### 4.3 AI Layer Queries

The AI agent queries the vault through a defined interface:

```swift
public protocol BrainyAI: Sendable {
    /// Semantic search across all media items
    func search(query: String, mediaTypes: [MediaType]?, limit: Int) async throws -> [MediaItem]

    /// "Have I seen this before?" — dedup check
    func findSimilar(to item: MediaItem, threshold: Double) async throws -> [MediaItem]

    /// Filter noise from a source fetch (e.g., skip clickbait RSS)
    func filterRelevant(items: [MediaItem], preferences: UserPreferences) async throws -> [MediaItem]

    /// Generate recommendations based on consumption history
    func recommend(from history: [MediaItem], count: Int) async throws -> [Recommendation]

    /// Summarize content
    func summarize(content: String, maxLength: Int) async throws -> String
}
```

Implementation uses local LLM (MLX on Apple Silicon, Ollama fallback) for zero-cloud privacy. Embeddings stored in a separate `embeddings` table for vector search via libSQL vector extension.

---

## 5. Source Plugin Architecture

### 5.1 Protocol

```swift
public protocol BrainySource: Sendable {
    /// Unique identifier for this source type
    static var sourceType: String { get }

    /// Human-readable name
    static var displayName: String { get }

    /// Which media types this source provides
    static var supportedMediaTypes: [MediaType] { get }

    /// Initialize with source-specific configuration
    init(config: SourceConfig) throws

    /// Discover content (browse/latest)
    func discover(page: Int) async throws -> [MediaItem]

    /// Fetch a specific item's full content
    func fetch(itemId: String) async throws -> MediaItem

    /// Search within this source
    func search(query: String, page: Int) async throws -> [MediaItem]

    /// Fetch updates since last check (for feeds)
    func fetchUpdates(since: Date) async throws -> [MediaItem]

    /// Download media asset for offline use (pages, video, audio)
    func downloadAsset(for item: MediaItem, to directory: URL) async throws -> URL
}

public struct SourceConfig: Sendable, Codable {
    public let sourceId: String
    public var parameters: [String: String]   // Source-specific key-value config
    public var credentials: [String: String]   // Stored encrypted
}
```

### 5.2 Built-in Sources

| Source | Media Types | Technology | Phase |
|--------|------------|-----------|-------|
| `RSSSource` | article | FeedKit (already in use) | v0.1 |
| `YouTubeSource` | video | yt-dlp shell-out | v0.1 |
| `WebScraperSource` | link, article | NetKit + SwiftSoup | v0.1 |
| `LocalFileSource` | video, audio, book | File system scan | v0.1 |
| `PodcastSource` | audio | FeedKit (RSS podcast feeds) | v0.3 |
| `TMDBSource` | screen | TMDB API (metadata only) | v0.3 |

### 5.3 Community Sources (Manga Model)

Manga sources follow the Aidoku/Tachiyomi model — external source definitions that implement `BrainySource`.

**How community sources work**:

1. **Source package** = a Swift module conforming to `BrainySource`, compiled to a dynamic library (`.dylib` on macOS, `.so` on Linux)
2. **Source repository** = a JSON index listing available sources with version, URL, checksum
3. **Installation**: user adds a repo URL, Brainy fetches the index, user picks sources to install
4. **Update**: Brainy checks repo index for new versions, downloads updated `.dylib`
5. **Sandboxing**: sources run in a separate process with limited capabilities (network only to their declared domains, no file system access outside cache directory)

```swift
// Example: a manga source
public struct PhenixScansSource: BrainySource {
    public static let sourceType = "manga.phenixscans"
    public static let displayName = "Phenix Scans"
    public static let supportedMediaTypes: [MediaType] = [.manga]

    private let baseURL = "https://phenixscans.fr"

    public init(config: SourceConfig) throws { /* ... */ }

    public func discover(page: Int) async throws -> [MediaItem] {
        // Scrape latest releases page
    }

    public func fetch(itemId: String) async throws -> MediaItem {
        // Fetch chapter page list
    }

    public func search(query: String, page: Int) async throws -> [MediaItem] {
        // Search manga by title
    }

    public func downloadAsset(for item: MediaItem, to directory: URL) async throws -> URL {
        // Download chapter pages as images
    }
}
```

**Repo index format** (JSON):

```json
{
  "name": "FR Manga Sources",
  "sources": [
    {
      "id": "manga.phenixscans",
      "name": "Phenix Scans",
      "version": "1.0.0",
      "url": "https://repo.example.com/phenixscans-1.0.0.dylib",
      "checksum": "sha256:abc123...",
      "mediaTypes": ["manga"],
      "language": "fr",
      "nsfw": false
    }
  ]
}
```

### 5.4 Source Lifecycle

```
Install → Configure → Enable → Fetch (periodic) → Update → Disable/Remove
                                  ↓
                            discover() / search()
                                  ↓
                            fetch() → MediaItem saved to vault
                                  ↓
                            downloadAsset() → cached locally
```

---

## 6. Features by Priority

### v0.0 — Data Sovereignty Core (Phase 0 — SHIPS FIRST)

**Goal**: The MCP server that owns your data. Everything else is a feature ON TOP of this.

**Deliverables:**
- **BrainyMCP** — MCP server (stdio transport, same pattern as ShikiMCP)
  - `preferences/` — taste graph (genres, topics, authors, channels you follow)
  - `stats/reading` — books, manga, articles (title, progress, time spent, rating)
  - `stats/watching` — movies, series, anime, videos
  - `stats/listening` — music, podcasts, audio
  - `stats/browsing` — web history, saved links, tab vault
  - `permissions/` — per-company ACL (who can read what, audit log)
- **Permission model** — `brainy grant spotify --scope stats/listening --expires 30d`
- **Revocation** — `brainy revoke spotify --delete-remote` (GDPR deletion request)
- **Audit log** — every data access logged in vault (who, when, what, how much)
- **Import pipeline** — `brainy import youtube-history`, `brainy import spotify-playlists`, `brainy import browser-tabs`
- **Encrypted vault** — libSQL with encryption, locked by passphrase or biometrics

**Why Phase 0**: Without the data sovereignty layer, Brainy is just another reader app. With it, it's a paradigm shift. The MCP server IS the product. Readers and players are features.

**Estimated LOC**: ~800 (MCP server + permission model + import CLI)

---

### v0.1 — MVP (Foundation)

**Goal**: Replace browser tabs + YouTube playlists. Daily-usable link vault and video player. Built ON TOP of the v0.0 MCP vault.

| Feature | Description | Target |
|---------|-------------|--------|
| **Link vault** | Paste URLs → saved with title, description, favicon. Searchable. | CLI + macOS |
| **Browser tab dump** | Paste a list of URLs (one per line), bulk import. "Discharge your tabs." | CLI + macOS |
| **Video player** | BrainyTube as-is, with BrainyTube spec v2 improvements (thumbnail grid, codec strategy, key routing, geo-bypass, quality selector, NSFW filter) | macOS |
| **Reading list** | Articles from RSS + saved from web. Clean reading mode. | CLI + macOS |
| **Full-text search** | FTS5 search across all titles, notes, content. "Did I already save this?" | CLI + macOS |
| **Unified vault** | Single libSQL database backing all media types. Migrations from current schema. | All |
| **Collections** | User-created folders/playlists. Drag-and-drop organization. | macOS |
| **Tags** | Free-form tags on any media item. Filter by tag. | All |

**Migration from current schema**: v0.1 must migrate existing `feeds`, `articles`, and `videos` tables into the unified `media_items` table. Write a migration that reads old rows, converts to `MediaItem` with appropriate `MediaDetail`, inserts into new schema, drops old tables.

**LOC estimate**: ~2,800 new + ~800 refactored
**Tests**: ~400 LOC

### v0.2 — Reader + Progress

**Goal**: Replace Aidoku for manga reading. Track what you consume and with whom.

| Feature | Description | Target |
|---------|-------------|--------|
| **Manga reader** | Page-by-page + scroll mode. Zoom. Chapter navigation. | macOS, iOS |
| **Source plugins** | Community manga sources (Phenix Scans, Bergelmir, etc.) | All |
| **Progress tracking** | Per-content position + per-person tags + sessions | All |
| **Offline cache** | Download chapters/articles/videos for offline use. Cache manager with size limits. | All |
| **Book reader** | EPUB/PDF rendering. Page bookmarks. | macOS, iOS |
| **BrainyDaemon** | Background process for periodic source fetching + cache warming | macOS, Linux |
| **iOS app** | Read manga, articles, watch videos on mobile | iOS |

**LOC estimate**: ~4,200 new
**Tests**: ~600 LOC

### v0.3 — Audio + Screen + AI

**Goal**: Replace podcast app + Trakt. Add AI filtering layer.

| Feature | Description | Target |
|---------|-------------|--------|
| **Audio player** | Playback for podcasts, local music. Queue management. Background audio. | macOS, iOS |
| **Podcast source** | RSS podcast feed parsing. Episode tracking. | All |
| **Movie/Series tracker** | Add movies/series/anime. Track episodes. Import from TMDB. No playback — just tracking. | All |
| **AI filtering** | Local LLM filters RSS noise. Relevance scoring. "Show me only the good stuff." | macOS, Linux |
| **AI search** | Semantic search across vault. "What did I read about X?" Natural language queries. | macOS, Linux |
| **AI recommendations** | "Based on what you liked, try this." Local only — no cloud. | macOS, Linux |
| **Smart collections** | Auto-updating collections based on saved queries ("unread articles from this week", "manga I'm behind on"). | All |
| **iPadOS app** | Full reader experience on iPad. Split view support. | iPadOS |

**LOC estimate**: ~5,500 new
**Tests**: ~700 LOC

### v1.0 — Vault + Sync + Ecosystem

**Goal**: Production-grade private vault. Multi-device. Living room experience.

| Feature | Description | Target |
|---------|-------------|--------|
| **Encrypted vault** | Vault locked with biometrics (Touch ID / Face ID) or passphrase. AES-256 at rest. | All Apple |
| **P2P sync** | Encrypted peer-to-peer sync between your devices. No cloud server. Multipeer Connectivity (Apple) + custom protocol (Linux). | All |
| **tvOS app** | Living room media: video playback, anime tracking, series progress. Remote-friendly UI. | tvOS |
| **Linux CLI** | Full vault management. Headless ingest. Sync daemon. Server-side source fetching. | Linux |
| **Share sheets** | iOS/macOS share extension for capturing URLs from any app. | iOS, macOS |
| **Browser extension** | Safari + Firefox extension. One-click save. Tab dump. | macOS |
| **Export/Import** | Export vault to JSON/SQLite. Import from Pocket, Raindrop, Aidoku backup. | All |
| **Statistics** | Reading/watching stats. Time spent per media type. Streaks. | All |

**LOC estimate**: ~7,000 new
**Tests**: ~900 LOC

---

## 7. Platform Strategy

### 7.1 Build Order

```
Phase 1 (v0.1):  CLI ──────► macOS (BrainyTube evolution)
Phase 2 (v0.2):  CLI + macOS ──────► iOS (reader-first)
Phase 3 (v0.3):  All above ──────► iPadOS
Phase 4 (v1.0):  All above ──────► tvOS + Linux CLI
```

### 7.2 Per-Platform Focus

| Platform | Primary Use | UI Framework | Min OS |
|----------|------------|-------------|--------|
| **macOS** | Full experience — read, watch, manage, organize | SwiftUI | macOS 14 (Sonoma) |
| **iOS** | Read manga/articles on the go, watch videos, quick capture | SwiftUI | iOS 17 |
| **iPadOS** | Extended reading (manga, books), split view browsing | SwiftUI | iPadOS 17 |
| **tvOS** | Living room — video playback, anime/series with family | SwiftUI (focus-based) | tvOS 17 |
| **Linux** | Headless vault management, sync daemon, CI/ingest | ArgumentParser CLI | Ubuntu 22.04+ |

### 7.3 Shared vs Platform-Specific

```
100% shared (BrainyCore):
  - Models, Storage, Sources, Progress, Sync, AI protocol

Per-platform:
  - macOS: NSWindow management, menu bar, keyboard shortcuts, AVPlayer
  - iOS: UIKit lifecycle, share extension, background fetch
  - iPadOS: Split view, pointer support, stage manager
  - tvOS: Focus engine, top shelf, remote navigation
  - Linux: No UI framework — CLI only, no AVFoundation (ffmpeg for media)
```

---

## 8. @shi Team Brainstorm

### 8.1 Ten FOR Ideas — What Makes Brainy Special

**@Sensei (CTO)**:
1. **One vault, all media** — No other app unifies articles + videos + manga + audio + movies + links + books in a single searchable database. Every competitor owns one vertical. Brainy owns the horizontal. This is the "second brain for media" — one search bar to find anything you ever consumed.

2. **"Discharge your tabs" UX** — Paste 47 browser tabs, Brainy ingests them all in 3 seconds, extracts titles and metadata, makes them searchable. You close all tabs. Your brain is lighter. The tabs live forever in the vault. This is Brainy's killer onboarding moment.

**@Hanami (UX)**:
3. **Person-tagged consumption** — "Which anime did I watch with my brother?" "What did my wife and I read together?" No other app tracks the social dimension of media consumption. This is not a social network — it is a private memory of shared experiences.

4. **Attention gradient, not folders** — Instead of rigid folder hierarchies, content surfaces by recency, frequency, and relevance. Most-accessed content glows bright; forgotten content dims. Smart collections replace manual organization. You never file anything — Brainy remembers what matters.

**@Kintsugi (Philosophy)**:
5. **Private by architecture, not policy** — Not "we promise not to sell your data." Instead: the vault is a local encrypted SQLite file on YOUR device. There is no server to subpoena, no terms of service to change. The architecture makes surveillance impossible, not merely against the rules.

6. **Cultural sovereignty** — Your reading history, watch patterns, music taste, manga preferences — this is your cultural DNA. Brainy keeps it in your hands. No algorithm nudging you toward engagement metrics. You discover through your own curiosity, not a recommendation engine optimized for ad revenue.

**@Enso (Brand)**:
7. **Cross-media discovery** — "People who liked this manga also watched this anime and read this article." Not from a cloud database of other users — from YOUR consumption patterns. The AI sees connections you missed: the article about Japanese woodworking relates to the manga about a carpenter. Local AI that knows you.

**@Shogun (Market)**:
8. **Source plugin marketplace** — The Aidoku/Tachiyomi model proven at scale: community-maintained source adapters. Users install manga sources from repositories. This creates a contributor ecosystem without Brainy bearing legal risk for scraping. The platform enables; the community provides.

9. **Import your digital life** — One-click import from Pocket, Raindrop, Aidoku, YouTube playlists, OPML, browser bookmarks, Trakt watch history, Spotify playlists. Every import is a permanent switch. High switching cost for competitors, zero switching cost for users coming IN.

**@Tsubaki (Copy)**:
10. **"Brain, not feed"** — Brainy is not a feed reader that demands attention. It is a brain extension that holds knowledge until you need it. The mental model shift: RSS = push (new items arrive, you must process). Brainy = pull (everything is stored, you search when curious). This flips the stress equation.

### 8.2 Ten AGAINST / Risks (@Ronin Adversarial)

**@Ronin**:

1. **Scope creep — 7 media types is monstrous** — Each media type is effectively a standalone app (reader, player, tracker). Building 7 apps inside one is a multi-year, multi-team effort. The risk is shipping none of them well. **Mitigation**: strict phase gates. v0.1 = links + video only. Each phase adds ONE reader. Never build two readers in parallel.

2. **Source plugin maintenance burden** — Web sources break constantly (DOM changes, anti-scraping, domain moves). Aidoku and Tachiyomi survive because they have hundreds of volunteer maintainers. Brainy starts with zero. If sources break monthly and nobody fixes them, the manga reader is dead on arrival. **Mitigation**: start with 2-3 stable sources only. Make the contribution path trivially easy. Document source authoring to the point a non-developer can adapt one.

3. **Legal risk — manga scraping** — Aidoku and Suwatte exist in a legal gray zone. Apple has removed manga reader apps from the App Store before (Tachiyomi had to stay Android-only). Distributing an app that facilitates scraping copyrighted manga is a real risk. **Mitigation**: Brainy ships with zero manga sources built-in. Sources come from external community repos. The app is a reader — what you put in it is your business. Same defense as a web browser.

4. **Apple App Store review** — An app that downloads YouTube videos, reads pirated manga, and caches copyrighted content will raise review flags. Especially the yt-dlp integration. **Mitigation**: macOS is primary (no App Store required — distribute as .dmg). iOS version positions as "reading list + bookmark manager" and does NOT include yt-dlp or manga source installation. Video watching on iOS = stream only, no download. Manga on iOS = only from user's local files or explicitly licensed sources.

5. **Competing with funded products** — Pocket (Mozilla, $$$), Raindrop (profitable SaaS), Infuse (Firecore, 10+ years), Aidoku (open source, active community). Each competitor has years of polish in their vertical. Brainy tries to beat all of them at once with one developer. **Mitigation**: Brainy does not need to beat them feature-for-feature. The value is unification + privacy. Users accept 80% features if it means one app instead of seven. Focus on the 20% that matters for each vertical.

6. **libSQL encryption maturity** — libSQL's encryption extension is newer than SQLCipher. If there are bugs or performance issues with large vaults (50K+ items), there is no fallback that maintains the "no Apple lock-in" principle. **Mitigation**: encryption is v1.0, not v0.1. By then, libSQL encryption will have another year of production hardening. Keep vault format simple enough to migrate to SQLCipher if needed.

7. **P2P sync is notoriously hard** — CRDTs, conflict resolution, partial sync, network discovery — each is a research-grade problem. Multipeer Connectivity is unreliable. Building a custom sync protocol is months of work that does not ship visible features. **Mitigation**: P2P sync is v1.0, the last milestone. v0.1-v0.3 are single-device only. When sync ships, use a proven CRDT library (Automerge or Yjs via Swift binding), not a custom implementation.

8. **Performance with large vaults** — A power user with 10K bookmarks, 500 manga chapters, 2K articles, 300 videos — that is 13K+ rows with JSON detail columns, FTS index, and progress history. Query performance on mobile (especially older iPhones) could degrade. **Mitigation**: aggressive indexing, pagination everywhere, lazy loading of detail_json. Benchmark with 50K synthetic items before each release.

9. **AI layer dependency on Apple Silicon** — MLX only runs on Apple Silicon. Ollama requires significant RAM. The Linux CLI has no GPU acceleration for LLM inference. Users without M-series Macs get no AI features. **Mitigation**: AI is optional, never blocking. Vault works perfectly without it. On Linux, support remote LLM endpoint (LM Studio API, same pattern as Shiki). On Intel Macs, use smaller quantized models or skip AI entirely.

10. **Single-developer bus factor** — Brainy is ambitious enough for a team of 5. One developer means one illness, one burnout, one priority shift kills the project. The codebase grows to 20K+ LOC across 5 platforms — that is unmaintainable solo long-term. **Mitigation**: BrainyCore is the insurance policy. If the GUI apps stall, the CLI + core library remain useful. Open source under AGPL means the community can fork and continue. Keep the architecture modular enough that contributors can own one reader or one source.

---

## 9. Build Order — Full Roadmap

### Phase 0: v0.0 Data Sovereignty Core (~800 LOC + tests)

```
Wave 0.1: BrainyMCP server (stdio transport, tool definitions)     (~300 LOC)
Wave 0.2: Permission model (grant/revoke/audit, libSQL schema)     (~200 LOC)
Wave 0.3: Import pipeline (YouTube, Spotify, browser tabs CLI)     (~200 LOC)
Wave 0.4: Encrypted vault (libSQL encryption + passphrase lock)    (~100 LOC)
```

### Phase 1: v0.1 MVP (~3,200 LOC + tests, builds on Phase 0 vault)

```
Wave 1: BrainyCore v2 — Unified models + storage migration
  - MediaItem, MediaDetail, MediaType models              (~400 LOC)
  - New libSQL schema (media_items, collections, etc.)     (~200 LOC)
  - Migration from current Feed/Article/Video tables       (~150 LOC)
  - Storage v2: CRUD for media_items, collections          (~500 LOC)
  - Tests: model serialization, storage CRUD, migration    (~300 LOC)

Wave 2: Link Vault + Tab Dump
  - WebScraperSource: title/description/favicon extraction  (~200 LOC)
  - CLI: `brainy add <url>`, `brainy dump` (bulk import)    (~150 LOC)
  - CLI: `brainy search <query>` (FTS5)                     (~100 LOC)
  - Tests: scraper, CLI commands                             (~100 LOC)

Wave 3: BrainyTube v2 — Apply video engine spec
  - Codec strategy, thumbnail grid, key router              (~615 LOC)
  - Geo-bypass, quality selector, content filter            (~525 LOC)
  - Migrate BrainyTube to use BrainyCore v2 storage         (~150 LOC)
  - Tests: per BrainyTube spec                               (~260 LOC)

Wave 4: macOS Reading List UI
  - Article reader view (clean reading mode)                 (~250 LOC)
  - Link vault view (grid/list with favicons)                (~200 LOC)
  - Collection sidebar                                       (~150 LOC)
  - Tag management                                           (~100 LOC)

Ship criterion: Can dump browser tabs, save articles, watch videos, search everything.
```

### Phase 2: v0.2 Reader + Progress (~4,800 LOC + tests)

```
Wave 5: Source Plugin System
  - BrainySource protocol                                    (~100 LOC)
  - Source manager (install, update, enable/disable)         (~300 LOC)
  - Source sandboxing (subprocess execution)                  (~200 LOC)
  - Built-in: RSSSource refactor to protocol                 (~100 LOC)
  - Tests: source lifecycle, sandboxing                      (~200 LOC)

Wave 6: Manga Reader
  - MangaReaderView: page-by-page + scroll modes             (~400 LOC)
  - Chapter navigation + preloading                          (~200 LOC)
  - Image cache + offline chapter storage                    (~250 LOC)
  - 2-3 initial manga source plugins                         (~300 LOC each, ~900 total)
  - Tests: reader navigation, cache                          (~200 LOC)

Wave 7: Progress Tracking
  - Progress engine (append-only tracking)                   (~200 LOC)
  - Person tags CRUD                                         (~100 LOC)
  - Session recording (auto start/stop)                      (~150 LOC)
  - Progress UI (per-item timeline, person filter)           (~250 LOC)
  - Tests: progress recording, queries                       (~200 LOC)

Wave 8: Offline Cache + iOS App
  - Cache manager (LRU eviction, size limits, integrity)     (~300 LOC)
  - BrainyDaemon (background fetch + cache warm)             (~250 LOC)
  - iOS app: reading views (article + manga)                 (~500 LOC)
  - iOS: share extension (save URL)                          (~150 LOC)

Ship criterion: Can read manga from community sources, track progress with person tags, read offline.
```

### Phase 3: v0.3 Audio + Screen + AI (~5,500 LOC + tests)

```
Wave 9: Audio Player
  - Audio playback engine (AVAudioPlayer/AVFoundation)       (~300 LOC)
  - Podcast source (RSS feed parsing for enclosures)         (~200 LOC)
  - Audio player UI (now playing, queue, playlists)          (~400 LOC)
  - Background audio on iOS                                  (~100 LOC)
  - Tests: playback, podcast parsing                         (~150 LOC)

Wave 10: Movie/Series/Anime Tracker
  - TMDB source (metadata fetch, poster download)            (~250 LOC)
  - Tracker UI (season/episode grid, status)                 (~350 LOC)
  - Watch session with person tags                           (~100 LOC)
  - Tests: TMDB source, tracking logic                       (~100 LOC)

Wave 11: AI Agent Layer
  - BrainyAI protocol                                        (~50 LOC)
  - MLX integration (macOS) / Ollama client (fallback)       (~300 LOC)
  - Embedding generation + vector storage                    (~250 LOC)
  - Semantic search implementation                           (~200 LOC)
  - Relevance filter for RSS feeds                           (~150 LOC)
  - Recommendation engine                                    (~200 LOC)
  - Smart collections (saved query evaluation)               (~150 LOC)
  - Tests: AI protocol mocks, search, filtering              (~200 LOC)

Wave 12: iPadOS + Polish
  - iPadOS adaptations (split view, pointer)                 (~300 LOC)
  - Statistics view (time spent, streaks, per-type)          (~250 LOC)
  - Unified BrainyApp shell (tab bar for all media types)    (~400 LOC)

Ship criterion: Full media vault — 7 types, AI search, offline, multi-device (macOS + iOS + iPad).
```

### Phase 4: v1.0 Vault + Sync + Ecosystem (~7,000 LOC + tests)

```
Wave 13: Encrypted Vault
  - libSQL encryption integration                            (~200 LOC)
  - Vault lock/unlock flow (biometrics + passphrase)         (~300 LOC)
  - Key derivation (Argon2id)                                (~100 LOC)
  - Secure file cache encryption                             (~200 LOC)
  - Tests: encryption round-trip, lock/unlock                (~200 LOC)

Wave 14: P2P Sync
  - Sync protocol design (CRDT-based)                        (~400 LOC)
  - Multipeer Connectivity transport (Apple devices)         (~300 LOC)
  - Custom TCP transport (Linux ↔ any)                      (~300 LOC)
  - Conflict resolution                                      (~250 LOC)
  - Sync UI (device list, sync status, resolve conflicts)    (~200 LOC)
  - Tests: sync protocol, conflict resolution                (~300 LOC)

Wave 15: tvOS App
  - tvOS app target (focus-based navigation)                 (~500 LOC)
  - Video player (tvOS AVPlayerViewController)               (~200 LOC)
  - Series/anime browsing (poster grid)                      (~300 LOC)
  - Remote-friendly controls                                 (~150 LOC)

Wave 16: Linux CLI + Ecosystem
  - Linux-compatible BrainyCore (no AVFoundation)            (~200 LOC)
  - Sync daemon (systemd service)                            (~150 LOC)
  - CLI: all CRUD operations, source management              (~400 LOC)
  - Import from Pocket, Raindrop, OPML, Trakt                (~500 LOC)
  - Browser extension (Safari + Firefox)                      (~400 LOC)
  - Export (JSON, SQLite dump)                                (~200 LOC)
  - Tests: import/export, Linux-specific                     (~200 LOC)

Ship criterion: Encrypted, syncs across devices, works on all platforms.
```

---

## 10. Total Estimates

| Phase | New LOC | Test LOC | Cumulative |
|-------|---------|----------|-----------|
| v0.0 Data Sovereignty | ~700 | ~100 | ~800 |
| v0.1 MVP | ~2,800 | ~660 | ~4,260 |
| v0.2 Reader + Progress | ~3,900 | ~600 | ~8,760 |
| v0.3 Audio + Screen + AI | ~4,150 | ~450 | ~13,360 |
| v1.0 Vault + Sync + Ecosystem | ~5,050 | ~700 | ~18,310 |
| **Total** | **~15,900** | **~2,410** | **~18,310** |

---

## 11. Open Questions for @Daimyo

### Architecture

1. **Unified app vs separate executables?** — Current structure has `Brainy` (CLI) and `BrainyTube` (macOS video) as separate executables. v0.3 introduces `BrainyApp` as a unified shell. Do we keep separate executables for each reader (BrainyTube, BrainyReader) during development and merge later? Or build the unified shell from v0.2?

2. **Source plugin format** — Dynamic libraries (`.dylib`) are the most performant but require Swift ABI stability and complicate distribution. Alternative: source definitions as JSON/YAML with a built-in scraping DSL (like Aidoku's approach). Simpler to author but less flexible. Which path?

3. **iOS App Store strategy** — Ship iOS as a "reading list + article reader" (App Store safe) and load manga/video features only on macOS/sideload? Or skip the App Store entirely and distribute via TestFlight / AltStore?

### Priorities

4. **Manga before audio?** — v0.2 does manga, v0.3 does audio. The user's primary itch is manga (uses Aidoku with brother). But audio is simpler to implement and has wider appeal. Confirm manga-first ordering?

5. **AI timing** — v0.3 adds the AI layer. Is this too late? Basic relevance filtering for RSS could ship in v0.1 with a simpler heuristic (keyword matching, read-frequency weighting) without needing LLM. Should we ship "dumb AI" early and "real AI" later?

6. **tvOS priority** — v1.0 is the tvOS target. The user watches anime on TV. Should tvOS move to v0.3 (after the screen tracker) to get the living room experience sooner?

### Technical

7. **libSQL vector extension** — Required for semantic search in the AI layer. Is the libSQL vector extension mature enough, or should we plan for a separate vector store (e.g., Qdrant embedded, or plain cosine similarity on small datasets)?

8. **Sync protocol** — Multipeer Connectivity for Apple-to-Apple, custom TCP for Linux. Is this worth the complexity? Alternative: a simple "export vault → import on other device" manual sync for v1.0, with real sync in v1.1.

9. **BrainyTube spec v2 sequencing** — The BrainyTube video engine spec (thumbnail grid, codec strategy, keyboard nav, geo-bypass, quality selector, NSFW filter) is ~1,400 LOC across 6 waves. Should this ship as a standalone release before starting the unified vault migration? Or merge both efforts?

### Data

10. **Migration from current users** — If anyone is already using the CLI or BrainyTube, the v0.1 migration from the old schema to unified `media_items` is destructive (drops old tables). Ship a backup-first migration? Or assume no external users yet?

---

## Appendix A: Dependency Map

```
BrainyCore
  ├── libsql-swift          (database)
  └── (no other deps — pure Swift + Foundation)

Brainy (CLI)
  ├── BrainyCore
  ├── ArgumentParser         (CLI framework)
  ├── FeedKit               (RSS parsing)
  └── NetKit                (HTTP client)

BrainyTube (macOS Video)
  ├── BrainyCore
  ├── KSPlayer              (VP9 decode, conditional)
  └── AVFoundation          (system framework)

BrainyReader (macOS Manga/Book)
  ├── BrainyCore
  └── SwiftUI               (system framework)

BrainyApp (Unified macOS Shell)
  ├── BrainyCore
  ├── BrainyTube (embedded)
  ├── BrainyReader (embedded)
  └── SwiftUI

BrainyDaemon (Background Service)
  ├── BrainyCore
  ├── FeedKit
  └── NetKit

iOS / iPadOS / tvOS
  ├── BrainyCore
  └── SwiftUI
```

## Appendix B: File Layout After v0.1

```
Sources/BrainyCore/
├── Models/
│   ├── MediaItem.swift
│   ├── MediaDetail.swift
│   ├── MediaType.swift
│   ├── ConsumptionStatus.swift
│   ├── Collection.swift
│   ├── PersonTag.swift
│   ├── Progress.swift
│   └── Session.swift
├── Storage/
│   ├── VaultStorage.swift           (unified CRUD)
│   ├── VaultMigrations.swift        (schema + data migrations)
│   ├── FTSManager.swift             (full-text search)
│   └── LegacyMigration.swift        (v0 → v0.1 schema migration)
├── Sources/
│   ├── BrainySource.swift           (protocol)
│   ├── SourceConfig.swift
│   ├── SourceManager.swift
│   ├── BuiltIn/
│   │   ├── RSSSource.swift
│   │   ├── YouTubeSource.swift
│   │   ├── WebScraperSource.swift
│   │   └── LocalFileSource.swift
│   └── Community/
│       └── CommunitySourceLoader.swift
└── Cache/
    └── CacheManager.swift
```

---

*This spec is the product bible for Brainy. Every implementation decision flows from here. Update this document as decisions are made on the open questions above.*
