-- Migration 008: Scheduled Tasks
-- ShikkiKernel Wave 2 — Cron-based task scheduling (BR-16 to BR-37)

CREATE TABLE IF NOT EXISTS scheduled_tasks (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL UNIQUE,
    cron_expression TEXT NOT NULL,
    command         TEXT NOT NULL,
    company_id      TEXT,
    enabled         BOOLEAN NOT NULL DEFAULT true,
    retry_policy    TEXT NOT NULL DEFAULT 'linear',
    estimated_duration_ms INTEGER NOT NULL DEFAULT 60000,
    avg_duration_ms INTEGER,
    last_run_at     TIMESTAMPTZ,
    next_run_at     TIMESTAMPTZ,
    claimed_by      TEXT,
    claimed_at      TIMESTAMPTZ,
    is_builtin      BOOLEAN NOT NULL DEFAULT false,
    speculative     BOOLEAN NOT NULL DEFAULT false,
    retry_count     INTEGER NOT NULL DEFAULT 0,
    max_retries     INTEGER NOT NULL DEFAULT 3,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for TaskSchedulerService query patterns
CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_next_run
    ON scheduled_tasks (next_run_at)
    WHERE enabled = true;

CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_enabled
    ON scheduled_tasks (enabled);

CREATE INDEX IF NOT EXISTS idx_scheduled_tasks_claimed
    ON scheduled_tasks (claimed_by)
    WHERE claimed_by IS NOT NULL;

-- BR-36: Seed built-in tasks
-- corroboration-sweep: daily at 03:00, refreshes stale memories (freshness < 0.3)
INSERT INTO scheduled_tasks (id, name, cron_expression, command, enabled, estimated_duration_ms, is_builtin, max_retries)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'corroboration-sweep',
    '0 3 * * *',
    'corroboration-sweep',
    true,
    300000,
    true,
    3
) ON CONFLICT (id) DO NOTHING;

-- radar-scan: daily at 05:00, GitHub trending to ShikiDB
INSERT INTO scheduled_tasks (id, name, cron_expression, command, enabled, estimated_duration_ms, is_builtin, max_retries)
VALUES (
    '00000000-0000-0000-0000-000000000002',
    'radar-scan',
    '0 5 * * *',
    'radar-scan',
    true,
    180000,
    true,
    3
) ON CONFLICT (id) DO NOTHING;
