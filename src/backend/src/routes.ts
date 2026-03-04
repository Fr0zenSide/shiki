import { sql, healthCheck, getPoolStats } from "./db.ts";
import { ollamaHealthCheck } from "./ollama.ts";
import { writeAgentEvent, writePerformanceMetric } from "./events.ts";
import { storeMemory, searchMemories } from "./memories.ts";
import {
  AgentEventSchema,
  PerformanceMetricSchema,
  ChatMessageSchema,
  MemorySchema,
  MemorySearchSchema,
  PrCreatedSchema,
  DataSyncSchema,
} from "./schemas.ts";
import { json, parseBody, handleError, logDebug } from "./middleware.ts";
import { broadcastToProject, getWsStats } from "./ws.ts";

const APP_VERSION = "3.0.0";
const startedAt = Date.now();

export async function handleRequest(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;
  const method = req.method;

  try {
    // ── Health check ──────────────────────────────────────────────
    if (path === "/health") {
      return await handleHealth();
    }

    // ── Projects ──────────────────────────────────────────────────
    if (path === "/api/projects" && method === "GET") {
      const projects = await sql`SELECT * FROM projects ORDER BY created_at`;
      return json(projects);
    }

    // ── Sessions ──────────────────────────────────────────────────
    if (path === "/api/sessions" && method === "GET") {
      const projectId = url.searchParams.get("project_id");
      const sessions = projectId
        ? await sql`SELECT * FROM sessions WHERE project_id = ${projectId} ORDER BY started_at DESC LIMIT 50`
        : await sql`SELECT * FROM sessions ORDER BY started_at DESC LIMIT 50`;
      return json(sessions);
    }

    // ── Active sessions view ──────────────────────────────────────
    if (path === "/api/sessions/active" && method === "GET") {
      const sessions = await sql`SELECT * FROM active_sessions ORDER BY hours_active DESC`;
      return json(sessions);
    }

    // ── Agents ────────────────────────────────────────────────────
    if (path === "/api/agents" && method === "GET") {
      const sessionId = url.searchParams.get("session_id");
      const agents = sessionId
        ? await sql`SELECT * FROM agents WHERE session_id = ${sessionId} ORDER BY spawned_at DESC`
        : await sql`SELECT * FROM agents ORDER BY spawned_at DESC LIMIT 100`;
      return json(agents);
    }

    // ── Agent Events ──────────────────────────────────────────────
    if (path === "/api/agent-update" && method === "POST") {
      const body = await parseBody(req, AgentEventSchema);
      await writeAgentEvent(body);
      // Broadcast to WS clients watching this project
      broadcastToProject(body.projectId, {
        type: "agent_event",
        event: {
          occurred_at: new Date().toISOString(),
          agent_id: body.agentId,
          session_id: body.sessionId,
          project_id: body.projectId,
          event_type: body.eventType,
          payload: body.payload ?? {},
          progress_pct: body.progressPct ?? null,
          message: body.message ?? null,
        },
      });
      return json({ ok: true });
    }

    if (path === "/api/agent-events" && method === "GET") {
      const sessionId = url.searchParams.get("session_id");
      const limit = Math.min(parseInt(url.searchParams.get("limit") ?? "50"), 500);
      const events = sessionId
        ? await sql`SELECT * FROM agent_events WHERE session_id = ${sessionId} ORDER BY occurred_at DESC LIMIT ${limit}`
        : await sql`SELECT * FROM agent_events ORDER BY occurred_at DESC LIMIT ${limit}`;
      return json(events);
    }

    // ── Performance ───────────────────────────────────────────────
    if (path === "/api/stats-update" && method === "POST") {
      const body = await parseBody(req, PerformanceMetricSchema);
      await writePerformanceMetric(body);
      broadcastToProject(body.projectId, {
        type: "stats_update",
        metric: body,
        timestamp: new Date().toISOString(),
      });
      return json({ ok: true });
    }

    // ── Memories ──────────────────────────────────────────────────
    if (path === "/api/memories" && method === "POST") {
      const body = await parseBody(req, MemorySchema);
      const id = await storeMemory(body);
      return json({ id });
    }

    if (path === "/api/memories" && method === "GET") {
      const projectId = url.searchParams.get("project_id");
      const limit = Math.min(parseInt(url.searchParams.get("limit") ?? "50"), 500);
      const memories = projectId
        ? await sql`SELECT id, project_id, session_id, agent_id, content, category, importance, created_at FROM agent_memories WHERE project_id = ${projectId} ORDER BY created_at DESC LIMIT ${limit}`
        : await sql`SELECT id, project_id, session_id, agent_id, content, category, importance, created_at FROM agent_memories ORDER BY created_at DESC LIMIT ${limit}`;
      return json(memories);
    }

    if (path === "/api/memories/search" && method === "POST") {
      const { query, projectId, limit, threshold } = await parseBody(req, MemorySearchSchema);
      const results = await searchMemories(query, projectId, limit, threshold);
      return json(results);
    }

    // ── Memory Sources (file backup tracker) ────────────────────
    if (path === "/api/memories/sources" && method === "GET") {
      const projectId = url.searchParams.get("project_id");
      const sources = projectId
        ? await sql`
            SELECT
              metadata->>'sourceFile' as source_file,
              metadata->>'fileModifiedAt' as file_modified_at,
              MAX(created_at) as last_backed_up,
              COUNT(*) as chunk_count,
              ROUND(AVG(importance)::numeric, 1) as avg_importance
            FROM agent_memories
            WHERE project_id = ${projectId}
              AND metadata->>'sourceFile' IS NOT NULL
            GROUP BY metadata->>'sourceFile', metadata->>'fileModifiedAt'
            ORDER BY MAX(created_at) DESC
          `
        : await sql`
            SELECT
              metadata->>'sourceFile' as source_file,
              metadata->>'fileModifiedAt' as file_modified_at,
              MAX(created_at) as last_backed_up,
              COUNT(*) as chunk_count,
              ROUND(AVG(importance)::numeric, 1) as avg_importance
            FROM agent_memories
            WHERE metadata->>'sourceFile' IS NOT NULL
            GROUP BY metadata->>'sourceFile', metadata->>'fileModifiedAt'
            ORDER BY MAX(created_at) DESC
          `;
      return json(sources);
    }

    // ── Chat Messages ─────────────────────────────────────────────
    if (path === "/api/chat-message" && method === "POST") {
      const body = await parseBody(req, ChatMessageSchema);
      const now = new Date().toISOString();
      await sql`
        INSERT INTO chat_messages (occurred_at, session_id, project_id, agent_id, role, content, token_count, metadata)
        VALUES (${now}::timestamptz, ${body.sessionId}, ${body.projectId}, ${body.agentId ?? null}, ${body.role}, ${body.content}, ${body.tokenCount ?? null}, ${JSON.stringify(body.metadata)})
      `;
      // Broadcast chat to WS clients watching this project/session
      broadcastToProject(body.projectId, {
        type: "chat",
        sessionId: body.sessionId,
        projectId: body.projectId,
        agentId: body.agentId ?? null,
        role: body.role,
        content: body.content,
        timestamp: now,
      });
      return json({ ok: true });
    }

    if (path === "/api/chat-messages" && method === "GET") {
      const sessionId = url.searchParams.get("session_id");
      if (!sessionId) return json({ error: "session_id query param required" }, 400);
      const limit = Math.min(parseInt(url.searchParams.get("limit") ?? "100"), 1000);
      const messages = await sql`
        SELECT * FROM chat_messages WHERE session_id = ${sessionId} ORDER BY occurred_at ASC LIMIT ${limit}
      `;
      return json(messages);
    }

    // ── Data Sync ─────────────────────────────────────────────────
    if (path === "/api/data-sync" && method === "POST") {
      const body = await parseBody(req, DataSyncSchema);
      logDebug("Data sync received:", body.type, body.projectId);
      // Store as an agent event with type "data_sync"
      await sql`
        INSERT INTO agent_events (occurred_at, agent_id, session_id, project_id, event_type, payload, message)
        VALUES (NOW(), ${null}::uuid, ${body.sessionId ?? null}::uuid, ${body.projectId}, 'data_sync', ${JSON.stringify(body.data)}, ${body.type})
      `;
      broadcastToProject(body.projectId, {
        type: "data_sync",
        syncType: body.type,
        data: body.data,
        timestamp: new Date().toISOString(),
      });
      return json({ ok: true });
    }

    // ── PR Created ────────────────────────────────────────────────
    if (path === "/api/pr-created" && method === "POST") {
      const body = await parseBody(req, PrCreatedSchema);
      await sql`
        INSERT INTO git_events (occurred_at, project_id, session_id, agent_id, event_type, ref, commit_msg, metadata)
        VALUES (NOW(), ${body.projectId}, ${body.sessionId ?? null}, ${body.agentId ?? null}, 'pr_created', ${body.branch}, ${body.title}, ${JSON.stringify({ prUrl: body.prUrl, baseBranch: body.baseBranch, ...body.metadata })})
      `;
      broadcastToProject(body.projectId, {
        type: "pr_created",
        prUrl: body.prUrl,
        title: body.title,
        branch: body.branch,
        timestamp: new Date().toISOString(),
      });
      return json({ ok: true });
    }

    // ── Git Events / PRs ────────────────────────────────────────
    if (path === "/api/git-events" && method === "GET") {
      const projectId = url.searchParams.get("project_id");
      const eventType = url.searchParams.get("event_type");
      const limit = Math.min(parseInt(url.searchParams.get("limit") ?? "50"), 500);
      let events;
      if (projectId && eventType) {
        events = await sql`SELECT * FROM git_events WHERE project_id = ${projectId} AND event_type = ${eventType} ORDER BY occurred_at DESC LIMIT ${limit}`;
      } else if (projectId) {
        events = await sql`SELECT * FROM git_events WHERE project_id = ${projectId} ORDER BY occurred_at DESC LIMIT ${limit}`;
      } else if (eventType) {
        events = await sql`SELECT * FROM git_events WHERE event_type = ${eventType} ORDER BY occurred_at DESC LIMIT ${limit}`;
      } else {
        events = await sql`SELECT * FROM git_events ORDER BY occurred_at DESC LIMIT ${limit}`;
      }
      return json(events);
    }

    // ── Dashboard summary (aggregate stats) ────────────────────
    if (path === "/api/dashboard/summary" && method === "GET") {
      const projectId = url.searchParams.get("project_id");

      const [activeSessionsResult] = await sql`
        SELECT COUNT(*) as count FROM sessions WHERE status = 'active'
        ${projectId ? sql`AND project_id = ${projectId}` : sql``}
      `;
      const [activeAgentsResult] = await sql`
        SELECT COUNT(*) as count FROM agents WHERE status IN ('spawned', 'running')
        ${projectId ? sql`AND project_id = ${projectId}` : sql``}
      `;
      const [totalAgentsResult] = await sql`
        SELECT COUNT(*) as count FROM agents
        ${projectId ? sql`WHERE project_id = ${projectId}` : sql``}
      `;
      const [prCountResult] = await sql`
        SELECT COUNT(*) as count FROM git_events WHERE event_type = 'pr_created'
        ${projectId ? sql`AND project_id = ${projectId}` : sql``}
      `;
      const [decisionsCountResult] = await sql`
        SELECT COUNT(*) as count FROM decisions
        ${projectId ? sql`WHERE session_id IN (SELECT id FROM sessions WHERE project_id = ${projectId})` : sql``}
      `;
      const [messagesCountResult] = await sql`
        SELECT COUNT(*) as count FROM chat_messages
        ${projectId ? sql`WHERE project_id = ${projectId}` : sql``}
      `;
      const [recentEventsCountResult] = await sql`
        SELECT COUNT(*) as count FROM agent_events WHERE occurred_at > NOW() - INTERVAL '24 hours'
        ${projectId ? sql`AND project_id = ${projectId}` : sql``}
      `;

      return json({
        activeSessions: parseInt(activeSessionsResult.count),
        activeAgents: parseInt(activeAgentsResult.count),
        totalAgents: parseInt(totalAgentsResult.count),
        prsCreated: parseInt(prCountResult.count),
        decisionsCount: parseInt(decisionsCountResult.count),
        messagesCount: parseInt(messagesCountResult.count),
        recentEvents24h: parseInt(recentEventsCountResult.count),
      });
    }

    // ── Dashboard aggregates ──────────────────────────────────────
    if (path === "/api/dashboard/performance" && method === "GET") {
      const projectId = url.searchParams.get("project_id");
      const days = Math.min(parseInt(url.searchParams.get("days") ?? "7"), 365);
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
      const hours = Math.min(parseInt(url.searchParams.get("hours") ?? "24"), 720);
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

    if (path === "/api/dashboard/costs" && method === "GET") {
      const data = await sql`
        SELECT * FROM agent_cost_leaderboard LIMIT 50
      `;
      return json(data);
    }

    if (path === "/api/dashboard/git" && method === "GET") {
      const projectId = url.searchParams.get("project_id");
      const days = Math.min(parseInt(url.searchParams.get("days") ?? "7"), 365);
      const data = await sql`
        SELECT bucket, event_type, event_count, total_additions, total_deletions, total_files_changed
        FROM daily_git_activity
        WHERE bucket >= NOW() - make_interval(days => ${days})
        ${projectId ? sql`AND project_id = ${projectId}` : sql``}
        ORDER BY bucket
      `;
      return json(data);
    }

    // ── Database Backup Info ─────────────────────────────────────
    if (path === "/api/admin/backup-status" && method === "GET") {
      const dbStats = await sql`
        SELECT
          (SELECT COUNT(*) FROM agent_memories) as memories,
          (SELECT COUNT(*) FROM agent_events) as events,
          (SELECT COUNT(*) FROM chat_messages) as chats,
          (SELECT COUNT(*) FROM agents) as agents,
          (SELECT COUNT(*) FROM sessions) as sessions,
          (SELECT COUNT(*) FROM decisions) as decisions,
          (SELECT COUNT(*) FROM git_events) as git_events,
          (SELECT COUNT(*) FROM performance_metrics) as metrics
      `;
      return json({
        database: dbStats[0],
        backupScript: "scripts/backup-db.sh",
        restoreScript: "scripts/restore-db.sh",
        backupDir: "backups/",
        retentionDays: 14,
        timestamp: new Date().toISOString(),
      });
    }

    return json({ error: "Not found" }, 404);
  } catch (error) {
    return handleError(error);
  }
}

async function handleHealth(): Promise<Response> {
  const dbOk = await healthCheck();
  const ollamaOk = await ollamaHealthCheck();
  const poolStats = getPoolStats();
  const wsStats = getWsStats();
  const uptimeMs = Date.now() - startedAt;

  const status = dbOk ? "ok" : "degraded";
  const httpCode = dbOk ? 200 : 503;

  return json({
    status,
    version: APP_VERSION,
    uptime: {
      ms: uptimeMs,
      human: formatUptime(uptimeMs),
    },
    services: {
      database: {
        connected: dbOk,
        pool: poolStats,
      },
      ollama: {
        connected: ollamaOk,
      },
      websocket: wsStats,
    },
    timestamp: new Date().toISOString(),
  }, httpCode);
}

function formatUptime(ms: number): string {
  const seconds = Math.floor(ms / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);

  if (days > 0) return `${days}d ${hours % 24}h ${minutes % 60}m`;
  if (hours > 0) return `${hours}h ${minutes % 60}m`;
  if (minutes > 0) return `${minutes}m ${seconds % 60}s`;
  return `${seconds}s`;
}
