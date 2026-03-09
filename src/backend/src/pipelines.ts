import { sql } from "./db.ts";
import { logDebug, logError } from "./middleware.ts";

// ── Types ──────────────────────────────────────────────────────────

export interface PipelineRun {
  id: string;
  pipeline_type: string;
  project_id: string | null;
  session_id: string | null;
  status: string;
  current_phase: string | null;
  state: Record<string, unknown>;
  config: Record<string, unknown>;
  error: string | null;
  started_at: string;
  completed_at: string | null;
  resumed_from: string | null;
  metadata: Record<string, unknown>;
}

export interface PipelineCheckpoint {
  id: string;
  run_id: string;
  phase: string;
  phase_index: number;
  status: string;
  state_before: Record<string, unknown>;
  state_after: Record<string, unknown>;
  output: Record<string, unknown>;
  error: string | null;
  duration_ms: number | null;
  created_at: string;
  metadata: Record<string, unknown>;
}

export interface RoutingRule {
  id: string;
  pipeline_type: string;
  source_phase: string;
  condition: string;
  target_action: string;
  config: Record<string, unknown>;
  priority: number;
  enabled: boolean;
}

// ── Pipeline Run CRUD ──────────────────────────────────────────────

export async function createPipelineRun(input: {
  pipelineType: string;
  projectId?: string;
  sessionId?: string;
  config?: Record<string, unknown>;
  initialState?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
}): Promise<{ id: string }> {
  const [row] = await sql`
    INSERT INTO pipeline_runs (pipeline_type, project_id, session_id, state, config, metadata)
    VALUES (
      ${input.pipelineType},
      ${input.projectId ?? null},
      ${input.sessionId ?? null},
      ${JSON.stringify(input.initialState ?? {})},
      ${JSON.stringify(input.config ?? {})},
      ${JSON.stringify(input.metadata ?? {})}
    )
    RETURNING id
  `;
  logDebug(`Pipeline run created: ${row.id} (${input.pipelineType})`);
  return { id: row.id };
}

export async function getPipelineRun(id: string): Promise<PipelineRun | null> {
  const [row] = await sql`SELECT * FROM pipeline_runs WHERE id = ${id}`;
  return row ?? null;
}

export async function updatePipelineRun(id: string, input: {
  status?: string;
  currentPhase?: string;
  state?: Record<string, unknown>;
  error?: string;
}): Promise<PipelineRun | null> {
  // Build the completed_at logic: set when terminal status
  const isTerminal = input.status === "completed" || input.status === "failed" || input.status === "cancelled";

  const [row] = await sql`
    UPDATE pipeline_runs SET
      status = COALESCE(${input.status ?? null}, status),
      current_phase = COALESCE(${input.currentPhase ?? null}, current_phase),
      state = CASE
        WHEN ${input.state ? JSON.stringify(input.state) : null}::jsonb IS NOT NULL
        THEN state || ${JSON.stringify(input.state ?? {})}::jsonb
        ELSE state
      END,
      error = COALESCE(${input.error ?? null}, error),
      completed_at = CASE WHEN ${isTerminal} THEN NOW() ELSE completed_at END
    WHERE id = ${id}
    RETURNING *
  `;
  return row ?? null;
}

export async function listPipelineRuns(filters: {
  pipelineType?: string;
  status?: string;
  projectId?: string;
  limit?: number;
}): Promise<PipelineRun[]> {
  const limit = Math.min(filters.limit ?? 20, 100);

  if (filters.pipelineType && filters.status) {
    return await sql`
      SELECT * FROM pipeline_runs
      WHERE pipeline_type = ${filters.pipelineType} AND status = ${filters.status}
      ${filters.projectId ? sql`AND project_id = ${filters.projectId}` : sql``}
      ORDER BY started_at DESC LIMIT ${limit}
    `;
  } else if (filters.pipelineType) {
    return await sql`
      SELECT * FROM pipeline_runs
      WHERE pipeline_type = ${filters.pipelineType}
      ${filters.projectId ? sql`AND project_id = ${filters.projectId}` : sql``}
      ORDER BY started_at DESC LIMIT ${limit}
    `;
  } else if (filters.status) {
    return await sql`
      SELECT * FROM pipeline_runs
      WHERE status = ${filters.status}
      ${filters.projectId ? sql`AND project_id = ${filters.projectId}` : sql``}
      ORDER BY started_at DESC LIMIT ${limit}
    `;
  }

  return await sql`
    SELECT * FROM pipeline_runs
    ${filters.projectId ? sql`WHERE project_id = ${filters.projectId}` : sql``}
    ORDER BY started_at DESC LIMIT ${limit}
  `;
}

export async function getLatestPipelineRun(pipelineType?: string): Promise<PipelineRun | null> {
  const [row] = pipelineType
    ? await sql`SELECT * FROM pipeline_runs WHERE pipeline_type = ${pipelineType} ORDER BY started_at DESC LIMIT 1`
    : await sql`SELECT * FROM pipeline_runs ORDER BY started_at DESC LIMIT 1`;
  return row ?? null;
}

// ── Checkpoint CRUD ────────────────────────────────────────────────

export async function addCheckpoint(runId: string, input: {
  phase: string;
  phaseIndex: number;
  status?: string;
  stateBefore?: Record<string, unknown>;
  stateAfter?: Record<string, unknown>;
  output?: Record<string, unknown>;
  error?: string;
  durationMs?: number;
  metadata?: Record<string, unknown>;
}): Promise<{ id: string }> {
  const status = input.status ?? "completed";
  const stateAfter = input.stateAfter ?? {};

  // Upsert checkpoint (idempotent for retries)
  const [row] = await sql`
    INSERT INTO pipeline_checkpoints (run_id, phase, phase_index, status, state_before, state_after, output, error, duration_ms, metadata)
    VALUES (
      ${runId},
      ${input.phase},
      ${input.phaseIndex},
      ${status},
      ${JSON.stringify(input.stateBefore ?? {})},
      ${JSON.stringify(stateAfter)},
      ${JSON.stringify(input.output ?? {})},
      ${input.error ?? null},
      ${input.durationMs ?? null},
      ${JSON.stringify(input.metadata ?? {})}
    )
    ON CONFLICT (run_id, phase) DO UPDATE SET
      status = EXCLUDED.status,
      state_after = EXCLUDED.state_after,
      output = EXCLUDED.output,
      error = EXCLUDED.error,
      duration_ms = EXCLUDED.duration_ms,
      metadata = EXCLUDED.metadata,
      created_at = NOW()
    RETURNING id
  `;

  // Update the run's current_phase and merge state
  await sql`
    UPDATE pipeline_runs SET
      current_phase = ${input.phase},
      state = state || ${JSON.stringify(stateAfter)}::jsonb,
      status = CASE WHEN ${status === "failed"} THEN 'failed' ELSE status END,
      error = CASE WHEN ${status === "failed"} THEN ${input.error ?? null} ELSE error END,
      completed_at = CASE WHEN ${status === "failed"} THEN NOW() ELSE completed_at END
    WHERE id = ${runId}
  `;

  logDebug(`Checkpoint ${input.phase} (${status}) for run ${runId}`);
  return { id: row.id };
}

export async function getCheckpoints(runId: string): Promise<PipelineCheckpoint[]> {
  return await sql`
    SELECT * FROM pipeline_checkpoints WHERE run_id = ${runId} ORDER BY phase_index
  `;
}

export async function getCheckpoint(runId: string, phase: string): Promise<PipelineCheckpoint | null> {
  const [row] = await sql`
    SELECT * FROM pipeline_checkpoints WHERE run_id = ${runId} AND phase = ${phase}
  `;
  return row ?? null;
}

// ── Resume ─────────────────────────────────────────────────────────

export async function resumePipelineRun(failedRunId: string, input: {
  fromPhase?: string;
  stateOverrides?: Record<string, unknown>;
}): Promise<{ newRunId: string; resumeFromPhase: string; resumeFromIndex: number; state: Record<string, unknown> }> {
  // 1. Load the failed run
  const failedRun = await getPipelineRun(failedRunId);
  if (!failedRun) throw new Error(`Pipeline run ${failedRunId} not found`);

  // 2. Get all checkpoints
  const checkpoints = await getCheckpoints(failedRunId);

  // 3. Find resume point
  let resumeFromIndex: number;
  let resumeFromPhase: string;
  let accumulatedState: Record<string, unknown> = {};

  // Helper: ensure JSONB values are objects (postgres.js may return strings)
  const parseJsonb = (val: unknown): Record<string, unknown> => {
    if (typeof val === "string") return JSON.parse(val);
    if (val && typeof val === "object") return val as Record<string, unknown>;
    return {};
  };

  if (input.fromPhase) {
    // User specified a phase to resume from
    const cp = checkpoints.find((c) => c.phase === input.fromPhase);
    resumeFromIndex = cp ? cp.phase_index : 0;
    resumeFromPhase = input.fromPhase;
    // Accumulate state from all checkpoints before this phase
    for (const c of checkpoints) {
      if (c.phase_index < resumeFromIndex && c.status === "completed") {
        accumulatedState = { ...accumulatedState, ...parseJsonb(c.state_after) };
      }
    }
  } else {
    // Find the last successful checkpoint
    const successfulCheckpoints = checkpoints.filter((c) => c.status === "completed");
    if (successfulCheckpoints.length === 0) {
      resumeFromIndex = 0;
      resumeFromPhase = checkpoints[0]?.phase ?? "start";
    } else {
      const lastSuccess = successfulCheckpoints[successfulCheckpoints.length - 1];
      resumeFromIndex = lastSuccess.phase_index + 1;
      resumeFromPhase = checkpoints.find((c) => c.phase_index === resumeFromIndex)?.phase
        ?? `after_${lastSuccess.phase}`;
      // Accumulate state from all successful checkpoints
      for (const c of successfulCheckpoints) {
        accumulatedState = { ...accumulatedState, ...parseJsonb(c.state_after) };
      }
    }
  }

  // Apply overrides
  accumulatedState = { ...accumulatedState, ...(input.stateOverrides ?? {}) };

  // 4. Create new run
  const [newRun] = await sql`
    INSERT INTO pipeline_runs (pipeline_type, project_id, session_id, status, current_phase, state, config, resumed_from, metadata)
    VALUES (
      ${failedRun.pipeline_type},
      ${failedRun.project_id},
      ${failedRun.session_id},
      'resuming',
      ${resumeFromPhase},
      ${JSON.stringify(accumulatedState)},
      ${JSON.stringify(failedRun.config)},
      ${failedRunId},
      ${JSON.stringify({ resumed_at: new Date().toISOString(), original_error: failedRun.error })}
    )
    RETURNING id
  `;

  // 5. Copy successful checkpoints from old run
  const successfulCheckpoints = checkpoints.filter((c) => c.status === "completed" && c.phase_index < resumeFromIndex);
  for (const cp of successfulCheckpoints) {
    await sql`
      INSERT INTO pipeline_checkpoints (run_id, phase, phase_index, status, state_before, state_after, output, duration_ms, metadata)
      VALUES (
        ${newRun.id},
        ${cp.phase},
        ${cp.phase_index},
        'completed',
        ${JSON.stringify(cp.state_before)},
        ${JSON.stringify(cp.state_after)},
        ${JSON.stringify(cp.output)},
        ${cp.duration_ms},
        ${JSON.stringify({ copied_from: failedRunId })}
      )
    `;
  }

  logDebug(`Resumed pipeline ${failedRunId} → ${newRun.id} from phase ${resumeFromPhase} (index ${resumeFromIndex})`);

  return {
    newRunId: newRun.id,
    resumeFromPhase,
    resumeFromIndex,
    state: accumulatedState,
  };
}

// ── Routing Rules ──────────────────────────────────────────────────

export async function evaluateRouting(runId: string, failedPhase: string): Promise<{
  action: string;
  config: Record<string, unknown>;
  retriesUsed: number;
  maxRetries: number;
} | null> {
  // 1. Load the run
  const run = await getPipelineRun(runId);
  if (!run) return null;

  // 2. Get matching rules
  const rules = await sql`
    SELECT * FROM pipeline_routing_rules
    WHERE pipeline_type = ${run.pipeline_type}
      AND source_phase = ${failedPhase}
      AND condition = 'on_failure'
      AND enabled = TRUE
    ORDER BY priority
    LIMIT 1
  `;

  if (rules.length === 0) return null;
  const rule = rules[0];
  const ruleConfig = rule.config as Record<string, unknown>;
  const maxRetries = (ruleConfig.max_retries as number) ?? 3;

  // 3. Count retries across the run chain (follow resumed_from)
  let retriesUsed = 0;
  let currentRunId: string | null = runId;

  while (currentRunId) {
    const failedCheckpoints = await sql`
      SELECT COUNT(*) as count FROM pipeline_checkpoints
      WHERE run_id = ${currentRunId} AND phase = ${failedPhase} AND status = 'failed'
    `;
    retriesUsed += parseInt(failedCheckpoints[0].count);

    // Follow the chain
    const [parentRun] = await sql`SELECT resumed_from FROM pipeline_runs WHERE id = ${currentRunId}`;
    currentRunId = parentRun?.resumed_from ?? null;
  }

  // 4. If retries exhausted, escalate
  if (retriesUsed >= maxRetries) {
    return {
      action: "escalate",
      config: { reason: `Max retries (${maxRetries}) exhausted for ${failedPhase}`, ...ruleConfig },
      retriesUsed,
      maxRetries,
    };
  }

  return {
    action: rule.target_action,
    config: ruleConfig,
    retriesUsed,
    maxRetries,
  };
}

export async function listRoutingRules(pipelineType?: string): Promise<RoutingRule[]> {
  if (pipelineType) {
    return await sql`SELECT * FROM pipeline_routing_rules WHERE pipeline_type = ${pipelineType} ORDER BY pipeline_type, source_phase, priority`;
  }
  return await sql`SELECT * FROM pipeline_routing_rules ORDER BY pipeline_type, source_phase, priority`;
}

export async function createRoutingRule(input: {
  pipelineType: string;
  sourcePhase: string;
  condition: string;
  targetAction: string;
  config?: Record<string, unknown>;
  priority?: number;
  enabled?: boolean;
}): Promise<{ id: string }> {
  const [row] = await sql`
    INSERT INTO pipeline_routing_rules (pipeline_type, source_phase, condition, target_action, config, priority, enabled)
    VALUES (
      ${input.pipelineType},
      ${input.sourcePhase},
      ${input.condition},
      ${input.targetAction},
      ${JSON.stringify(input.config ?? {})},
      ${input.priority ?? 0},
      ${input.enabled ?? true}
    )
    RETURNING id
  `;
  return { id: row.id };
}

export async function updateRoutingRule(id: string, updates: Record<string, unknown>): Promise<RoutingRule | null> {
  const [row] = await sql`
    UPDATE pipeline_routing_rules SET
      pipeline_type = COALESCE(${(updates.pipelineType as string) ?? null}, pipeline_type),
      source_phase = COALESCE(${(updates.sourcePhase as string) ?? null}, source_phase),
      condition = COALESCE(${(updates.condition as string) ?? null}, condition),
      target_action = COALESCE(${(updates.targetAction as string) ?? null}, target_action),
      config = CASE
        WHEN ${updates.config ? JSON.stringify(updates.config) : null}::jsonb IS NOT NULL
        THEN ${JSON.stringify(updates.config ?? {})}::jsonb
        ELSE config
      END,
      enabled = COALESCE(${(updates.enabled as boolean) ?? null}, enabled)
    WHERE id = ${id}
    RETURNING *
  `;
  return row ?? null;
}

export async function deleteRoutingRule(id: string): Promise<boolean> {
  const result = await sql`DELETE FROM pipeline_routing_rules WHERE id = ${id} RETURNING id`;
  return result.length > 0;
}

// ── Pipeline Run Summary ───────────────────────────────────────────

export async function getPipelineRunSummary(id: string) {
  const [row] = await sql`SELECT * FROM pipeline_run_summary WHERE id = ${id}`;
  return row ?? null;
}

export async function listPipelineRunSummaries(limit = 20) {
  return await sql`SELECT * FROM pipeline_run_summary ORDER BY started_at DESC LIMIT ${limit}`;
}
