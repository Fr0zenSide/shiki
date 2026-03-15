-- Migration 005: Dispatcher Model — multi-project companies + task-based dispatch
-- Adds company_projects join table, project_path on tasks, dispatcher_queue view

-- ═══════════════════════════════════════════════════════════════════
-- COMPANY_PROJECTS — allows 1 company → N projects
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE company_projects (
    company_id  UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    project_id  UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    role        TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('primary', 'member')),
    config      JSONB NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (company_id, project_id)
);

CREATE INDEX idx_company_projects_project ON company_projects(project_id);

-- Migrate existing 1:1 data from companies.project_id
INSERT INTO company_projects (company_id, project_id, role)
SELECT id, project_id, 'primary' FROM companies
ON CONFLICT DO NOTHING;

-- Drop the UNIQUE index on project_id (keep column for backward compat)
DROP INDEX IF EXISTS idx_companies_project;

-- ═══════════════════════════════════════════════════════════════════
-- ADD project_path TO task_queue — each task knows which project dir
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE task_queue ADD COLUMN IF NOT EXISTS project_path TEXT;

-- ═══════════════════════════════════════════════════════════════════
-- UPDATE company_status VIEW — embed project list as JSONB aggregate
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW company_status AS
SELECT
    c.id,
    c.slug,
    c.display_name,
    c.status,
    c.priority,
    c.budget,
    c.schedule,
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
    END AS heartbeat_status,
    COALESCE(
        (SELECT jsonb_agg(jsonb_build_object(
            'project_id', cp.project_id,
            'project_slug', p2.slug,
            'role', cp.role,
            'config', cp.config
        )) FROM company_projects cp
        JOIN projects p2 ON p2.id = cp.project_id
        WHERE cp.company_id = c.id),
        '[]'::jsonb
    ) AS company_projects
FROM companies c
JOIN projects p ON p.id = c.project_id
LEFT JOIN task_queue tq ON tq.company_id = c.id
LEFT JOIN decision_queue dq ON dq.company_id = c.id
GROUP BY c.id, p.slug, p.name;

-- ═══════════════════════════════════════════════════════════════════
-- DISPATCHER_QUEUE VIEW — tasks ready for dispatch, ordered by priority
-- ═══════════════════════════════════════════════════════════════════

CREATE VIEW dispatcher_queue AS
SELECT
    tq.id AS task_id,
    tq.title,
    tq.priority AS task_priority,
    tq.project_path,
    tq.status,
    c.id AS company_id,
    c.slug AS company_slug,
    c.priority AS company_priority,
    c.budget,
    c.schedule,
    COALESCE((SELECT SUM(bl.amount_usd) FROM company_budget_log bl
        WHERE bl.company_id = c.id
        AND bl.occurred_at >= date_trunc('day', NOW())), 0) AS spent_today
FROM task_queue tq
JOIN companies c ON c.id = tq.company_id
WHERE tq.status = 'pending'
  AND c.status = 'active'
ORDER BY c.priority, tq.priority, tq.created_at;
