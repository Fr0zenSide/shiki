# Capacity Audit: Shikki Infrastructure Stack — Multi-Tenant Deployment

**Date**: 2026-04-04
**Scope**: PostgreSQL 17 + TimescaleDB + pgvector, NATS Server, PgBouncer
**Target**: Single Linux VPS, multi-tenant (company-per-tenant)

---

## 1. PostgreSQL 17 + TimescaleDB

### 1.1 Core Limits

| Metric | Limit | Notes |
|---|---|---|
| Max database size | **Unlimited** (practical: petabytes via partitioning) | Single table max: 32 TB (default 8 KB block). 128 TB with 32 KB blocks. |
| Max databases per instance | **No hard limit** | Practical: 50-100 before autovacuum contention and catalog cache pressure degrade performance. Google Cloud SQL stops collecting metrics beyond 500 DBs. |
| Max concurrent connections | **Default 100**, configurable | Each connection forks a dedicated OS process consuming ~5-10 MB RAM. 500 connections = 2.5-5 GB RAM just for connection overhead. |
| Max table size | **32 TB** (default config) | Partitioning extends this effectively without limit. |
| Max columns per table | **1,600** (250-1,600 depending on types) | |
| Max row size | **1.6 TB** (with TOAST) | |
| Max index size | **32 TB** | |

### 1.2 Transactions Per Second (pgbench)

| Hardware | TPS (simple reads) | TPS (read-write mix) | Notes |
|---|---|---|---|
| **2 cores, 4 GB RAM** | ~1,500-2,500 | ~800-1,200 | SSD required. Shared buffers = 1 GB. |
| **4 cores, 16 GB RAM** | ~3,000-4,500 | ~1,500-2,500 | Shared buffers = 4 GB. Sweet spot for small SaaS. |
| **8 cores, 32 GB RAM** | ~6,000-10,000 | ~3,000-5,000 | Shared buffers = 8 GB. NVMe required for write-heavy. |

**Source**: Aiven benchmarks (4 vCPU / 16 GB Ubuntu 22.04): baseline ~2,394 TPS, tuned ~4,487 TPS. Credativ PG18 benchmarks: ~2,489-3,010 TPS across versions. Real-world numbers depend heavily on query complexity and indexing.

### 1.3 Multi-Tenant Database Strategy

| Strategy | Max Tenants (practical) | Overhead | Best For |
|---|---|---|---|
| **Database-per-tenant** | 50-100 per instance | High (autovacuum workers, catalog cache, connection slots per DB) | Strict isolation (regulated industries) |
| **Schema-per-tenant** | 200-500 per instance | Medium (migration loop: 1 migration x N schemas) | Moderate isolation needs |
| **Shared schema + RLS** | 1,000-10,000+ per instance | Low (one set of tables, one migration) | SaaS, cost-optimized |

**Recommendation for Shikki**: Shared schema + RLS (Row-Level Security) with `tenant_id` column. This is what Supabase, Neon, and Crunchy Data recommend for SaaS. Database-per-tenant costs 5-8x more at scale (Neon data).

### 1.4 TimescaleDB Compression

| Metric | Value | Source |
|---|---|---|
| Typical compression ratio | **90-95%** (10-20x) | Production data: 150 GB -> 15 GB (90% reduction). DEV Community report. |
| Best case (ordered time-series) | **95%+** | Adjacent data with trends compresses best. |
| Worst case (random/unordered) | **30-40%** | Random or out-of-order data compresses poorly. |
| Compressed chunk behavior | **Read-only** | INSERT/UPDATE on compressed chunks is slower. Append-mostly workloads only. |
| Default chunk interval | **1 week** | Tunable. Smaller chunks = faster compression, larger = fewer chunks to manage. |

**For Shikki event data** (timestamps, agent events, lifecycle transitions): expect **85-95% compression** since event data is inherently ordered and repetitive.

### 1.5 pgvector Performance

| Scale | Index Type | Query Latency (p50) | QPS (@99% recall) | RAM Required | Notes |
|---|---|---|---|---|---|
| **1M vectors** (768-dim) | HNSW | **1-5 ms** | ~1,000-2,000 | ~6-8 GB | Sweet spot. Sub-10ms guaranteed. |
| **10M vectors** (768-dim) | HNSW | **5-20 ms** | ~200-500 | ~60-80 GB | Needs dedicated memory. Falls to disk at 60% RAM. |
| **10M vectors** (768-dim) | pgvectorscale DiskANN | **15-30 ms** | ~400-600 | ~4-8 GB (index on disk) | Dramatically less RAM. |
| **50M vectors** (768-dim) | pgvectorscale DiskANN | **31 ms (p50)** | **471 QPS** | Index on disk | Timescale benchmark vs. Qdrant (41 QPS). |
| **100M vectors** (768-dim) | pgvectorscale DiskANN | **50-100 ms** | ~100-200 | Index on disk | Competitive with dedicated vector DBs. |
| **100M+ vectors** | Any | Degraded | < 100 | > 1 TB (HNSW) | Consider dedicated vector DB (Milvus, Qdrant). |

**Critical thresholds**:
- HNSW index overhead: **2-3x base vector size** in RAM
- When index reaches **60% of available RAM**, plan next scaling step
- HNSW build for 5M vectors at 1536-dim needs **8-16 GB** maintenance_work_mem
- Default maintenance_work_mem (64 MB) causes **10-50x slower** disk-based builds

**Recommendation for Shikki**: At multi-tenant scale, you likely need < 1M vectors per tenant. Use HNSW for < 5M total vectors, switch to pgvectorscale DiskANN beyond that.

---

## 2. PgBouncer Connection Pooling

### 2.1 How It Changes the Math

| Metric | Without PgBouncer | With PgBouncer |
|---|---|---|
| Max practical concurrent users | **100-300** | **5,000-10,000+** |
| RAM per connection (client side) | ~5-10 MB (PG backend) | ~2-5 KB (PgBouncer lightweight) |
| Backend pool size | N/A | 20-50 physical connections |
| Multiplexing ratio | 1:1 | **100:1 to 500:1** (client:backend) |
| Throughput at 150+ clients | Degraded | **+60% TPS** improvement |

### 2.2 Configuration for Multi-Tenant

```ini
# PgBouncer recommended config for Shikki
[pgbouncer]
pool_mode = transaction          # Only sensible option for web/API
max_client_conn = 5000           # Total clients (all tenants)
default_pool_size = 25           # Backend connections per (user, database) pair
min_pool_size = 5                # Keep warm connections
reserve_pool_size = 5            # Emergency overflow
reserve_pool_timeout = 3         # Seconds before using reserve
max_db_connections = 100         # Total backend connections to PG per database
server_idle_timeout = 300        # Close idle backend connections after 5 min
```

### 2.3 The Multiplexing Math

| Tenants | Users/Tenant | Total Clients | PgBouncer Backend Pool | PG max_connections needed |
|---|---|---|---|---|
| 10 | 50 | 500 | 25 | 50-75 |
| 50 | 50 | 2,500 | 25 | 75-100 |
| 100 | 50 | 5,000 | 25-30 | 100-150 |
| 200 | 50 | 10,000 | 30-40 | 150-200 |

**Key insight**: PgBouncer lets 10,000 logical connections share 150-200 physical PostgreSQL connections. Without it, you hit PostgreSQL's practical limit at ~300-500 connections due to process fork overhead.

**When PgBouncer hurts**: Below ~100 concurrent clients, PgBouncer adds ~2.5x overhead (Percona benchmark). Only use it when you expect > 150 concurrent connections.

---

## 3. NATS Server

### 3.1 Core Limits

| Metric | Value | Notes |
|---|---|---|
| Max concurrent connections (default) | **65,536** | Configurable. Tested to ~1M idle connections on single server. |
| Memory per idle connection | **20-30 KB** | 50K connections = ~1-1.5 GB. 100K connections = ~2-3 GB. |
| Messages/sec (core, 16-byte msgs) | **7.6M msg/sec** (single pub) | 117 MB/sec throughput. |
| Messages/sec (pub+sub, 16-byte) | **2M msg/sec** (aggregate) | With 1 pub + 1 sub. |
| Messages/sec (pub+sub, 100-byte) | **~1M msg/sec** | 6 vCPU, 16 GB (Windows Server). |
| Max subjects | **No hard limit** | Limited by memory. Millions of subjects tested. |
| Core latency (request-reply) | **~51 microseconds** (avg) | At moderate load. |
| Latency at 132K msg/sec | **~374 microseconds** | 50 clients generating load. |

### 3.2 Latency by Load

| Load (msg/sec) | Expected Latency | Storage Mode | Notes |
|---|---|---|---|
| 1K | **< 100 us** | Core (no persist) | Negligible overhead. |
| 10K | **100-500 us** | Core | Still sub-millisecond. |
| 100K | **0.5-2 ms** | Core | Starts hitting scheduling overhead. |
| 1K | **1-5 ms** | JetStream (file) | Disk persistence adds ~10x latency. |
| 10K | **2-10 ms** | JetStream (file) | NVMe recommended. |
| 100K | **5-50 ms** | JetStream (file) | Depends on disk IOPS. |
| 1K-10K | **< 1 ms** | JetStream (memory) | Single-digit millisecond. |

### 3.3 JetStream Limits

| Metric | Value | Notes |
|---|---|---|
| Max HA assets per server | **2,000** (default) | R3/R5 streams + consumers combined. Configurable via max_ha_assets. |
| Max streams (non-HA) | **No hard limit** | Limited by storage and memory. |
| Max consumers per stream | **No hard limit** | Configurable per account. |
| Storage limit | **Disk or memory-bound** | Set via max_mem and max_file in JetStream config. |
| Inflight API requests | **10,000** | Since v2.10.21. Drops requests beyond this to protect memory. |
| 100K+ HA assets | **Supported** | Requires tuning, documented by NATS team. |

### 3.4 Multi-Tenant (Account Isolation)

| Feature | Detail |
|---|---|
| Isolation model | **Accounts** = tenant namespaces. Complete subject isolation by default. |
| Cross-account sharing | Explicit exports/imports only. |
| Per-account limits | max_connections, max_leafnodes, max_subscriptions, max_payload, JetStream quotas |
| Recommended topology | **One account per tenant**. Many small accounts > one large account. |
| Leaf nodes per hub | **No hard limit**. Port 7422 default. |

---

## 4. Practical Multi-Tenant Capacity by Hardware Tier

### 4.1 Small: 2 Cores, 4 GB RAM, SSD

| Component | Capacity | Bottleneck |
|---|---|---|
| PostgreSQL | 5-15 tenants (shared schema) | RAM for shared_buffers (1 GB) + connections |
| pgvector | < 200K vectors total | RAM (HNSW needs in-memory) |
| PgBouncer | 500-1,000 logical connections | CPU (2 cores limits TLS + pooling) |
| NATS | 5,000-10,000 connections | RAM (~300 MB for connections + JetStream) |
| TimescaleDB | ~50 GB uncompressed / ~5 GB compressed | Disk IOPS on SSD |
| **Total tenants** | **5-15 companies, ~10-20 users each** | **RAM is first bottleneck** |

### 4.2 Medium: 4 Cores, 16 GB RAM, NVMe

| Component | Capacity | Bottleneck |
|---|---|---|
| PostgreSQL | 30-100 tenants (shared schema) | Autovacuum workers, connection slots |
| pgvector | < 2M vectors total (HNSW) / 10M+ (DiskANN) | RAM for HNSW index |
| PgBouncer | 5,000-10,000 logical connections -> 100-200 PG backends | Sweet spot for PgBouncer |
| NATS | 50,000+ connections | CPU for message routing |
| TimescaleDB | ~500 GB uncompressed / ~50 GB compressed | Disk space |
| **Total tenants** | **30-100 companies, ~50 users each** | **CPU is first bottleneck** |

### 4.3 Large: 8 Cores, 32 GB RAM, NVMe

| Component | Capacity | Bottleneck |
|---|---|---|
| PostgreSQL | 100-500 tenants (shared schema) | Autovacuum, query planner overhead |
| pgvector | < 5M vectors total (HNSW) / 50M+ (DiskANN) | RAM/disk for index |
| PgBouncer | 10,000+ logical connections -> 200-400 PG backends | Rarely the bottleneck |
| NATS | 100,000+ connections | Network bandwidth |
| TimescaleDB | ~2 TB uncompressed / ~200 GB compressed | Disk space |
| **Total tenants** | **100-500 companies, ~50-100 users each** | **Disk I/O is first bottleneck** |

### 4.4 Bottleneck Progression

```
Small  (2c/4GB):   RAM -> CPU -> Disk I/O -> Network
Medium (4c/16GB):  CPU -> RAM -> Disk I/O -> Network
Large  (8c/32GB):  Disk I/O -> CPU -> RAM -> Network
```

The first bottleneck shifts as you scale. On small servers, RAM is exhausted first (shared_buffers + pgvector + NATS connections). On medium, CPU becomes the limit (query processing + message routing + TLS). On large, disk I/O is the constraint (JetStream persistence + WAL writes + vector index).

---

## 5. Real-World Multi-Tenant Examples

| Company | Stack | Scale | Architecture |
|---|---|---|---|
| **Supabase** | PostgreSQL + PgBouncer | 1M+ projects | Database-per-tenant (each project = isolated PG). Aggressive pooling. |
| **Neon** | PostgreSQL (serverless) | 1M+ databases | Database-per-user with compute scaling to zero. Storage separated from compute. |
| **Crunchy Data** | PostgreSQL | Enterprise | Recommends shared schema + RLS for SaaS. Database-per-tenant for regulated industries. |
| **OpenAI** | PostgreSQL 17 | 800M ChatGPT users | Massive horizontal sharding. Not single-server. |
| **Synadia** (NATS) | NATS | Global SaaS | Multi-account isolation. NGS (NATS Global Service) handles millions of connections across geo-distributed clusters. |

---

## 6. Monitoring Thresholds: When to Scale Up

### 6.1 PostgreSQL

| Metric | Yellow (watch) | Red (scale now) | Tool |
|---|---|---|---|
| Active connections / max_connections | > 60% | > 80% | `pg_stat_activity` |
| CPU usage | > 60% sustained | > 80% sustained | `top`, `pg_stat_statements` |
| Cache hit ratio | < 99% | < 95% | `pg_stat_user_tables` |
| Disk I/O wait | > 10% | > 25% | `iostat`, `pg_stat_io` (PG16+) |
| Transaction ID wraparound | < 500M remaining | < 200M remaining | `pg_database.datfrozenxid` |
| Replication lag | > 1 sec | > 10 sec | `pg_stat_replication` |
| Autovacuum queue depth | > 50 tables pending | > 200 tables pending | `pg_stat_user_tables.n_dead_tup` |
| Temp files created/sec | > 10/sec | > 100/sec | `pg_stat_database` |

### 6.2 PgBouncer

| Metric | Yellow | Red | Tool |
|---|---|---|---|
| Client connections / max_client_conn | > 60% | > 80% | `SHOW POOLS` |
| Avg wait time | > 50 ms | > 200 ms | `SHOW POOLS` (sv_wait) |
| Server connections in use | > 80% of pool | > 95% of pool | `SHOW POOLS` |

### 6.3 NATS

| Metric | Yellow | Red | Tool |
|---|---|---|---|
| Connections / max_connections | > 60% | > 80% | `nats-top`, monitoring endpoint |
| Slow consumers | Any | Sustained | `nats server report` |
| JetStream storage used | > 60% of max | > 80% of max | `nats stream ls` |
| CPU usage | > 60% | > 80% | OS metrics |
| Pending messages (consumer) | > 10K | > 100K | `nats consumer info` |

### 6.4 pgvector

| Metric | Yellow | Red | Tool |
|---|---|---|---|
| Vector index size / available RAM | > 40% | > 60% | `pg_relation_size` on index |
| Search latency (p95) | > 50 ms | > 200 ms | `pg_stat_statements` |
| Index build time | > 1 hour | > 4 hours | Manual monitoring during builds |

---

## 7. Recommendations for Shikki

### Architecture

1. **Use shared schema + RLS** for tenant isolation in PostgreSQL. One `tenant_id` column, one set of tables, one migration path. This is the consensus recommendation from Supabase, Neon, and Crunchy Data for SaaS.

2. **Deploy PgBouncer from day one** in transaction pooling mode. The cost is near-zero and it prevents connection exhaustion as tenants grow. Set `max_client_conn = 5000`, `default_pool_size = 25`.

3. **Use NATS accounts** for tenant isolation. One account per company. Set per-account limits on connections, subscriptions, and JetStream storage.

4. **Start with pgvector HNSW** for vector search. Switch to pgvectorscale DiskANN when total vectors exceed ~2M.

5. **Enable TimescaleDB compression** on event/metrics hypertables older than 7 days. Expect 90%+ compression on ordered event data.

### Starting Configuration (Medium VPS: 4 cores, 16 GB RAM, NVMe)

```
# PostgreSQL
shared_buffers = 4GB
effective_cache_size = 12GB
max_connections = 200
work_mem = 16MB
maintenance_work_mem = 1GB
max_wal_size = 4GB
autovacuum_max_workers = 4

# PgBouncer
pool_mode = transaction
max_client_conn = 5000
default_pool_size = 25
max_db_connections = 150

# NATS
max_connections: 50000
jetstream {
  max_mem: 2G
  max_file: 50G
}
```

### Scaling Triggers

| Trigger | Action |
|---|---|
| > 100 tenants on medium VPS | Upgrade to large (8c/32GB) |
| > 500 tenants on large VPS | Split: dedicated PG server + dedicated NATS server |
| > 5M vectors total | Switch to pgvectorscale DiskANN |
| > 50M vectors total | Dedicated vector search (Qdrant or Milvus sidecar) |
| PG cache hit ratio < 95% | Add RAM or split read replicas |
| NATS slow consumers appearing | Add NATS cluster nodes |
| JetStream storage > 80% | Expand disk or add retention policies |

---

## Sources

- [PostgreSQL 17 max_connections documentation](https://www.postgresql.org/docs/current/runtime-config-connection.html)
- [PostgreSQL Appendix K: Limits](https://www.postgresql.org/docs/current/limits.html)
- [CYBERTEC: max_connections tuning](https://www.cybertec-postgresql.com/en/tuning-max_connections-in-postgresql/)
- [Aiven PostgreSQL benchmarks](https://aiven.io/blog/aiven-for-postgresqlr-performance-benchmarks-across-cloud)
- [TimescaleDB compression: 150GB to 15GB](https://dev.to/polliog/timescaledb-compression-from-150gb-to-15gb-90-reduction-real-production-data-bnj)
- [Cloudflare: TimescaleDB at scale](https://blog.cloudflare.com/timescaledb-art/)
- [pgvectorscale benchmarks (50M vectors)](https://github.com/timescale/pgvectorscale)
- [pgvector scaling: memory, quantization, index strategies](https://dev.to/philip_mcclarence_2ef9475/scaling-pgvector-memory-quantization-and-index-build-strategies-8m2)
- [pgvector HNSW 10M vector build times](https://github.com/pgvector/pgvector/issues/300)
- [Instaclustr pgvector benchmarks](https://www.instaclustr.com/education/vector-database/pgvector-performance-benchmark-results-and-5-ways-to-boost-performance/)
- [NATS benchmarking tool](https://docs.nats.io/using-nats/nats-tools/nats_cli/natsbench)
- [NATS latency tests](https://github.com/nats-io/latency-tests)
- [NATS FAQ: connection limits](https://docs.nats.io/reference/faq)
- [NATS: 1M connections discussion](https://github.com/nats-io/nats-server/discussions/2770)
- [NATS multi-tenant accounts](https://docs.nats.io/running-a-nats-service/configuration/securing_nats/accounts)
- [NATS JetStream configuration](https://docs.nats.io/running-a-nats-service/configuration/resource_management)
- [NATS leaf nodes](https://docs.nats.io/running-a-nats-service/configuration/leafnodes)
- [PgBouncer configuration](https://www.pgbouncer.org/config.html)
- [Percona: PgBouncer benchmarks](https://www.percona.com/blog/scaling-postgresql-with-pgbouncer-you-may-need-a-connection-pooler-sooner-than-you-expect/)
- [Neon: multi-tenancy in Postgres](https://neon.com/blog/multi-tenancy-and-database-per-user-design-in-postgres)
- [Crunchy Data: designing for multi-tenancy](https://www.crunchydata.com/blog/designing-your-postgres-database-for-multi-tenancy)
- [Percona: PgBouncer for enterprise](https://www.percona.com/blog/pgbouncer-for-postgresql-how-connection-pooling-solves-enterprise-slowdowns/)
- [NATS performance optimization](https://oneuptime.com/blog/post/2026-02-02-nats-performance/view)
- [Google Cloud SQL: PostgreSQL quotas](https://cloud.google.com/sql/docs/postgres/quotas)
