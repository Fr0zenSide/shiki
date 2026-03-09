-- Migration 002: Knowledge ingestion sources + Tech radar watchlist & scans
-- Supports /ingest and /radar features

-- ═══════════════════════════════════════════════════════════════════
-- INGESTION SOURCES — tracks what was ingested into agent_memories
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE ingestion_sources (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id   UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    source_type  TEXT NOT NULL CHECK (source_type IN ('github_repo', 'local_path', 'url', 'raw_text')),
    source_uri   TEXT NOT NULL,
    display_name TEXT,
    content_hash TEXT,
    chunk_count  INTEGER NOT NULL DEFAULT 0,
    status       TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'stale')),
    error        TEXT,
    ingested_at  TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    config       JSONB NOT NULL DEFAULT '{}',
    metadata     JSONB NOT NULL DEFAULT '{}'
);

CREATE UNIQUE INDEX idx_ingest_source_dedup ON ingestion_sources(project_id, source_type, source_uri);
CREATE INDEX idx_ingest_source_project ON ingestion_sources(project_id);
CREATE INDEX idx_ingest_source_status  ON ingestion_sources(status);

-- Add metadata GIN index on agent_memories for source_id lookups
CREATE INDEX idx_memories_metadata ON agent_memories USING GIN (metadata);

-- ═══════════════════════════════════════════════════════════════════
-- RADAR WATCHLIST — repos and dependencies to monitor
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE radar_watchlist (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug        TEXT NOT NULL UNIQUE,
    kind        TEXT NOT NULL CHECK (kind IN ('repo', 'dependency', 'technology')),
    name        TEXT NOT NULL,
    source_url  TEXT,
    relevance   TEXT,
    tags        TEXT[] NOT NULL DEFAULT '{}',
    enabled     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata    JSONB NOT NULL DEFAULT '{}'
);

CREATE INDEX idx_radar_watchlist_kind ON radar_watchlist(kind);
CREATE INDEX idx_radar_watchlist_tags ON radar_watchlist USING GIN (tags);

-- ═══════════════════════════════════════════════════════════════════
-- RADAR SCANS — per-item results grouped by scan_run_id
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE radar_scans (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    watchlist_id    UUID NOT NULL REFERENCES radar_watchlist(id) ON DELETE CASCADE,
    scanned_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    scan_run_id     UUID NOT NULL,
    status          TEXT NOT NULL DEFAULT 'ok' CHECK (status IN ('ok', 'update', 'breaking', 'error')),
    current_version TEXT,
    previous_version TEXT,
    releases        JSONB NOT NULL DEFAULT '[]',
    notable_commits JSONB NOT NULL DEFAULT '[]',
    summary         TEXT,
    raw_data        JSONB NOT NULL DEFAULT '{}',
    metadata        JSONB NOT NULL DEFAULT '{}'
);

CREATE INDEX idx_radar_scans_watchlist ON radar_scans(watchlist_id, scanned_at DESC);
CREATE INDEX idx_radar_scans_run      ON radar_scans(scan_run_id);
CREATE INDEX idx_radar_scans_status   ON radar_scans(status);

-- ═══════════════════════════════════════════════════════════════════
-- RADAR DIGESTS — rendered markdown reports per scan run
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE radar_digests (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scan_run_id    UUID NOT NULL UNIQUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    markdown       TEXT NOT NULL,
    item_count     INTEGER NOT NULL DEFAULT 0,
    update_count   INTEGER NOT NULL DEFAULT 0,
    breaking_count INTEGER NOT NULL DEFAULT 0,
    ingested       BOOLEAN NOT NULL DEFAULT FALSE,
    metadata       JSONB NOT NULL DEFAULT '{}'
);

-- ═══════════════════════════════════════════════════════════════════
-- SEED: default watchlist for Shiki's stack
-- ═══════════════════════════════════════════════════════════════════

INSERT INTO radar_watchlist (slug, kind, name, source_url, relevance, tags) VALUES
  ('denoland/deno',           'repo', 'Deno',          'https://github.com/denoland/deno',           'Shiki backend runtime',     '{"shiki-core","runtime"}'),
  ('timescale/timescaledb',   'repo', 'TimescaleDB',   'https://github.com/timescale/timescaledb',   'Shiki DB extension',        '{"shiki-core","database"}'),
  ('pgvector/pgvector',       'repo', 'pgvector',      'https://github.com/pgvector/pgvector',       'Shiki vector storage',      '{"shiki-core","database","vector"}'),
  ('timescale/pgvectorscale', 'repo', 'pgvectorscale', 'https://github.com/timescale/pgvectorscale', 'Shiki vector indexing',     '{"shiki-core","database","vector"}'),
  ('ollama/ollama',           'repo', 'Ollama',        'https://github.com/ollama/ollama',           'Embedding provider',        '{"shiki-core","ai"}'),
  ('anthropics/claude-code',  'repo', 'Claude Code',   'https://github.com/anthropics/claude-code',  'Primary agent interface',   '{"shiki-core","ai"}'),
  ('porsager/postgres',       'repo', 'postgres.js',   'https://github.com/porsager/postgres',       'Deno DB driver',            '{"shiki-core","database"}'),
  ('colinhacks/zod',          'repo', 'Zod',           'https://github.com/colinhacks/zod',          'Schema validation',         '{"shiki-core","validation"}'),
  ('vuejs/core',              'repo', 'Vue.js',        'https://github.com/vuejs/core',              'Shiki dashboard frontend',  '{"shiki-core","frontend"}'),
  ('vitejs/vite',             'repo', 'Vite',          'https://github.com/vitejs/vite',             'Frontend build tool',       '{"shiki-core","frontend"}')
ON CONFLICT (slug) DO NOTHING;
