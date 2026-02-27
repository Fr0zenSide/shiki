-- Migration 001: Relax agent_events foreign key constraints
-- The data_sync endpoint and some bulk operations insert events without
-- a specific agent_id or session_id. Make these columns nullable.

ALTER TABLE agent_events ALTER COLUMN agent_id DROP NOT NULL;
ALTER TABLE agent_events ALTER COLUMN session_id DROP NOT NULL;
