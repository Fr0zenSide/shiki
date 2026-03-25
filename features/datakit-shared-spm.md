---
title: "DataKit — Shared SPM Package for Local Storage"
status: draft
priority: P1
project: shiki
created: 2026-03-25
---

# DataKit — Shared Local Storage SPM Package

## Summary

Extract libsql/SQLite storage layer from Brainy into a shared SPM package at `packages/DataKit/`, following the same pattern as CoreKit, NetKit, SecurityKit. Provides CRUD protocol, migration system, and storage abstraction reusable across all projects.

## Motivation

- Brainy uses libsql with raw SQL (same pattern as the "no ORM" decision)
- WabiSabi has `CRUDUseCaseProtocol` with strategy (online/offline)
- Maya will need local storage for offline fitness data
- Flsh uses FileSystemNoteStore (could benefit from structured storage option)
- Avoid duplicating storage boilerplate across projects

## Architecture

### CRUD Protocol (adapted from WabiSabi)

```swift
public protocol StorageProtocol: Sendable {
    func get<T: Codable & Sendable>(id: String, table: String) async throws -> T
    func getAll<T: Codable & Sendable>(table: String, filter: StorageFilter?) async throws -> [T]
    func create<T: Codable & Sendable>(_ item: T, table: String) async throws
    func update<T: Codable & Sendable>(id: String, _ item: T, table: String) async throws
    func delete(id: String, table: String) async throws
    func count(table: String, filter: StorageFilter?) async throws -> Int
}

public enum StorageFilter {
    case equals(column: String, value: String)
    case contains(column: String, value: String)
    case and([StorageFilter])
    case or([StorageFilter])
}
```

### Migration System

```swift
public protocol Migration: Sendable {
    var version: Int { get }
    var sql: String { get }
}

public struct MigrationRunner {
    func run(migrations: [Migration], on db: Database) async throws
}
```

### Package Structure

```
packages/DataKit/
├── Package.swift
├── Sources/DataKit/
│   ├── StorageProtocol.swift
│   ├── StorageFilter.swift
│   ├── Migration.swift
│   ├── LibsqlStorage.swift      (libsql implementation)
│   └── MockStorage.swift        (test double)
└── Tests/DataKitTests/
    ├── StorageTests.swift
    └── MigrationTests.swift
```

### Dependencies

- `libsql-swift` (from: "0.1.1")
- `CoreKit` (for AppLog, CacheRepository)

### Migration Path

1. Create `packages/DataKit/` with protocol + libsql impl
2. Port Brainy's `Storage.swift` to use DataKit
3. Port WabiSabi's offline cache to use DataKit (optional, can coexist)
4. Future: Maya local storage uses DataKit from day 1

### Estimated

- ~400 LOC source, ~150 LOC tests
- 1 wave, half-day implementation
