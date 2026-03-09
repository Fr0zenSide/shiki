-- Migration 003: Pipeline resilience — checkpointing, typed state, conditional routing
-- Implements LangGraph-inspired durable execution for Shiki pipelines

-- ═══════════════════════════════════════════════════════════════════
-- PIPELINE RUNS — one record per pipeline execution
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE pipeline_runs (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pipeline_type TEXT NOT NULL CHECK (pipeline_type IN ('quick', 'md-feature', 'dispatch', 'pre-pr', 'review')),
    project_id    UUID REFERENCES projects(id),
    session_id    UUID,
    status        TEXT NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'completed', 'failed', 'cancelled', 'resuming')),
    current_phase TEXT,
    state         JSONB NOT NULL DEFAULT '{}',
    config        JSONB NOT NULL DEFAULT '{}',
    error         TEXT,
    started_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at  TIMESTAMPTZ,
    resumed_from  UUID REFERENCES pipeline_runs(id),
    metadata      JSONB NOT NULL DEFAULT '{}'
);

CREATE INDEX idx_pipeline_runs_type    ON pipeline_runs(pipeline_type);
CREATE INDEX idx_pipeline_runs_status  ON pipeline_runs(status);
CREATE INDEX idx_pipeline_runs_project ON pipeline_runs(project_id);
CREATE INDEX idx_pipeline_runs_started ON pipeline_runs(started_at DESC);

-- ═══════════════════════════════════════════════════════════════════
-- PIPELINE CHECKPOINTS — one record per completed phase
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE pipeline_checkpoints (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id       UUID NOT NULL REFERENCES pipeline_runs(id) ON DELETE CASCADE,
    phase        TEXT NOT NULL,
    phase_index  SMALLINT NOT NULL,
    status       TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('completed', 'failed', 'skipped')),
    state_before JSONB NOT NULL DEFAULT '{}',
    state_after  JSONB NOT NULL DEFAULT '{}',
    output       JSONB NOT NULL DEFAULT '{}',
    error        TEXT,
    duration_ms  INTEGER,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata     JSONB NOT NULL DEFAULT '{}'
);

CREATE INDEX idx_checkpoints_run ON pipeline_checkpoints(run_id, phase_index);
CREATE UNIQUE INDEX idx_checkpoints_run_phase ON pipeline_checkpoints(run_id, phase);

-- ═══════════════════════════════════════════════════════════════════
-- PIPELINE ROUTING RULES — conditional routing on failure/success
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE pipeline_routing_rules (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pipeline_type  TEXT NOT NULL,
    source_phase   TEXT NOT NULL,
    condition      TEXT NOT NULL CHECK (condition IN ('on_failure', 'on_success', 'on_skip', 'always')),
    target_action  TEXT NOT NULL,
    config         JSONB NOT NULL DEFAULT '{}',
    priority       SMALLINT NOT NULL DEFAULT 0,
    enabled        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata       JSONB NOT NULL DEFAULT '{}'
);

CREATE INDEX idx_routing_rules_lookup ON pipeline_routing_rules(pipeline_type, source_phase, condition) WHERE enabled = TRUE;

-- ═══════════════════════════════════════════════════════════════════
-- SEED: default routing rules
-- ═══════════════════════════════════════════════════════════════════

INSERT INTO pipeline_routing_rules (pipeline_type, source_phase, condition, target_action, config, priority) VALUES
  -- /pre-pr: auto-fix on review failures, retry on visual QC
  ('pre-pr', 'gate_1a_spec_review',    'on_failure', 'auto_fix',    '{"max_retries": 3, "escalate_to": "daimyo"}', 0),
  ('pre-pr', 'gate_1b_quality_review', 'on_failure', 'auto_fix',    '{"max_retries": 3, "escalate_to": "daimyo"}', 0),
  ('pre-pr', 'gate_3_test_coverage',   'on_failure', 'auto_fix',    '{"max_retries": 3, "escalate_to": "daimyo"}', 0),
  ('pre-pr', 'gate_5_visual_qc',       'on_failure', 'retry_phase', '{"max_retries": 2}', 0),
  ('pre-pr', 'gate_8_ai_slop',         'on_failure', 'auto_fix',    '{"max_retries": 2}', 0),
  -- /md-feature: retry readiness gate
  ('md-feature', 'phase_5b_readiness_gate', 'on_failure', 'retry_phase', '{"max_retries": 2}', 0),
  -- /quick: escalate to md-feature if implementation fails
  ('quick', 'step_2_implementation', 'on_failure', 'escalate', '{"target": "md-feature"}', 0);

-- ═══════════════════════════════════════════════════════════════════
-- HELPER VIEW
-- ═══════════════════════════════════════════════════════════════════

CREATE VIEW pipeline_run_summary AS
SELECT
    pr.id,
    pr.pipeline_type,
    pr.status,
    pr.current_phase,
    pr.started_at,
    pr.completed_at,
    pr.error,
    pr.resumed_from,
    p.slug AS project_slug,
    COUNT(pc.id) AS checkpoint_count,
    MAX(pc.phase_index) AS last_phase_index,
    MAX(pc.phase) FILTER (WHERE pc.status = 'completed') AS last_completed_phase,
    MAX(pc.phase) FILTER (WHERE pc.status = 'failed') AS failed_phase
FROM pipeline_runs pr
LEFT JOIN projects p ON p.id = pr.project_id
LEFT JOIN pipeline_checkpoints pc ON pc.run_id = pr.id
GROUP BY pr.id, p.slug;
