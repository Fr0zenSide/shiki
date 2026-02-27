// ── Domain Types ────────────────────────────────────────────────────

export interface Project {
  id: string;
  slug: string;
  name: string;
  description: string | null;
  repo_url: string | null;
  created_at: string;
  updated_at: string;
  metadata: Record<string, unknown>;
}

export interface Session {
  id: string;
  project_id: string;
  name: string;
  branch: string | null;
  status: "active" | "paused" | "completed" | "failed";
  started_at: string;
  ended_at: string | null;
  summary: string | null;
  metadata: Record<string, unknown>;
}

export interface ActiveSession {
  id: string;
  name: string;
  branch: string | null;
  started_at: string;
  project_slug: string;
  project_name: string;
  hours_active: number;
}

export interface Agent {
  id: string;
  session_id: string;
  project_id: string;
  handle: string;
  role: string;
  model: string;
  spawned_at: string;
  completed_at: string | null;
  status: "spawned" | "running" | "completed" | "failed" | "cancelled";
  parent_id: string | null;
  metadata: Record<string, unknown>;
}

export interface AgentEvent {
  occurred_at: string;
  agent_id: string;
  session_id: string;
  project_id: string;
  event_type: string;
  payload: Record<string, unknown>;
  progress_pct: number | null;
  message: string | null;
}

export interface ChatMessage {
  occurred_at: string;
  id: string;
  session_id: string;
  project_id: string;
  agent_id: string | null;
  role: "user" | "assistant" | "system" | "orchestrator";
  content: string;
  token_count: number | null;
  metadata: Record<string, unknown>;
}

export interface PerformanceBucket {
  bucket: string;
  model: string;
  api_calls: number;
  total_tokens: number;
  total_cost_usd: number;
  avg_duration_ms: number;
}

export interface ActivityBucket {
  bucket: string;
  event_type: string;
  count: number;
}

export interface CostLeaderEntry {
  handle: string;
  model: string;
  status: string;
  api_calls: number;
  total_tokens: number;
  total_cost_usd: number;
}

export interface GitEvent {
  occurred_at: string;
  project_id: string;
  session_id: string | null;
  agent_id: string | null;
  event_type: string;
  ref: string | null;
  commit_sha: string | null;
  commit_msg: string | null;
  author: string | null;
  files_changed: number | null;
  additions: number | null;
  deletions: number | null;
  metadata: Record<string, unknown>;
}

export interface Memory {
  id: string;
  project_id: string;
  session_id: string | null;
  agent_id: string | null;
  content: string;
  category: string;
  importance: number;
  created_at: string;
}

export interface MemorySearchResult {
  id: string;
  content: string;
  category: string;
  similarity: number;
  createdAt: string;
  fromAgent: string | null;
}

export interface MemorySource {
  source_file: string;
  file_modified_at: string | null;
  last_backed_up: string;
  chunk_count: number;
  avg_importance: number;
}

export interface DashboardSummary {
  activeSessions: number;
  activeAgents: number;
  totalAgents: number;
  prsCreated: number;
  decisionsCount: number;
  messagesCount: number;
  recentEvents24h: number;
}

export interface HealthStatus {
  status: "ok" | "degraded";
  version: string;
  uptime: {
    ms: number;
    human: string;
  };
  services: {
    database: {
      connected: boolean;
      pool: {
        totalConnections: number;
        idleConnections: number;
        waitingQueries: number;
      };
    };
    ollama: {
      connected: boolean;
    };
    websocket: {
      clientCount: number;
      channelCount: number;
      channels: Record<string, number>;
    };
  };
  timestamp: string;
}

// ── WebSocket message types ─────────────────────────────────────────

export type WsIncoming =
  | { type: "connected"; clientId: string; timestamp: string }
  | { type: "subscribed"; channel: string; timestamp: string }
  | { type: "unsubscribed"; channel: string; timestamp: string }
  | { type: "chat"; sessionId: string; projectId: string; agentId?: string; role: string; content: string; timestamp: string }
  | { type: "agent_event"; event: AgentEvent }
  | { type: "stats_update"; metric: Record<string, unknown>; timestamp: string }
  | { type: "data_sync"; syncType: string; data: Record<string, unknown>; timestamp: string }
  | { type: "pr_created"; prUrl: string; title: string; branch: string; timestamp: string }
  | { type: "error"; message: string };

export type WsOutgoing =
  | { type: "subscribe"; channel: string }
  | { type: "unsubscribe"; channel: string }
  | { type: "chat"; sessionId: string; projectId: string; agentId?: string; role?: string; content: string };
