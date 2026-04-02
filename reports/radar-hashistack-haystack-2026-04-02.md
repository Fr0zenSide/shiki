---
title: "Radar: HashiStack + Haystack vs Moto/Hanko Protocols"
date: 2026-04-02
type: radar
scope: moto-hanko-protocols
---

# Radar: HashiStack + Haystack vs Moto/Hanko Protocols

Two projects evaluated for relevance to Shikki's Moto (public code cache) and Hanko (private data vault) protocols.

---

## 1. HashiStack (HashiCorp Vault + Consul + Nomad)

**Repo**: `hashicorp-guides/hashistack` (7 stars, Terraform deployment configs)
**Real value**: the three underlying HashiCorp tools -- all Go, all battle-tested.

| Tool | Stars | Purpose |
|------|-------|---------|
| **Vault** | 35.3k | Secrets management, encryption-as-a-service, privileged access |
| **Consul** | 29.8k | Service discovery, service mesh, distributed KV store |
| **Nomad** | 16.4k | Workload orchestration (containers + non-container, multi-DC) |

### Architecture Summary

1. **Vault -- Seal/Unseal + Secret Engines**: Vault uses a seal/unseal ceremony (Shamir's Secret Sharing or auto-unseal via cloud KMS). Data encrypted at rest with a master key split across key shares. Secret engines are pluggable backends (KV, PKI, database credentials, transit encryption). Access controlled via policy-based ACLs with lease/TTL on every secret.

2. **Consul -- Service Catalog + Health Checks + KV**: Consul maintains a service registry with DNS and HTTP interfaces. Agents run on every node (client mode) and a quorum of servers uses Raft consensus. The KV store supports watches (blocking queries) for reactive config. Service mesh uses Envoy sidecars with mutual TLS.

3. **Nomad -- Job Specs + Task Drivers + Evaluations**: Nomad uses a declarative job spec (HCL/JSON). Schedulers evaluate jobs against cluster state, produce allocations. Task drivers are pluggable (Docker, exec, Java, QEMU). Native Vault integration for secret injection into tasks. Native Consul integration for service registration.

4. **Shared Pattern -- Gossip + Raft + ACLs**: All three use Serf gossip protocol for membership, Raft for leader election/state replication, and token-based ACL systems. Designed for multi-datacenter federation.

### Relevance to Hanko: **HIGH**

Vault's architecture is the closest production analog to Hanko's private data vault:

- **Seal/Unseal model** maps to Hanko's vault encryption. Hanko uses AES-256-GCM on local SQLite; Vault's approach of requiring an explicit unseal ceremony (multiple key shares) is more robust for sensitive data.
- **Secret engines as plugins** -- Hanko could adopt this pattern: each data domain (reading stats, listening stats, credentials) as a separate engine with its own schema and access policy.
- **Lease/TTL on secrets** -- Vault's approach of issuing dynamic, time-limited credentials is exactly what Hanko's JWT token exchange flow needs. Every `hanko grant` should produce a leased token with automatic revocation.
- **Audit logging** -- Vault's audit device (file, syslog, socket) with HMAC'd sensitive values is more mature than Hanko's planned `audit_log/` table.

### Relevance to Moto: **MEDIUM**

Consul's service discovery pattern has parallels to Moto's cache resolution:

- **DNS-based resolution** (`moto_get_context(project)` is conceptually like `project.service.consul`). Consul's `.consul` TLD maps to Moto's `.moto` dotfile as a "pointer to where the data lives."
- **KV store with watches** -- Moto's cache files (manifest.json, types.json, etc.) could use Consul-style blocking queries for cache invalidation: "watch this cache version, notify when it changes."
- **Catalog registration** -- Consul's service catalog pattern (register, deregister, health check) could apply to Moto's cache registry: projects register their caches, consumers discover them.

### Relevance to Shikki Core: **MEDIUM**

- Nomad's job scheduling model is similar to Shikki's dispatch system (job spec = spec file, evaluation = quality gate, allocation = agent assignment).
- Nomad's multi-region federation could inform Shikki's future multi-node architecture (P0 Node Security backlog item).
- Vault integration pattern (inject secrets into tasks at runtime) is relevant to Shikki's plugin sandbox security.

### Patterns to Adopt

1. **Vault lease/TTL for Hanko tokens** -- every `hanko grant` issues a leased token with configurable TTL and automatic revocation. Adopt Vault's renewal/revocation lifecycle instead of simple expiration timestamps.
2. **Consul-style cache watches for Moto** -- implement blocking queries on cache version. When a consumer holds cache v1.2.0, it can long-poll for updates instead of re-fetching on every session.
3. **ACL policy language** -- Vault's HCL-based policy format (`path "secret/data/reading/*" { capabilities = ["read"] }`) is a proven pattern for Hanko's permission scoping. More expressive than simple scope strings.

### Verdict: **WATCH**

Vault's patterns are highly relevant to Hanko but Hanko is local-first (not distributed), so the full Vault architecture (Raft, multi-DC) is overkill. Cherry-pick the lease/TTL model and audit patterns. Consul's service discovery is relevant conceptually but Moto operates at file/dotfile level, not network service level. Nomad is interesting for future Shikki multi-node but not actionable today.

---

## 2. Haystack (deepset-ai/haystack)

**Repo**: `deepset-ai/haystack` -- 24.7k stars, Apache-2.0, Python/MDX
**What**: Open-source AI orchestration framework for production RAG, agents, and search pipelines.

### Architecture Summary

1. **Component Protocol** -- every building block implements a `Component` protocol with `run(**kwargs) -> dict[str, Any]`. Components declare typed input/output sockets. The framework validates connections at pipeline construction time. Components are JSON-serializable for save/load. Lightweight `__init__`, heavy state in `warm_up()`.

2. **DAG Pipeline Engine** -- pipelines are directed acyclic graphs (NetworkX `MultiDiGraph`) of components. Execution follows topological order with priority scheduling (`HIGHEST > READY > DEFER > BLOCKED`). Max-runs-per-component guard prevents infinite loops. Breakpoints for debugging. Full tracing via spans. Serializable to YAML/dict for persistence.

3. **DocumentStore Protocol** -- abstract protocol with `count_documents()`, `filter_documents(filters)`, `write_documents(docs, policy)`, `delete_documents(ids)`. Filter DSL supports nested AND/OR/NOT with comparison operators. In-memory implementation includes BM25 (configurable algorithm: Okapi/L/Plus) and vector similarity (dot product/cosine). External stores (Elasticsearch, Qdrant, Weaviate, Pinecone) via integrations.

4. **SuperComponent (Composability)** -- wraps a full pipeline as a single component with mapped inputs/outputs. Enables nesting pipelines inside pipelines. This is how complex RAG chains are built from simpler sub-pipelines.

### Relevance to Moto: **MEDIUM**

- **DocumentStore protocol** maps to Moto's cache storage abstraction. Moto stores structured JSON files (types.json, protocols.json); Haystack's DocumentStore stores `Document` objects with metadata and embeddings. The filter DSL (nested AND/OR with field operators) is more expressive than Moto's current per-file access pattern.
- **BM25 retrieval** -- Moto's `moto_suggest_implementation` could benefit from BM25-ranked retrieval over the patterns cache, rather than exact-match lookups.
- Haystack's component ecosystem (retrievers, embedders, rankers) could inform Moto's future query capabilities beyond simple `get_type`/`get_protocol`.

### Relevance to Hanko: **LOW**

Hanko is a permission-controlled data vault, not a search/retrieval system. Haystack's patterns don't directly apply to Hanko's core concerns (encryption, ACL, audit). The filter DSL could be useful for querying vault stats, but that's a minor concern.

### Relevance to Shikki Core: **HIGH**

This is where Haystack shines for Shikki:

- **Pipeline DAG pattern** -- Shikki's `/spec`, `/quick`, `/ship` pipelines are sequential today. Haystack's DAG model with typed sockets, priority scheduling, and breakpoints is a mature implementation of what Shikki's pipeline engine could evolve toward. The `max_runs_per_component` guard is exactly what Shikki's Loop Guard (P1 backlog) needs.
- **Component protocol** -- Haystack's `@component` decorator with typed input/output sockets, JSON serialization, and `warm_up()` lifecycle maps directly to Shikki's plugin system. PluginManifest could adopt socket-based I/O typing for safer plugin composition.
- **Agent component** -- Haystack's `Agent` wraps a chat generator + tool invoker in a loop with breakpoints, state management, and confirmation strategies. This is a production implementation of what ShikiCore's AgentProvider does. Their `ToolExecutionDecision` and `ConfirmationStrategy` patterns are relevant to Shikki's human-in-the-loop approval flow.
- **SuperComponent** -- wrapping a pipeline as a reusable component is exactly how Shikki should compose `/quick` (which is a simplified `/spec + /ship` flow).

### Patterns to Adopt

1. **Typed socket connections for pipelines** -- define explicit input/output types on each pipeline stage. Validate connections at construction time, not runtime. Catches integration errors before execution. Apply to Shikki's `QuickPipeline`, `PrePRGates`, and plugin execution.
2. **DocumentStore filter DSL for Moto queries** -- adopt the nested AND/OR filter format for `moto_get_context(project, filters)`. More powerful than current scope-based access: `{"operator": "AND", "conditions": [{"field": "visibility", "operator": "==", "value": "public"}, {"field": "module", "operator": "in", "value": ["ShikkiKit", "CoreKit"]}]}`.
3. **Max-runs guard for agent loops** -- Haystack's `max_runs_per_component=100` with `PipelineMaxComponentRuns` exception is a simple, proven pattern for Shikki's P1 Loop Guard backlog item. No need to reinvent -- just port the concept.

### Verdict: **ADOPT** (for Shikki Core pipeline patterns)

Haystack's pipeline engine is the most relevant find. The typed-socket DAG model, component protocol, and composability via SuperComponent are patterns Shikki should adopt as its pipeline engine matures. Not a dependency -- Shikki is Swift, Haystack is Python -- but the architecture patterns are directly portable.

---

## Summary Matrix

| Dimension | HashiStack (Vault/Consul/Nomad) | Haystack (deepset) |
|-----------|-------------------------------|-------------------|
| **Stars** | 35k + 30k + 16k | 24.7k |
| **Language** | Go | Python |
| **License** | BUSL-1.1 (Vault/Consul), MPL-2.0 (Nomad) | Apache-2.0 |
| **Moto relevance** | MEDIUM (Consul discovery) | MEDIUM (DocumentStore) |
| **Hanko relevance** | HIGH (Vault secrets model) | LOW |
| **Shikki relevance** | MEDIUM (Nomad dispatch) | HIGH (pipeline engine) |
| **Verdict** | WATCH | ADOPT (patterns) |

## Action Items

1. **[Hanko]** Design lease/TTL model for `hanko grant` based on Vault's secret lease lifecycle. Add to Hanko protocol spec v1.
2. **[Hanko]** Adopt Vault-style HCL policy language for permission scoping instead of flat scope strings.
3. **[Moto]** Add blocking-query/watch mechanism for cache version polling, inspired by Consul KV watches.
4. **[Shikki]** Port Haystack's typed-socket pipeline pattern to Swift for QuickPipeline and PrePRGates.
5. **[Shikki]** Implement max-runs-per-component guard (Loop Guard P1) using Haystack's pattern.
6. **[Moto]** Evaluate Haystack's filter DSL for richer `moto_get_context` queries beyond simple scope access.
