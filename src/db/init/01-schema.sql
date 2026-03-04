-- Shiki (四季) Database Schema
-- PostgreSQL 17 + TimescaleDB + pgvector + pgvectorscale

CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS vectorscale CASCADE;

-- RELATIONAL TABLES
CREATE TABLE projects (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug        TEXT NOT NULL UNIQUE,
    name        TEXT NOT NULL,
    description TEXT,
    repo_url    TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata    JSONB NOT NULL DEFAULT '{}'
);

CREATE TABLE sessions (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id   UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name         TEXT NOT NULL,
    branch       TEXT,
    status       TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'completed', 'failed')),
    started_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at     TIMESTAMPTZ,
    summary      TEXT,
    metadata     JSONB NOT NULL DEFAULT '{}'
);
CREATE INDEX idx_sessions_project ON sessions(project_id);
CREATE INDEX idx_sessions_status  ON sessions(status);

CREATE TABLE agents (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id   UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    project_id   UUID NOT NULL REFERENCES projects(id),
    handle       TEXT NOT NULL,
    role         TEXT NOT NULL,
    model        TEXT NOT NULL,
    spawned_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    status       TEXT NOT NULL DEFAULT 'spawned' CHECK (status IN ('spawned', 'running', 'completed', 'failed', 'cancelled')),
    parent_id    UUID REFERENCES agents(id),
    metadata     JSONB NOT NULL DEFAULT '{}'
);
CREATE INDEX idx_agents_session ON agents(session_id);
CREATE INDEX idx_agents_handle  ON agents(handle);
CREATE INDEX idx_agents_status  ON agents(status);

CREATE TABLE decisions (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id   UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    agent_id     UUID REFERENCES agents(id),
    question     TEXT NOT NULL,
    options      JSONB,
    chosen       TEXT,
    rationale    TEXT,
    decided_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata     JSONB NOT NULL DEFAULT '{}'
);
CREATE INDEX idx_decisions_session ON decisions(session_id);

-- TIME-SERIES TABLES (hypertables)
CREATE TABLE agent_events (
    occurred_at  TIMESTAMPTZ NOT NULL,
    agent_id     UUID REFERENCES agents(id),
    session_id   UUID,
    project_id   UUID NOT NULL,
    event_type   TEXT NOT NULL,
    payload      JSONB NOT NULL DEFAULT '{}',
    progress_pct SMALLINT,
    message      TEXT
);
SELECT create_hypertable('agent_events', 'occurred_at', chunk_time_interval => INTERVAL '1 day');
ALTER TABLE agent_events SET (timescaledb.compress, timescaledb.compress_orderby = 'occurred_at DESC', timescaledb.compress_segmentby = 'project_id, session_id');
SELECT add_compression_policy('agent_events', compress_after => INTERVAL '7 days');
CREATE INDEX idx_agent_events_agent   ON agent_events(agent_id,   occurred_at DESC);
CREATE INDEX idx_agent_events_session ON agent_events(session_id, occurred_at DESC);
CREATE INDEX idx_agent_events_type    ON agent_events(event_type, occurred_at DESC);

CREATE TABLE chat_messages (
    occurred_at  TIMESTAMPTZ NOT NULL,
    id           UUID NOT NULL DEFAULT gen_random_uuid(),
    session_id   UUID NOT NULL,
    project_id   UUID NOT NULL,
    agent_id     UUID REFERENCES agents(id),
    role         TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system', 'orchestrator')),
    content      TEXT NOT NULL,
    token_count  INTEGER,
    metadata     JSONB NOT NULL DEFAULT '{}'
);
SELECT create_hypertable('chat_messages', 'occurred_at', chunk_time_interval => INTERVAL '7 days');
ALTER TABLE chat_messages SET (timescaledb.compress, timescaledb.compress_orderby = 'occurred_at DESC', timescaledb.compress_segmentby = 'session_id');
SELECT add_compression_policy('chat_messages', compress_after => INTERVAL '30 days');
CREATE INDEX idx_chat_session  ON chat_messages(session_id, occurred_at DESC);
CREATE INDEX idx_chat_agent    ON chat_messages(agent_id,   occurred_at DESC);
CREATE INDEX idx_chat_fts ON chat_messages USING GIN (to_tsvector('english', content));

CREATE TABLE performance_metrics (
    occurred_at       TIMESTAMPTZ NOT NULL,
    agent_id          UUID NOT NULL,
    session_id        UUID NOT NULL,
    project_id        UUID NOT NULL,
    metric_type       TEXT NOT NULL,
    tokens_input      INTEGER,
    tokens_output     INTEGER,
    duration_ms       INTEGER,
    cost_usd          NUMERIC(10, 6),
    model             TEXT,
    metadata          JSONB NOT NULL DEFAULT '{}'
);
SELECT create_hypertable('performance_metrics', 'occurred_at', chunk_time_interval => INTERVAL '1 day');
ALTER TABLE performance_metrics SET (timescaledb.compress, timescaledb.compress_orderby = 'occurred_at DESC', timescaledb.compress_segmentby = 'project_id, agent_id');
SELECT add_compression_policy('performance_metrics', compress_after => INTERVAL '7 days');
CREATE INDEX idx_perf_agent   ON performance_metrics(agent_id,   occurred_at DESC);
CREATE INDEX idx_perf_session ON performance_metrics(session_id, occurred_at DESC);
CREATE INDEX idx_perf_project ON performance_metrics(project_id, occurred_at DESC);

CREATE TABLE git_events (
    occurred_at   TIMESTAMPTZ NOT NULL,
    project_id    UUID NOT NULL,
    session_id    UUID,
    agent_id      UUID,
    event_type    TEXT NOT NULL,
    ref           TEXT,
    commit_sha    TEXT,
    commit_msg    TEXT,
    author        TEXT,
    files_changed INTEGER,
    additions     INTEGER,
    deletions     INTEGER,
    metadata      JSONB NOT NULL DEFAULT '{}'
);
SELECT create_hypertable('git_events', 'occurred_at', chunk_time_interval => INTERVAL '7 days');
ALTER TABLE git_events SET (timescaledb.compress, timescaledb.compress_orderby = 'occurred_at DESC', timescaledb.compress_segmentby = 'project_id');
SELECT add_compression_policy('git_events', compress_after => INTERVAL '30 days');
CREATE INDEX idx_git_project ON git_events(project_id, occurred_at DESC);
CREATE INDEX idx_git_ref     ON git_events(ref, occurred_at DESC);

-- VECTOR MEMORY TABLE
CREATE TABLE agent_memories (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id   UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    session_id   UUID REFERENCES sessions(id),
    agent_id     UUID REFERENCES agents(id),
    content      TEXT NOT NULL,
    category     TEXT NOT NULL DEFAULT 'general',
    embedding    vector(768),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_accessed_at TIMESTAMPTZ,
    access_count INTEGER NOT NULL DEFAULT 0,
    importance   FLOAT NOT NULL DEFAULT 1.0,
    metadata     JSONB NOT NULL DEFAULT '{}'
);
CREATE INDEX idx_memories_embedding ON agent_memories USING diskann (embedding vector_cosine_ops);
CREATE INDEX idx_memories_project  ON agent_memories(project_id);
CREATE INDEX idx_memories_category ON agent_memories(category);
CREATE INDEX idx_memories_session  ON agent_memories(session_id);

-- CONTINUOUS AGGREGATES
CREATE MATERIALIZED VIEW agent_activity_hourly
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', occurred_at) AS bucket, project_id, session_id, event_type, COUNT(*) AS event_count
FROM agent_events GROUP BY bucket, project_id, session_id, event_type WITH NO DATA;
SELECT add_continuous_aggregate_policy('agent_activity_hourly', start_offset => INTERVAL '3 hours', end_offset => INTERVAL '1 minute', schedule_interval => INTERVAL '1 hour');

CREATE MATERIALIZED VIEW daily_performance
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 day', occurred_at) AS bucket, project_id, model, COUNT(*) AS api_calls, SUM(tokens_input) AS total_tokens_input, SUM(tokens_output) AS total_tokens_output, SUM(tokens_input + tokens_output) AS total_tokens, SUM(cost_usd) AS total_cost_usd, AVG(duration_ms) AS avg_duration_ms, PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_ms) AS p95_duration_ms
FROM performance_metrics WHERE metric_type = 'api_call' GROUP BY bucket, project_id, model WITH NO DATA;
SELECT add_continuous_aggregate_policy('daily_performance', start_offset => INTERVAL '3 days', end_offset => INTERVAL '1 hour', schedule_interval => INTERVAL '1 hour');

CREATE MATERIALIZED VIEW daily_git_activity
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 day', occurred_at) AS bucket, project_id, event_type, COUNT(*) AS event_count, SUM(additions) AS total_additions, SUM(deletions) AS total_deletions, SUM(files_changed) AS total_files_changed
FROM git_events GROUP BY bucket, project_id, event_type WITH NO DATA;
SELECT add_continuous_aggregate_policy('daily_git_activity', start_offset => INTERVAL '3 days', end_offset => INTERVAL '1 hour', schedule_interval => INTERVAL '1 hour');

-- RETENTION POLICIES
SELECT add_retention_policy('agent_events', drop_after => INTERVAL '90 days');
SELECT add_retention_policy('chat_messages', drop_after => INTERVAL '365 days');
SELECT add_retention_policy('performance_metrics', drop_after => INTERVAL '365 days');

-- HELPER VIEWS
CREATE VIEW active_sessions AS
SELECT s.id, s.name, s.branch, s.started_at, p.slug AS project_slug, p.name AS project_name, EXTRACT(EPOCH FROM (NOW() - s.started_at))/3600 AS hours_active
FROM sessions s JOIN projects p ON p.id = s.project_id WHERE s.status = 'active';

CREATE VIEW agent_cost_leaderboard AS
SELECT a.handle, a.model, a.status, COUNT(pm.*) AS api_calls, SUM(pm.tokens_input + pm.tokens_output) AS total_tokens, SUM(pm.cost_usd) AS total_cost_usd
FROM agents a LEFT JOIN performance_metrics pm ON pm.agent_id = a.id GROUP BY a.id, a.handle, a.model, a.status ORDER BY total_cost_usd DESC NULLS LAST;
