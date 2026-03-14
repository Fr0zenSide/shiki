import { sql } from "./db.ts";
import { logDebug } from "./middleware.ts";

// deno-lint-ignore no-explicit-any
type Row = any;

// ── Company CRUD ──────────────────────────────────────────────────

export async function createCompany(input: {
  projectId: string;
  slug: string;
  displayName: string;
  priority?: number;
  budget?: Record<string, unknown>;
  schedule?: Record<string, unknown>;
  config?: Record<string, unknown>;
}): Promise<Row> {
  const [row] = await sql`
    INSERT INTO companies (project_id, slug, display_name, priority, budget, schedule, config)
    VALUES (
      ${input.projectId},
      ${input.slug},
      ${input.displayName},
      ${input.priority ?? 5},
      ${JSON.stringify(input.budget ?? { daily_usd: 5, monthly_usd: 150, spent_today_usd: 0 })},
      ${JSON.stringify(input.schedule ?? { active_hours: [8, 22], timezone: "Europe/Paris", days: [1,2,3,4,5,6,7] })},
      ${JSON.stringify(input.config ?? {})}
    )
    RETURNING *
  `;
  logDebug(`Company created: ${row.slug} (${row.id})`);
  return row;
}

export async function getCompany(id: string): Promise<Row | null> {
  const [row] = await sql`SELECT * FROM companies WHERE id = ${id}`;
  return row ?? null;
}

export async function listCompanies(status?: string): Promise<Row[]> {
  if (status) {
    return await sql`SELECT * FROM companies WHERE status = ${status} ORDER BY priority, slug`;
  }
  return await sql`SELECT * FROM companies ORDER BY priority, slug`;
}

export async function updateCompany(id: string, updates: {
  status?: string;
  priority?: number;
  budget?: Record<string, unknown>;
  schedule?: Record<string, unknown>;
  config?: Record<string, unknown>;
  displayName?: string;
}): Promise<Row | null> {
  const [row] = await sql`
    UPDATE companies SET
      status = COALESCE(${updates.status ?? null}, status),
      priority = COALESCE(${updates.priority ?? null}, priority),
      budget = CASE
        WHEN ${updates.budget ? JSON.stringify(updates.budget) : null}::jsonb IS NOT NULL
        THEN ${JSON.stringify(updates.budget ?? {})}::jsonb
        ELSE budget
      END,
      schedule = CASE
        WHEN ${updates.schedule ? JSON.stringify(updates.schedule) : null}::jsonb IS NOT NULL
        THEN ${JSON.stringify(updates.schedule ?? {})}::jsonb
        ELSE schedule
      END,
      config = CASE
        WHEN ${updates.config ? JSON.stringify(updates.config) : null}::jsonb IS NOT NULL
        THEN config || ${JSON.stringify(updates.config ?? {})}::jsonb
        ELSE config
      END,
      display_name = COALESCE(${updates.displayName ?? null}, display_name),
      updated_at = NOW()
    WHERE id = ${id}
    RETURNING *
  `;
  return row ?? null;
}

export async function recordHeartbeat(companyId: string): Promise<void> {
  await sql`
    UPDATE companies SET last_heartbeat_at = NOW(), updated_at = NOW()
    WHERE id = ${companyId}
  `;
}

// ── Company Status View ───────────────────────────────────────────

export async function getCompanyStatus(id: string) {
  const [row] = await sql`SELECT * FROM company_status WHERE id = ${id}`;
  return row ?? null;
}

export async function getOrchestratorOverview() {
  const [row] = await sql`SELECT * FROM orchestrator_overview`;
  return row ?? null;
}

// ── Task Queue CRUD ───────────────────────────────────────────────

export async function createTask(input: {
  companyId: string;
  title: string;
  description?: string;
  source?: string;
  priority?: number;
  parentId?: string;
  metadata?: Record<string, unknown>;
}): Promise<Row> {
  const [row] = await sql`
    INSERT INTO task_queue (company_id, title, description, source, priority, parent_id, metadata)
    VALUES (
      ${input.companyId},
      ${input.title},
      ${input.description ?? null},
      ${input.source ?? "manual"},
      ${input.priority ?? 5},
      ${input.parentId ?? null},
      ${JSON.stringify(input.metadata ?? {})}
    )
    RETURNING *
  `;
  logDebug(`Task created: ${row.title} (${row.id}) for company ${input.companyId}`);
  return row;
}

export async function getTask(id: string): Promise<Row | null> {
  const [row] = await sql`SELECT * FROM task_queue WHERE id = ${id}`;
  return row ?? null;
}

export async function listTasks(companyId: string, status?: string): Promise<Row[]> {
  if (status) {
    return await sql`
      SELECT * FROM task_queue
      WHERE company_id = ${companyId} AND status = ${status}
      ORDER BY priority, created_at
    `;
  }
  return await sql`
    SELECT * FROM task_queue
    WHERE company_id = ${companyId}
    ORDER BY priority, created_at
  `;
}

export async function updateTask(id: string, updates: {
  status?: string;
  result?: Record<string, unknown>;
  blockingQuestionIds?: string[];
  pipelineRunId?: string;
  metadata?: Record<string, unknown>;
}): Promise<Row | null> {
  const [row] = await sql`
    UPDATE task_queue SET
      status = COALESCE(${updates.status ?? null}, status),
      result = CASE
        WHEN ${updates.result ? JSON.stringify(updates.result) : null}::jsonb IS NOT NULL
        THEN ${JSON.stringify(updates.result ?? {})}::jsonb
        ELSE result
      END,
      blocking_question_ids = COALESCE(${updates.blockingQuestionIds ?? null}, blocking_question_ids),
      pipeline_run_id = COALESCE(${updates.pipelineRunId ?? null}, pipeline_run_id),
      metadata = CASE
        WHEN ${updates.metadata ? JSON.stringify(updates.metadata) : null}::jsonb IS NOT NULL
        THEN metadata || ${JSON.stringify(updates.metadata ?? {})}::jsonb
        ELSE metadata
      END,
      updated_at = NOW()
    WHERE id = ${id}
    RETURNING *
  `;
  return row ?? null;
}

/**
 * Atomic task claim — uses FOR UPDATE SKIP LOCKED to avoid races.
 * Returns the claimed task or null if none available.
 */
export async function claimTask(companyId: string, sessionId: string): Promise<Row | null> {
  const [row] = await sql`
    UPDATE task_queue SET
      status = 'claimed',
      claimed_by = ${sessionId}::uuid,
      claimed_at = NOW(),
      updated_at = NOW()
    WHERE id = (
      SELECT id FROM task_queue
      WHERE company_id = ${companyId}
        AND status = 'pending'
      ORDER BY priority, created_at
      LIMIT 1
      FOR UPDATE SKIP LOCKED
    )
    RETURNING *
  `;
  if (row) {
    logDebug(`Task claimed: ${row.title} (${row.id}) by session ${sessionId}`);
  }
  return row ?? null;
}

// ── Decision Queue CRUD ───────────────────────────────────────────

export async function createDecision(input: {
  companyId: string;
  taskId?: string;
  pipelineRunId?: string;
  tier: number;
  question: string;
  options?: Record<string, unknown>;
  context?: string;
  metadata?: Record<string, unknown>;
}): Promise<Row> {
  const [row] = await sql`
    INSERT INTO decision_queue (company_id, task_id, pipeline_run_id, tier, question, options, context, metadata)
    VALUES (
      ${input.companyId},
      ${input.taskId ?? null},
      ${input.pipelineRunId ?? null},
      ${input.tier},
      ${input.question},
      ${input.options ? JSON.stringify(input.options) : null},
      ${input.context ?? null},
      ${JSON.stringify(input.metadata ?? {})}
    )
    RETURNING *
  `;
  logDebug(`Decision created: tier ${input.tier} for company ${input.companyId}`);
  return row;
}

export async function getDecision(id: string): Promise<Row | null> {
  const [row] = await sql`SELECT * FROM decision_queue WHERE id = ${id}`;
  return row ?? null;
}

export async function listDecisions(filters: {
  companyId?: string;
  answered?: boolean;
  tier?: number;
}): Promise<Row[]> {
  if (filters.companyId && filters.answered !== undefined) {
    return await sql`
      SELECT * FROM decision_queue
      WHERE company_id = ${filters.companyId} AND answered = ${filters.answered}
      ${filters.tier ? sql`AND tier = ${filters.tier}` : sql``}
      ORDER BY tier, created_at
    `;
  }
  if (filters.companyId) {
    return await sql`
      SELECT * FROM decision_queue
      WHERE company_id = ${filters.companyId}
      ORDER BY tier, created_at
    `;
  }
  if (filters.answered !== undefined) {
    return await sql`
      SELECT * FROM decision_queue
      WHERE answered = ${filters.answered}
      ${filters.tier ? sql`AND tier = ${filters.tier}` : sql``}
      ORDER BY tier, created_at
    `;
  }
  return await sql`SELECT * FROM decision_queue ORDER BY tier, created_at`;
}

export async function getPendingDecisions(): Promise<Row[]> {
  return await sql`
    SELECT dq.*, c.slug AS company_slug, c.display_name AS company_name
    FROM decision_queue dq
    JOIN companies c ON c.id = dq.company_id
    WHERE dq.answered = FALSE
    ORDER BY dq.tier, dq.created_at
  `;
}

export async function answerDecision(id: string, input: {
  answer: string;
  answeredBy: string;
}): Promise<Row | null> {
  const [row] = await sql`
    UPDATE decision_queue SET
      answered = TRUE,
      answer = ${input.answer},
      answered_by = ${input.answeredBy},
      answered_at = NOW()
    WHERE id = ${id}
    RETURNING *
  `;

  if (row && row.task_id) {
    // Check if all blocking decisions for this task are now answered
    const remaining = await sql`
      SELECT COUNT(*) as count FROM decision_queue
      WHERE task_id = ${row.task_id} AND answered = FALSE
    `;
    if (parseInt(remaining[0].count) === 0) {
      // Unblock the task
      await sql`
        UPDATE task_queue SET
          status = 'pending',
          blocking_question_ids = '{}',
          updated_at = NOW()
        WHERE id = ${row.task_id} AND status = 'blocked'
      `;
      logDebug(`Task ${row.task_id} unblocked — all decisions answered`);
    }
  }

  return row ?? null;
}

// ── Budget Tracking ───────────────────────────────────────────────

export async function logBudgetEntry(input: {
  companyId: string;
  amountUsd: number;
  source: string;
  metadata?: Record<string, unknown>;
}): Promise<void> {
  // Get current cumulative for today
  const [cum] = await sql`
    SELECT COALESCE(MAX(cumulative_usd), 0) as total
    FROM company_budget_log
    WHERE company_id = ${input.companyId}
      AND occurred_at >= date_trunc('day', NOW())
  `;
  const cumulative = parseFloat(cum.total) + input.amountUsd;

  await sql`
    INSERT INTO company_budget_log (occurred_at, company_id, amount_usd, cumulative_usd, source, metadata)
    VALUES (NOW(), ${input.companyId}, ${input.amountUsd}, ${cumulative}, ${input.source}, ${JSON.stringify(input.metadata ?? {})})
  `;

  // Update the company's spent_today_usd
  await sql`
    UPDATE companies SET
      budget = jsonb_set(budget, '{spent_today_usd}', to_jsonb(${cumulative}::numeric)),
      updated_at = NOW()
    WHERE id = ${input.companyId}
  `;
}

export async function getTodaySpend(companyId: string): Promise<number> {
  const [row] = await sql`
    SELECT COALESCE(SUM(amount_usd), 0) as total
    FROM company_budget_log
    WHERE company_id = ${companyId}
      AND occurred_at >= date_trunc('day', NOW())
  `;
  return parseFloat(row.total);
}

// ── Stale Company Detection ───────────────────────────────────────

export async function getStaleCompanies(thresholdMinutes = 5): Promise<Row[]> {
  return await sql`
    SELECT c.*, p.slug AS project_slug
    FROM companies c
    JOIN projects p ON p.id = c.project_id
    WHERE c.status = 'active'
      AND c.last_heartbeat_at IS NOT NULL
      AND c.last_heartbeat_at < NOW() - make_interval(mins => ${thresholdMinutes})
  `;
}

export async function getCompaniesWithPendingTasks(): Promise<Row[]> {
  return await sql`
    SELECT c.*, p.slug AS project_slug,
      COUNT(tq.id) AS pending_count
    FROM companies c
    JOIN projects p ON p.id = c.project_id
    JOIN task_queue tq ON tq.company_id = c.id AND tq.status = 'pending'
    WHERE c.status = 'active'
    GROUP BY c.id, p.slug
    ORDER BY c.priority, c.slug
  `;
}

// ── Cross-Company Package Lock ────────────────────────────────────

/**
 * Attempt to acquire a lock for a shared package.
 * Returns the lock task if acquired, null if already locked by another company.
 */
export async function acquirePackageLock(companyId: string, packageName: string, sessionId: string): Promise<Row | null> {
  const existing = await sql`
    SELECT tq.*, c.slug AS company_slug
    FROM task_queue tq
    JOIN companies c ON c.id = tq.company_id
    WHERE tq.source = 'cross_company'
      AND tq.status IN ('claimed', 'running')
      AND tq.metadata->>'package' = ${packageName}
      AND tq.company_id != ${companyId}
  `;

  if (existing.length > 0) {
    logDebug(`Package lock denied: ${packageName} held by ${existing[0].company_slug}`);
    return null;
  }

  const lockMeta = { package: packageName };
  const [row] = await sql`
    INSERT INTO task_queue (company_id, title, source, status, claimed_by, claimed_at, priority, metadata)
    VALUES (
      ${companyId},
      ${'cross-company: ' + packageName},
      'cross_company',
      'running',
      ${sessionId}::uuid,
      NOW(),
      0,
      ${sql.json(lockMeta)}
    )
    RETURNING *
  `;
  logDebug(`Package lock acquired: ${packageName} by company ${companyId}`);
  return row;
}

/**
 * Release a package lock by completing the lock task.
 */
export async function releasePackageLock(packageName: string, companyId: string): Promise<boolean> {
  const result = await sql`
    UPDATE task_queue SET
      status = 'completed',
      result = ${JSON.stringify({ released_at: new Date().toISOString() })},
      updated_at = NOW()
    WHERE source = 'cross_company'
      AND status IN ('claimed', 'running')
      AND metadata->>'package' = ${packageName}
      AND company_id = ${companyId}
    RETURNING id
  `;
  if (result.length > 0) {
    logDebug(`Package lock released: ${packageName} by company ${companyId}`);
  }
  return result.length > 0;
}

/**
 * List all currently held package locks.
 */
export async function listPackageLocks(): Promise<Row[]> {
  return await sql`
    SELECT tq.id, tq.company_id, tq.metadata->>'package' AS package_name,
           tq.claimed_at, tq.status, c.slug AS company_slug
    FROM task_queue tq
    JOIN companies c ON c.id = tq.company_id
    WHERE tq.source = 'cross_company'
      AND tq.status IN ('claimed', 'running')
    ORDER BY tq.claimed_at
  `;
}

// ── Daily Report ──────────────────────────────────────────────────

export async function getDailyReport(date?: string) {
  const targetDate = date ?? new Date().toISOString().split('T')[0];

  const perCompany = await sql`
    SELECT
      c.slug,
      c.display_name,
      COUNT(tq.id) FILTER (WHERE tq.status = 'completed' AND tq.updated_at::date = ${targetDate}::date) AS tasks_completed,
      COUNT(tq.id) FILTER (WHERE tq.status = 'failed' AND tq.updated_at::date = ${targetDate}::date) AS tasks_failed,
      COUNT(dq.id) FILTER (WHERE dq.created_at::date = ${targetDate}::date) AS decisions_asked,
      COUNT(dq.id) FILTER (WHERE dq.answered = TRUE AND dq.answered_at::date = ${targetDate}::date) AS decisions_answered,
      COALESCE(
        (SELECT SUM(bl.amount_usd) FROM company_budget_log bl
         WHERE bl.company_id = c.id AND bl.occurred_at::date = ${targetDate}::date),
        0
      ) AS spend_usd
    FROM companies c
    LEFT JOIN task_queue tq ON tq.company_id = c.id
    LEFT JOIN decision_queue dq ON dq.company_id = c.id
    WHERE c.status != 'archived'
    GROUP BY c.id, c.slug, c.display_name
    ORDER BY c.priority, c.slug
  `;

  const blocked = await sql`
    SELECT tq.title, tq.status, c.slug AS company_slug,
           dq.question, dq.tier
    FROM task_queue tq
    JOIN companies c ON c.id = tq.company_id
    LEFT JOIN decision_queue dq ON dq.task_id = tq.id AND dq.answered = FALSE
    WHERE tq.status = 'blocked'
    ORDER BY dq.tier, tq.created_at
  `;

  const prsCreated = await sql`
    SELECT ge.ref AS branch, ge.commit_msg AS title, ge.metadata->>'prUrl' AS pr_url,
           p.slug AS project_slug
    FROM git_events ge
    JOIN projects p ON p.id = ge.project_id
    WHERE ge.event_type = 'pr_created'
      AND ge.occurred_at::date = ${targetDate}::date
    ORDER BY ge.occurred_at DESC
  `;

  return { date: targetDate, perCompany, blocked, prsCreated };
}

// ── Heartbeat Processing ──────────────────────────────────────────

export async function processHeartbeat(companyId: string, sessionId: string) {
  await recordHeartbeat(companyId);

  const status = await getCompanyStatus(companyId);
  const company = await getCompany(companyId);
  let budgetExceeded = false;
  if (company) {
    const budget = typeof company.budget === 'string' ? JSON.parse(company.budget) : company.budget;
    const todaySpend = await getTodaySpend(companyId);
    budgetExceeded = todaySpend >= (budget.daily_usd ?? 999);
  }

  return {
    ...status,
    budgetExceeded,
    sessionId,
    timestamp: new Date().toISOString(),
  };
}

// ── Audit Log ─────────────────────────────────────────────────────

export async function writeAuditLog(input: {
  companyId?: string;
  actor: string;
  action: string;
  targetType: string;
  targetId?: string;
  beforeState?: Record<string, unknown>;
  afterState?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
}): Promise<void> {
  await sql`
    INSERT INTO audit_log (occurred_at, company_id, actor, action, target_type, target_id, before_state, after_state, metadata)
    VALUES (
      NOW(),
      ${input.companyId ?? null},
      ${input.actor},
      ${input.action},
      ${input.targetType},
      ${input.targetId ?? null},
      ${input.beforeState ? JSON.stringify(input.beforeState) : null},
      ${input.afterState ? JSON.stringify(input.afterState) : null},
      ${JSON.stringify(input.metadata ?? {})}
    )
  `;
}
