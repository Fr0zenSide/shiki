---
title: "Shi Kernel / Extension Architecture"
status: draft
priority: P0
project: shikki
created: 2026-04-02
authors: ["@Daimyo"]
tags: [architecture, kernel, extensions, foundation]
---

# Feature: Shi Kernel / Extension Architecture
> Created: 2026-04-02 | Status: Architecture Decision | Owner: @Daimyo

## Thesis

"A process before it becomes the system itself."

Shi starts as a system daemon that manages the workspace. Over time, as extensions compose, it becomes the operating system for software development. The kernel is the part that never changes. Extensions are the part that always evolves.

## @t Decision: Split Architecture, Not Binary

**Phase 1 (now):** Move files into kernel/extension directory structure, enforce import discipline. Ship as monolith.
**Phase 2 (v1):** Ship `shi-full` with clean internal boundaries. One binary.
**Phase 3 (first external extension):** Split Package.swift into multi-target, add `shi ext install`.

## Boundary Rules

| BR | Rule |
|----|------|
| BR-1 | If removing it crashes the daemon → kernel |
| BR-2 | If it has no UI and no domain logic → kernel |
| BR-3 | If it implements a workflow (spec/review/ship) → extension |
| BR-4 | If it talks to external systems other than ShikiDB → extension |
| BR-5 | Plugin infrastructure is always kernel (can't extend without the extender) |
| BR-6 | Kernel never imports an extension. Extensions only import kernel |

## Kernel (~25 files)

- ShikkiKernel (FSM, service scheduler, tick loop)
- ManagedService protocol + ServiceID + QoS + RestartPolicy
- EventBus + ShikkiEvent + EventRouter
- ShikiDB client (BackendClient, DBSyncClient)
- CheckpointManager + RecoveryManager
- SetupGuard + SetupState
- AgentProvider protocol (not implementations)
- HealthMonitor + Watchdog
- PluginManifest + PluginRegistry + PluginSandbox + PluginRunner
- AppConfig + ShikkiState + core Models
- WakeReason + EscalationEvent

## Extensions

| Extension | Depends on |
|-----------|------------|
| ShiSpec | Kernel |
| ShiCodeGen | Kernel, ShiSpec |
| ShiReview | Kernel, ShiSpec |
| ShiShip | Kernel |
| ShiNATS | Kernel |
| ShiTUI | Kernel |
| ShiSafety | Kernel |
| ShiAnswerEngine | Kernel |
| ShiFlywheel | Kernel |
| ShiMoto | Kernel |
| ShiObservatory | Kernel |

## Extension Contract

```swift
public protocol ExtensionManifest: Sendable {
    var id: String { get }
    var version: String { get }
    var minimumKernelVersion: String { get }
    var dependencies: [String] { get }
    var services: [any ManagedService.Type] { get }
}
```

## Distribution

- `shi` = kernel only (runs on ARM/tiny boards)
- `shi-full` = oh-my-zsh bundle (kernel + all standard extensions)
- `shi ext install spec` = individual extension install (v2)

## Key Moves vs Original Proposal

- TmuxStateManager → TUI extension (not kernel)
- EmojiRouter + ChainParser → TUI extension (not kernel)
- NATS (all 16 files) → ShiNATS extension (not everyone needs multi-node)
- PluginRunner infrastructure → kernel (extension loading IS kernel)

## Migration Path

1. **This week:** Directory restructure, import discipline, document kernel contract
2. **v1 launch:** Ship as `shi-full` monolith with clean boundaries
3. **On demand:** Split SPM targets when first external extension exists

"launchd shipped as one binary too."
