-- Migration 004: Orchestrator — multi-company autonomous agency
-- Adds companies, task_queue, decision_queue, budget log, and audit trail

-- ═══════════════════════════════════════════════════════════════════
-- COMPANIES — orchestration layer over existing projects
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE companies (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id       UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    slug             TEXT NOT NULL UNIQUE,
    display_name     TEXT NOT NULL,
    status           TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'archived')),
    priority         SMALLINT NOT NULL DEFAULT 5 CHECK (priority >= 0),
    budget           JSONB NOT NULL DEFAULT '{"daily_usd": 5, "monthly_usd": 150, "spent_today_usd": 0}',
    schedule         JSONB NOT NULL DEFAULT '{"active_hours": [8, 22], "timezone": "Europe/Paris", "days": [1,2,3,4,5,6,7]}',
    config           JSONB NOT NULL DEFAULT '{}',
    last_heartbeat_at TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_companies_project ON companies(project_id);
CREATE INDEX idx_companies_status ON companies(status);
CREATE INDEX idx_companies_priority ON companies(priority) WHERE status = 'active';

-- ═══════════════════════════════════════════════════════════════════
-- TASK QUEUE — atomic checkout with goal ancestry (Paperclip pattern)
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE task_queue (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id          UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    parent_id           UUID REFERENCES task_queue(id),
    title               TEXT NOT NULL,
    description         TEXT,
    source              TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('backlog', 'autopilot', 'manual', 'cross_company')),
    status              TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'claimed', 'running', 'blocked', 'completed', 'failed', 'cancelled')),
    claimed_by          UUID,
    claimed_at          TIMESTAMPTZ,
    priority            SMALLINT NOT NULL DEFAULT 5 CHECK (priority >= 0),
    blocking_question_ids UUID[] NOT NULL DEFAULT '{}',
    result              JSONB,
    pipeline_run_id     UUID REFERENCES pipeline_runs(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata            JSONB NOT NULL DEFAULT '{}'
);

CREATE INDEX idx_task_queue_company ON task_queue(company_id);
CREATE INDEX idx_task_queue_status ON task_queue(status);
CREATE INDEX idx_task_queue_priority ON task_queue(company_id, priority, created_at) WHERE status = 'pending';
CREATE INDEX idx_task_queue_parent ON task_queue(parent_id) WHERE parent_id IS NOT NULL;
CREATE INDEX idx_task_queue_claimed ON task_queue(claimed_by) WHERE status IN ('claimed', 'running');

-- ═══════════════════════════════════════════════════════════════════
-- DECISION QUEUE — cross-company blocking questions
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE decision_queue (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id       UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    task_id          UUID REFERENCES task_queue(id),
    pipeline_run_id  UUID REFERENCES pipeline_runs(id),
    tier             SMALLINT NOT NULL DEFAULT 3 CHECK (tier BETWEEN 1 AND 3),
    question         TEXT NOT NULL,
    options          JSONB,
    context          TEXT,
    answered         BOOLEAN NOT NULL DEFAULT FALSE,
    answer           TEXT,
    answered_by      TEXT,
    answered_at      TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata         JSONB NOT NULL DEFAULT '{}'
);

CREATE INDEX idx_decision_queue_company ON decision_queue(company_id);
CREATE INDEX idx_decision_queue_pending ON decision_queue(answered, tier) WHERE answered = FALSE;
CREATE INDEX idx_decision_queue_task ON decision_queue(task_id) WHERE task_id IS NOT NULL;

-- ═══════════════════════════════════════════════════════════════════
-- COMPANY BUDGET LOG — cost tracking (hypertable)
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE company_budget_log (
    occurred_at    TIMESTAMPTZ NOT NULL,
    company_id     UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    amount_usd     NUMERIC(10, 6) NOT NULL,
    cumulative_usd NUMERIC(10, 6) NOT NULL DEFAULT 0,
    source         TEXT NOT NULL,
    metadata       JSONB NOT NULL DEFAULT '{}'
);

SELECT create_hypertable('company_budget_log', 'occurred_at', chunk_time_interval => INTERVAL '1 day');
ALTER TABLE company_budget_log SET (
    timescaledb.compress,
    timescaledb.compress_orderby = 'occurred_at DESC',
    timescaledb.compress_segmentby = 'company_id'
);
SELECT add_compression_policy('company_budget_log', compress_after => INTERVAL '7 days');
CREATE INDEX idx_budget_log_company ON company_budget_log(company_id, occurred_at DESC);

-- ═══════════════════════════════════════════════════════════════════
-- AUDIT LOG — structured mutation trail (hypertable)
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE audit_log (
    occurred_at   TIMESTAMPTZ NOT NULL,
    company_id    UUID REFERENCES companies(id),
    actor         TEXT NOT NULL,
    action        TEXT NOT NULL,
    target_type   TEXT NOT NULL,
    target_id     UUID,
    before_state  JSONB,
    after_state   JSONB,
    metadata      JSONB NOT NULL DEFAULT '{}'
);

SELECT create_hypertable('audit_log', 'occurred_at', chunk_time_interval => INTERVAL '7 days');
ALTER TABLE audit_log SET (
    timescaledb.compress,
    timescaledb.compress_orderby = 'occurred_at DESC',
    timescaledb.compress_segmentby = 'company_id'
);
SELECT add_compression_policy('audit_log', compress_after => INTERVAL '30 days');
CREATE INDEX idx_audit_company ON audit_log(company_id, occurred_at DESC);
CREATE INDEX idx_audit_action ON audit_log(action, occurred_at DESC);
CREATE INDEX idx_audit_target ON audit_log(target_type, target_id, occurred_at DESC);

-- ═══════════════════════════════════════════════════════════════════
-- EXTEND PIPELINE_RUNS — optional company_id FK
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE pipeline_runs ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES companies(id);
CREATE INDEX IF NOT EXISTS idx_pipeline_runs_company ON pipeline_runs(company_id) WHERE company_id IS NOT NULL;

-- ═══════════════════════════════════════════════════════════════════
-- RETENTION POLICIES
-- ═══════════════════════════════════════════════════════════════════

SELECT add_retention_policy('company_budget_log', drop_after => INTERVAL '365 days');
SELECT add_retention_policy('audit_log', drop_after => INTERVAL '365 days');

-- ═══════════════════════════════════════════════════════════════════
-- HELPER VIEWS
-- ═══════════════════════════════════════════════════════════════════

CREATE VIEW company_status AS
SELECT
    c.id,
    c.slug,
    c.display_name,
    c.status,
    c.priority,
    c.budget,
    c.last_heartbeat_at,
    p.slug AS project_slug,
    p.name AS project_name,
    COUNT(tq.id) FILTER (WHERE tq.status = 'pending')   AS pending_tasks,
    COUNT(tq.id) FILTER (WHERE tq.status = 'running')    AS running_tasks,
    COUNT(tq.id) FILTER (WHERE tq.status = 'blocked')    AS blocked_tasks,
    COUNT(tq.id) FILTER (WHERE tq.status = 'completed')  AS completed_tasks,
    COUNT(dq.id) FILTER (WHERE dq.answered = FALSE)       AS pending_decisions,
    CASE
        WHEN c.last_heartbeat_at IS NULL THEN 'never'
        WHEN c.last_heartbeat_at > NOW() - INTERVAL '5 minutes' THEN 'healthy'
        WHEN c.last_heartbeat_at > NOW() - INTERVAL '15 minutes' THEN 'stale'
        ELSE 'dead'
    END AS heartbeat_status
FROM companies c
JOIN projects p ON p.id = c.project_id
LEFT JOIN task_queue tq ON tq.company_id = c.id
LEFT JOIN decision_queue dq ON dq.company_id = c.id
GROUP BY c.id, p.slug, p.name;

CREATE VIEW orchestrator_overview AS
SELECT
    (SELECT COUNT(*) FROM companies WHERE status = 'active')     AS active_companies,
    (SELECT COUNT(*) FROM task_queue WHERE status = 'pending')   AS total_pending_tasks,
    (SELECT COUNT(*) FROM task_queue WHERE status = 'running')   AS total_running_tasks,
    (SELECT COUNT(*) FROM task_queue WHERE status = 'blocked')   AS total_blocked_tasks,
    (SELECT COUNT(*) FROM decision_queue WHERE answered = FALSE) AS total_pending_decisions,
    (SELECT COUNT(*) FROM decision_queue WHERE answered = FALSE AND tier = 1) AS t1_pending_decisions,
    (SELECT COALESCE(SUM(amount_usd), 0) FROM company_budget_log
        WHERE occurred_at >= date_trunc('day', NOW()))           AS today_total_spend;
