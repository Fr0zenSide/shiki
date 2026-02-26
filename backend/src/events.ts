import { sql } from "./db.ts";

export interface AgentEvent {
  agentId: string;
  sessionId: string;
  projectId: string;
  eventType: string;
  payload?: Record<string, unknown>;
  progressPct?: number;
  message?: string;
}

export async function writeAgentEvent(event: AgentEvent) {
  await sql`
    INSERT INTO agent_events (occurred_at, agent_id, session_id, project_id, event_type, payload, progress_pct, message)
    VALUES (NOW(), ${event.agentId}, ${event.sessionId}, ${event.projectId}, ${event.eventType}, ${JSON.stringify(event.payload ?? {})}, ${event.progressPct ?? null}, ${event.message ?? null})
  `;
}

export interface PerformanceMetric {
  agentId: string;
  sessionId: string;
  projectId: string;
  metricType: string;
  tokensInput?: number;
  tokensOutput?: number;
  durationMs?: number;
  costUsd?: number;
  model?: string;
}

export async function writePerformanceMetric(metric: PerformanceMetric) {
  await sql`
    INSERT INTO performance_metrics (occurred_at, agent_id, session_id, project_id, metric_type, tokens_input, tokens_output, duration_ms, cost_usd, model)
    VALUES (NOW(), ${metric.agentId}, ${metric.sessionId}, ${metric.projectId}, ${metric.metricType}, ${metric.tokensInput ?? null}, ${metric.tokensOutput ?? null}, ${metric.durationMs ?? null}, ${metric.costUsd ?? null}, ${metric.model ?? null})
  `;
}
