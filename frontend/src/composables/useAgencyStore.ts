import { defineStore } from "pinia";
import { ref, computed } from "vue";
import { useApi } from "./useApi";
import type {
  Project,
  Session,
  ActiveSession,
  Agent,
  AgentEvent,
  ChatMessage,
  HealthStatus,
} from "@/types";

export const useAgencyStore = defineStore("agency", () => {
  const api = useApi();

  // ── State ─────────────────────────────────────────────────────────
  const projects = ref<Project[]>([]);
  const sessions = ref<Session[]>([]);
  const activeSessions = ref<ActiveSession[]>([]);
  const agents = ref<Agent[]>([]);
  const events = ref<AgentEvent[]>([]);
  const chatMessages = ref<ChatMessage[]>([]);
  const health = ref<HealthStatus | null>(null);

  const loading = ref(false);
  const error = ref<string | null>(null);
  const selectedProjectId = ref<string | null>(null);
  const selectedSessionId = ref<string | null>(null);

  // ── Computed ──────────────────────────────────────────────────────
  const selectedProject = computed(() =>
    projects.value.find((p) => p.id === selectedProjectId.value) ?? null,
  );

  const selectedSession = computed(() =>
    sessions.value.find((s) => s.id === selectedSessionId.value) ?? null,
  );

  const sessionAgents = computed(() =>
    selectedSessionId.value
      ? agents.value.filter((a) => a.session_id === selectedSessionId.value)
      : agents.value,
  );

  const activeAgentCount = computed(() =>
    agents.value.filter((a) => a.status === "running" || a.status === "spawned").length,
  );

  const isHealthy = computed(() => health.value?.status === "ok");

  // ── Actions ───────────────────────────────────────────────────────

  async function init() {
    await Promise.all([
      fetchProjects(),
      fetchHealth(),
    ]);
  }

  async function fetchProjects() {
    try {
      projects.value = await api.getProjects();
      if (projects.value.length > 0 && !selectedProjectId.value) {
        selectedProjectId.value = projects.value[0].id;
      }
    } catch (err) {
      error.value = err instanceof Error ? err.message : "Failed to fetch projects";
    }
  }

  async function fetchSessions(projectId?: string) {
    try {
      sessions.value = await api.getSessions(projectId ?? selectedProjectId.value ?? undefined);
    } catch (err) {
      error.value = err instanceof Error ? err.message : "Failed to fetch sessions";
    }
  }

  async function fetchActiveSessions() {
    try {
      activeSessions.value = await api.getActiveSessions();
    } catch (err) {
      error.value = err instanceof Error ? err.message : "Failed to fetch active sessions";
    }
  }

  async function fetchAgents(sessionId?: string) {
    try {
      agents.value = await api.getAgents(sessionId);
    } catch (err) {
      error.value = err instanceof Error ? err.message : "Failed to fetch agents";
    }
  }

  async function fetchEvents(sessionId?: string, limit = 50) {
    try {
      events.value = await api.getAgentEvents(sessionId, limit);
    } catch (err) {
      error.value = err instanceof Error ? err.message : "Failed to fetch events";
    }
  }

  async function fetchChatMessages(sessionId: string) {
    try {
      chatMessages.value = await api.getChatMessages(sessionId);
    } catch (err) {
      error.value = err instanceof Error ? err.message : "Failed to fetch chat messages";
    }
  }

  async function sendChatMessage(content: string) {
    if (!selectedSessionId.value || !selectedProjectId.value) return;
    try {
      await api.sendChatMessage({
        sessionId: selectedSessionId.value,
        projectId: selectedProjectId.value,
        role: "user",
        content,
      });
      // Refresh messages
      await fetchChatMessages(selectedSessionId.value);
    } catch (err) {
      error.value = err instanceof Error ? err.message : "Failed to send message";
    }
  }

  async function fetchHealth() {
    try {
      health.value = await api.health();
    } catch {
      health.value = null;
    }
  }

  function selectProject(id: string) {
    selectedProjectId.value = id;
    selectedSessionId.value = null;
    fetchSessions(id);
  }

  function selectSession(id: string) {
    selectedSessionId.value = id;
    fetchAgents(id);
    fetchEvents(id);
    fetchChatMessages(id);
  }

  // ── WS event handlers (called from layout) ───────────────────────

  function handleWsChat(msg: { sessionId: string; content: string; role: string; timestamp: string }) {
    if (msg.sessionId === selectedSessionId.value) {
      chatMessages.value.push({
        occurred_at: msg.timestamp,
        id: crypto.randomUUID(),
        session_id: msg.sessionId,
        project_id: selectedProjectId.value ?? "",
        agent_id: null,
        role: msg.role as ChatMessage["role"],
        content: msg.content,
        token_count: null,
        metadata: {},
      });
    }
  }

  function handleWsAgentEvent(event: AgentEvent) {
    events.value.unshift(event);
    // Keep event list bounded
    if (events.value.length > 200) {
      events.value = events.value.slice(0, 200);
    }
  }

  return {
    // State
    projects,
    sessions,
    activeSessions,
    agents,
    events,
    chatMessages,
    health,
    loading,
    error,
    selectedProjectId,
    selectedSessionId,

    // Computed
    selectedProject,
    selectedSession,
    sessionAgents,
    activeAgentCount,
    isHealthy,

    // Actions
    init,
    fetchProjects,
    fetchSessions,
    fetchActiveSessions,
    fetchAgents,
    fetchEvents,
    fetchChatMessages,
    sendChatMessage,
    fetchHealth,
    selectProject,
    selectSession,
    handleWsChat,
    handleWsAgentEvent,
  };
});
