---
title: "OpenAI-Compatible Provider — Universal Local AI Backend"
status: draft
priority: P0
project: shikki
created: 2026-04-03
authors: "@Daimyo + @shi brainstorm"
tags:
  - providers
  - openai
  - lm-studio
  - nats
depends-on:
  - shikki-node-security.md (NATS mesh auth)
  - shikki-distributed-orchestration.md (node discovery)
relates-to:
  - shikki-provider-nats-node.md (provider as discoverable node)
---

# OpenAI-Compatible Provider

> It was never an LM Studio client. It is an OpenAI API client. Name it honestly.

---

## 1. Problem

`LMStudioProvider` is a generic OpenAI-compatible HTTP client that works with any server implementing `/v1/chat/completions` -- LM Studio, Ollama, Jan, MLX, vLLM. The name lies about its scope. New contributors assume it only works with LM Studio. Worse, adding a second local server means copy-pasting the entire provider with a different name. The env vars (`LMSTUDIO_URL`, `LMSTUDIO_MODEL`) are LM Studio-specific but the code is universal.

---

## 2. Solution

Rename `LMStudioProvider` to `OpenAICompatibleProvider`. Accept per-instance config via env vars or explicit init params. Support multiple simultaneous instances (e.g., LM Studio on `:1234` + Ollama on `:11434`). Each instance can register as a NATS node (see `shikki-provider-nats-node.md`).

---

## 3. Business Rules

| ID | Rule |
|----|------|
| BR-01 | `LMStudioProvider` MUST be renamed to `OpenAICompatibleProvider` with a deprecated typealias for backward compatibility |
| BR-02 | Error enum renamed `OpenAICompatibleError` (typealias `LMStudioError` kept) |
| BR-03 | Env vars: `OPENAI_COMPAT_URL` (fallback `LMSTUDIO_URL`), `OPENAI_COMPAT_MODEL` (fallback `LMSTUDIO_MODEL`) |
| BR-04 | Init accepts optional `instanceName: String` for logging and NATS registration identity |
| BR-05 | Multiple instances MUST coexist in `FallbackProviderChain` with distinct base URLs |
| BR-06 | `FallbackProviderChain.isFallbackEligible` MUST match on `OpenAICompatibleError` (not just `LMStudioError`) |
| BR-07 | Health check via `GET /v1/models` -- returns `true` if 200, `false` otherwise |
| BR-08 | Logger label uses `instanceName` for multi-instance disambiguation |

---

## 4. TDDP

| # | Test | State |
|---|------|-------|
| 1 | `OpenAICompatibleProvider` exists and conforms to `AgentProviding` | RED |
| 2 | Impl: Rename struct, add typealias `LMStudioProvider = OpenAICompatibleProvider` | GREEN |
| 3 | `OpenAICompatibleError` is the error type; `LMStudioError` typealias compiles | RED |
| 4 | Impl: Rename enum, add typealias | GREEN |
| 5 | Init reads `OPENAI_COMPAT_URL` with fallback to `LMSTUDIO_URL` | RED |
| 6 | Impl: Env var cascade in init | GREEN |
| 7 | `instanceName` appears in logger metadata | RED |
| 8 | Impl: Logger label `shikki.provider.\(instanceName)` | GREEN |
| 9 | Two instances with different URLs coexist in FallbackProviderChain | RED |
| 10 | Impl: Value-type provider with per-instance baseURL | GREEN |
| 11 | `healthCheck()` returns true for 200 from `/v1/models` | RED |
| 12 | Impl: GET request to `/v1/models`, return status == 200 | GREEN |
| 13 | `FallbackProviderChain.isFallbackEligible` handles `OpenAICompatibleError` | RED |
| 14 | Impl: Update pattern match in `isFallbackEligible` | GREEN |

---

## 5. S3 Scenarios

### Scenario 1: Rename backward compatibility (BR-01, BR-02)
```
When  existing code references `LMStudioProvider`
Then  it compiles via the deprecated typealias
  and  `OpenAICompatibleProvider` is the canonical type
```

### Scenario 2: Env var cascade (BR-03)
```
When  `OPENAI_COMPAT_URL` is set to "http://10.0.0.5:8080"
Then  provider uses that URL
  otherwise  when only `LMSTUDIO_URL` is set
  then  provider falls back to `LMSTUDIO_URL`
  otherwise  provider defaults to "http://127.0.0.1:1234"
```

### Scenario 3: Multi-instance chain (BR-04, BR-05)
```
When  FallbackProviderChain contains:
      - OpenAICompatibleProvider(instanceName: "lm-studio", baseURL: ":1234")
      - OpenAICompatibleProvider(instanceName: "ollama", baseURL: ":11434")
Then  first provider is tried for each request
  if  it throws connectionRefused
  then  second provider is tried
  and  logs identify each by instanceName
```

### Scenario 4: Health check (BR-07)
```
When  provider.healthCheck() is called
  if  GET /v1/models returns 200
  then  healthCheck() returns true
  otherwise  healthCheck() returns false (no throw)
```

### Scenario 5: Fallback eligibility after rename (BR-06)
```
When  provider throws OpenAICompatibleError.rateLimited
Then  FallbackProviderChain.isFallbackEligible returns true
  and  chain falls through to next provider
```

---

## 6. Wave Dispatch Tree

```
Wave 1: Rename + Typealiases
  Input:   LMStudioProvider.swift, LMStudioProviderTests.swift
  Output:  OpenAICompatibleProvider.swift, updated tests
  Gate:    Tests 1-4 green, existing tests compile
  <- NOT BLOCKED

Wave 2: Multi-Instance + Health Check
  Input:   OpenAICompatibleProvider.swift, FallbackProviderChain.swift
  Output:  instanceName, healthCheck(), updated isFallbackEligible
  Gate:    Tests 5-14 green
  <- BLOCKED BY Wave 1
```

---

## 7. Implementation Waves

### Wave 1: Rename + Backward Compatibility
- **Files**: `Sources/ShikkiKit/Providers/OpenAICompatibleProvider.swift` (rename from `LMStudioProvider.swift`), `Tests/ShikkiKitTests/Providers/OpenAICompatibleProviderTests.swift` (rename)
- **Tests**: Tests 1-4
- **BRs**: BR-01, BR-02, BR-03
- **Deps**: None
- **Gate**: All existing `LMStudioProviderTests` + `FallbackProviderChainTests` pass under new names. Typealiases compile.

### Wave 2: Multi-Instance + Health + Chain Update
- **Files**: `Sources/ShikkiKit/Providers/OpenAICompatibleProvider.swift` (extend), `Sources/ShikkiKit/Providers/FallbackProviderChain.swift` (update)
- **Tests**: Tests 5-14
- **BRs**: BR-04, BR-05, BR-06, BR-07, BR-08
- **Deps**: Wave 1
- **Gate**: Multi-instance chain test green, health check test green, `FallbackProviderChainTests` still green

---

## 8. @shi Mini-Challenge

1. **@Ronin**: The `/v1/models` health check assumes every OpenAI-compatible server implements that endpoint. vLLM does, Ollama does, but some minimal servers may not. Should `healthCheck()` fall back to a `POST /v1/chat/completions` with a minimal prompt if `/v1/models` returns 404?

2. **@Sensei**: Each provider instance is currently stateless (struct). When we add NATS node registration (next spec), the provider needs to publish heartbeats -- that requires lifecycle (start/stop). Should `OpenAICompatibleProvider` stay a struct with a separate `ProviderNodeRegistrar` actor, or become a class/actor itself?
