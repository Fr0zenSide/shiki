# Project Adapter Template

Copy this file to your project root as `project-adapter.md` and fill in the values.
The Shiki process skills read this file to adapt to your tech stack.

## Project

- **Name**: <project name>
- **Description**: <1 line>
- **Repo**: <git URL>

## Tech Stack

- **Language**: <Swift / TypeScript / Python / Go / Rust / etc.>
- **Framework**: <SwiftUI / React / Django / etc.>
- **Architecture**: <Clean Arch / MVC / MVVM / Hexagonal / etc.>
- **DI**: <custom container / Swinject / none / etc.>
- **Backend**: <PocketBase / Supabase / Express / none / etc.>
- **Database**: <PostgreSQL / SQLite / none / etc.>

## Commands

- **Test**: `swift test` / `npm test` / `pytest` / `go test ./...`
- **Build**: `swift build` / `npm run build` / `cargo build`
- **Lint**: `swiftlint` / `eslint .` / `ruff check .` / (none)
- **Format**: `swiftformat .` / `prettier --write .` / (none)

## Conventions

- **Branching**: `feature/*` from `develop` / `feat/*` from `main`
- **Naming**: camelCase / snake_case / PascalCase
- **Test naming**: `test_<what>_<condition>_<expected>()` / `describe/it` / etc.
- **Commit style**: conventional commits / free-form

## Active Checklists

Enable/disable review addons:
- **CTO review**: yes
- **CTO Swift addon**: yes / no (only for Swift projects)
- **UX review**: yes / no (only if UI work)
- **Code quality**: yes
- **Code quality Swift addon**: yes / no
- **Visual QC**: yes / no (requires QC tool)
- **AI slop scan**: yes / no

## Feature File Path

- **Features directory**: `features/` (relative to project root)

## Design System

- **Tokens file**: <path or none>
- **Primary color**: <hex or name>
- **Font system**: <custom / system>

## Platform

- **Targets**: iOS / macOS / web / CLI / API / etc.
- **Min version**: iOS 17+ / Node 20+ / Python 3.12+ / etc.
- **UI framework**: SwiftUI / React / Vue / none
