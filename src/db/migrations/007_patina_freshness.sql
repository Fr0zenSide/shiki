-- Migration 007: Patina Protocol — freshness decay for memories
-- Adds freshness scoring with logarithmic decay from last corroboration.
-- Memories fade over time, corroboration (reference/echo) refreshes them.

-- Freshness: 0.0 (patina/faded) to 1.0 (fresh). Decays from last_corroborated_at.
ALTER TABLE agent_memories
  ADD COLUMN IF NOT EXISTS freshness FLOAT NOT NULL DEFAULT 1.0,
  ADD COLUMN IF NOT EXISTS last_corroborated_at TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS corroboration_count INTEGER NOT NULL DEFAULT 0;

-- Backfill: existing memories get freshness based on age from created_at
-- ln(2) / 30 days ≈ memories lose half freshness every 30 days without corroboration
UPDATE agent_memories
SET
  last_corroborated_at = COALESCE(last_accessed_at, created_at),
  freshness = GREATEST(0.05, EXP(-0.0231 * EXTRACT(EPOCH FROM (NOW() - COALESCE(last_accessed_at, created_at))) / 86400));

-- Function: compute freshness at query time (logarithmic decay)
-- Half-life = 30 days. freshness = exp(-λ * days_since_corroboration)
-- λ = ln(2) / 30 ≈ 0.0231
CREATE OR REPLACE FUNCTION compute_freshness(last_corroborated TIMESTAMPTZ)
RETURNS FLOAT AS $$
BEGIN
  RETURN GREATEST(0.05, EXP(-0.0231 * EXTRACT(EPOCH FROM (NOW() - last_corroborated)) / 86400));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function: corroborate a memory (refresh its freshness)
CREATE OR REPLACE FUNCTION corroborate_memory(memory_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE agent_memories
  SET
    freshness = 1.0,
    last_corroborated_at = NOW(),
    corroboration_count = corroboration_count + 1,
    last_accessed_at = NOW(),
    access_count = access_count + 1
  WHERE id = memory_id;
END;
$$ LANGUAGE plpgsql;

-- Index for freshness-aware queries (find faded memories)
CREATE INDEX IF NOT EXISTS idx_memories_freshness ON agent_memories(freshness);
CREATE INDEX IF NOT EXISTS idx_memories_corroborated ON agent_memories(last_corroborated_at);

COMMENT ON COLUMN agent_memories.freshness IS 'Patina Protocol: 0.05-1.0, decays logarithmically (half-life 30d) from last corroboration';
COMMENT ON COLUMN agent_memories.last_corroborated_at IS 'Last time this memory was referenced, echoed, or confirmed by any source';
COMMENT ON COLUMN agent_memories.corroboration_count IS 'Number of times this memory has been corroborated across its lifetime';
