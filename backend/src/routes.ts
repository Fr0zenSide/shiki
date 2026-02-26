import { sql, healthCheck } from "./db.ts";
import { ollamaHealthCheck } from "./ollama.ts";
import { writeAgentEvent, writePerformanceMetric } from "./events.ts";
import { storeMemory, searchMemories } from "./memories.ts";

export async function handleRequest(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;
  const method = req.method;

  // Health check
  if (path === "/health") {
    const dbOk = await healthCheck();
    const ollamaOk = await ollamaHealthCheck();
    return json({ status: dbOk ? "ok" : "degraded", db: dbOk, ollama: ollamaOk }, dbOk ? 200 : 503);
  }

  // --- Projects ---
  if (path === "/api/projects" && method === "GET") {
    const projects = await sql`SELECT * FROM projects ORDER BY created_at`;
    return json(projects);
  }

  // --- Sessions ---
  if (path === "/api/sessions" && method === "GET") {
    const projectId = url.searchParams.get("project_id");
    const sessions = projectId
      ? await sql`SELECT * FROM sessions WHERE project_id = ${projectId} ORDER BY started_at DESC LIMIT 50`
      : await sql`SELECT * FROM sessions ORDER BY started_at DESC LIMIT 50`;
    return json(sessions);
  }

  // --- Agent Events ---
  if (path === "/api/agent-update" && method === "POST") {
    const body = await req.json();
    await writeAgentEvent(body);
    return json({ ok: true });
  }

  // --- Performance ---
  if (path === "/api/stats-update" && method === "POST") {
    const body = await req.json();
    await writePerformanceMetric(body);
    return json({ ok: true });
  }

  // --- Memories ---
  if (path === "/api/memories" && method === "POST") {
    const body = await req.json();
    const id = await storeMemory(body);
    return json({ id });
  }

  if (path === "/api/memories/search" && method === "POST") {
    const { query, projectId, limit, threshold } = await req.json();
    const results = await searchMemories(query, projectId, limit, threshold);
    return json(results);
  }

  // --- Chat Messages ---
  if (path === "/api/chat-message" && method === "POST") {
    const body = await req.json();
    await sql`
      INSERT INTO chat_messages (occurred_at, session_id, project_id, agent_id, role, content, token_count, metadata)
      VALUES (NOW(), ${body.sessionId}, ${body.projectId}, ${body.agentId ?? null}, ${body.role ?? "assistant"}, ${body.content}, ${body.tokenCount ?? null}, ${JSON.stringify(body.metadata ?? {})})
    `;
    return json({ ok: true });
  }

  // --- Dashboard aggregates ---
  if (path === "/api/dashboard/performance" && method === "GET") {
    const projectId = url.searchParams.get("project_id");
    const days = parseInt(url.searchParams.get("days") ?? "7");
    const data = await sql`
      SELECT bucket, model, api_calls, total_tokens, total_cost_usd, avg_duration_ms
      FROM daily_performance
      WHERE bucket >= NOW() - make_interval(days => ${days})
      ${projectId ? sql`AND project_id = ${projectId}` : sql``}
      ORDER BY bucket
    `;
    return json(data);
  }

  if (path === "/api/dashboard/activity" && method === "GET") {
    const projectId = url.searchParams.get("project_id");
    const hours = parseInt(url.searchParams.get("hours") ?? "24");
    const data = await sql`
      SELECT bucket, event_type, SUM(event_count) as count
      FROM agent_activity_hourly
      WHERE bucket >= NOW() - make_interval(hours => ${hours})
      ${projectId ? sql`AND project_id = ${projectId}` : sql``}
      GROUP BY bucket, event_type
      ORDER BY bucket
    `;
    return json(data);
  }

  return json({ error: "Not found" }, 404);
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
}
