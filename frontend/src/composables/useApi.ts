import type {
  Project,
  Session,
  ActiveSession,
  Agent,
  AgentEvent,
  ChatMessage,
  PerformanceBucket,
  ActivityBucket,
  CostLeaderEntry,
  HealthStatus,
  GitEvent,
  Memory,
  MemorySearchResult,
  DashboardSummary,
} from "@/types";

const BASE_URL = import.meta.env.VITE_API_URL ?? "";

async function fetchJson<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${BASE_URL}${url}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...init?.headers,
    },
  });

  if (!response.ok) {
    const body = await response.json().catch(() => ({ error: response.statusText }));
    throw new Error(body.error ?? `HTTP ${response.status}`);
  }

  return response.json();
}

export function useApi() {
  return {
    // Health
    health: () => fetchJson<HealthStatus>("/health"),

    // Projects
    getProjects: () => fetchJson<Project[]>("/api/projects"),

    // Sessions
    getSessions: (projectId?: string) => {
      const qs = projectId ? `?project_id=${projectId}` : "";
      return fetchJson<Session[]>(`/api/sessions${qs}`);
    },
    getActiveSessions: () => fetchJson<ActiveSession[]>("/api/sessions/active"),

    // Agents
    getAgents: (sessionId?: string) => {
      const qs = sessionId ? `?session_id=${sessionId}` : "";
      return fetchJson<Agent[]>(`/api/agents${qs}`);
    },

    // Events
    getAgentEvents: (sessionId?: string, limit = 50) => {
      const params = new URLSearchParams();
      if (sessionId) params.set("session_id", sessionId);
      params.set("limit", String(limit));
      return fetchJson<AgentEvent[]>(`/api/agent-events?${params}`);
    },

    // Chat
    getChatMessages: (sessionId: string, limit = 100) =>
      fetchJson<ChatMessage[]>(`/api/chat-messages?session_id=${sessionId}&limit=${limit}`),

    sendChatMessage: (data: {
      sessionId: string;
      projectId: string;
      agentId?: string;
      role?: string;
      content: string;
    }) =>
      fetchJson<{ ok: boolean }>("/api/chat-message", {
        method: "POST",
        body: JSON.stringify(data),
      }),

    // Dashboard
    getPerformance: (projectId?: string, days = 7) => {
      const params = new URLSearchParams({ days: String(days) });
      if (projectId) params.set("project_id", projectId);
      return fetchJson<PerformanceBucket[]>(`/api/dashboard/performance?${params}`);
    },

    getActivity: (projectId?: string, hours = 24) => {
      const params = new URLSearchParams({ hours: String(hours) });
      if (projectId) params.set("project_id", projectId);
      return fetchJson<ActivityBucket[]>(`/api/dashboard/activity?${params}`);
    },

    getCosts: () => fetchJson<CostLeaderEntry[]>("/api/dashboard/costs"),

    getSummary: (projectId?: string) => {
      const params = new URLSearchParams();
      if (projectId) params.set("project_id", projectId);
      return fetchJson<DashboardSummary>(`/api/dashboard/summary?${params}`);
    },

    // Git / PRs
    getGitEvents: (projectId?: string, eventType?: string, limit = 50) => {
      const params = new URLSearchParams({ limit: String(limit) });
      if (projectId) params.set("project_id", projectId);
      if (eventType) params.set("event_type", eventType);
      return fetchJson<GitEvent[]>(`/api/git-events?${params}`);
    },

    // Memories
    getMemories: (projectId?: string, limit = 50) => {
      const params = new URLSearchParams({ limit: String(limit) });
      if (projectId) params.set("project_id", projectId);
      return fetchJson<Memory[]>(`/api/memories?${params}`);
    },

    searchMemories: (query: string, projectId: string, limit = 10, threshold = 0.7) =>
      fetchJson<MemorySearchResult[]>("/api/memories/search", {
        method: "POST",
        body: JSON.stringify({ query, projectId, limit, threshold }),
      }),
  };
}
