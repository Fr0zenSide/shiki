-- Migration 006: Session Transcripts — structured capture of autonomous Claude session output
-- Stores plans, decisions, PRs, test results, and compressed raw logs per task session.

-- ═══════════════════════════════════════════════════════════════════
-- SESSION_TRANSCRIPTS — one row per completed/failed task session
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE session_transcripts (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id       UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    task_id          UUID REFERENCES task_queue(id) ON DELETE SET NULL,
    session_id       TEXT NOT NULL,
    company_slug     TEXT NOT NULL,
    task_title       TEXT NOT NULL,
    project_path     TEXT,

    -- Structured content (what the user actually wants to read)
    summary          TEXT,
    plan_output      TEXT,
    files_changed    TEXT[] NOT NULL DEFAULT '{}',
    test_results     TEXT,
    prs_created      TEXT[] NOT NULL DEFAULT '{}',
    decisions        JSONB NOT NULL DEFAULT '[]',
    errors           TEXT[] NOT NULL DEFAULT '{}',

    -- Session metadata
    phase            TEXT NOT NULL DEFAULT 'completed'
                     CHECK (phase IN ('plan', 'implement', 'review', 'blocked', 'completed', 'failed')),
    duration_minutes INT,
    context_pct      INT,
    compaction_count INT DEFAULT 0,

    -- Raw log (compressed fallback — auto-purged after 30 days)
    raw_log          TEXT,

    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_transcripts_company ON session_transcripts(company_id, created_at DESC);
CREATE INDEX idx_transcripts_task ON session_transcripts(task_id) WHERE task_id IS NOT NULL;
CREATE INDEX idx_transcripts_slug ON session_transcripts(company_slug, created_at DESC);
CREATE INDEX idx_transcripts_phase ON session_transcripts(phase) WHERE phase NOT IN ('completed', 'failed');

-- ═══════════════════════════════════════════════════════════════════
-- BOARD_OVERVIEW VIEW — rich snapshot for `shiki board` / `shiki-ctl board`
-- ═══════════════════════════════════════════════════════════════════

CREATE VIEW board_overview AS
SELECT
    c.id AS company_id,
    c.slug AS company_slug,
    c.display_name,
    c.status AS company_status,
    c.priority,
    c.budget,
    c.schedule,
    c.last_heartbeat_at,

    -- Task counts
    COUNT(tq.id) FILTER (WHERE tq.status = 'pending')   AS pending_tasks,
    COUNT(tq.id) FILTER (WHERE tq.status = 'running')   AS running_tasks,
    COUNT(tq.id) FILTER (WHERE tq.status = 'blocked')   AS blocked_tasks,
    COUNT(tq.id) FILTER (WHERE tq.status = 'completed') AS completed_tasks,
    COUNT(tq.id) FILTER (WHERE tq.status = 'failed')    AS failed_tasks,
    COUNT(tq.id)                                         AS total_tasks,

    -- Budget
    COALESCE((SELECT SUM(bl.amount_usd) FROM company_budget_log bl
        WHERE bl.company_id = c.id
        AND bl.occurred_at >= date_trunc('day', NOW())), 0) AS spent_today,

    -- Health
    CASE
        WHEN c.last_heartbeat_at IS NULL THEN 'never'
        WHEN c.last_heartbeat_at > NOW() - INTERVAL '5 minutes' THEN 'healthy'
        WHEN c.last_heartbeat_at > NOW() - INTERVAL '15 minutes' THEN 'stale'
        ELSE 'dead'
    END AS heartbeat_status,

    -- Latest transcript summary (most recent session for this company)
    (SELECT st.summary FROM session_transcripts st
     WHERE st.company_id = c.id
     ORDER BY st.created_at DESC LIMIT 1) AS last_session_summary,

    (SELECT st.phase FROM session_transcripts st
     WHERE st.company_id = c.id
     ORDER BY st.created_at DESC LIMIT 1) AS last_session_phase,

    (SELECT st.created_at FROM session_transcripts st
     WHERE st.company_id = c.id
     ORDER BY st.created_at DESC LIMIT 1) AS last_session_at,

    -- Pending decisions count
    COUNT(dq.id) FILTER (WHERE dq.answered = FALSE) AS pending_decisions,

    -- Project count
    (SELECT COUNT(*) FROM company_projects cp WHERE cp.company_id = c.id) AS project_count

FROM companies c
LEFT JOIN task_queue tq ON tq.company_id = c.id
LEFT JOIN decision_queue dq ON dq.company_id = c.id
WHERE c.status != 'archived'
GROUP BY c.id;
