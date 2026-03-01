import { ref, computed } from "vue";
import Fuse from "fuse.js";
import { useAgencyStore } from "./useAgencyStore";
import { useApi } from "./useApi";
import { useRouter } from "vue-router";

// ── Types ────────────────────────────────────────────────────────────

export type EntityCategory = "session" | "agent" | "memory" | "pr" | "git" | "command";

export interface FzfResult {
  category: EntityCategory;
  id: string;
  label: string;
  sublabel: string;
  action: () => void;
  score: number;
}

export interface RecentItem {
  category: EntityCategory;
  id: string;
  label: string;
}

export type SearchMode = "all" | "session" | "agent" | "memory" | "pr" | "git" | "command";

// ── Prefix mapping ───────────────────────────────────────────────────

const PREFIX_MAP: Record<string, SearchMode> = {
  "s:": "session",
  "a:": "agent",
  "m:": "memory",
  "p:": "pr",
  "g:": "git",
  ">": "command",
};

const MODE_LABELS: Record<SearchMode, string> = {
  all: "Search everything...",
  session: "Search sessions...",
  agent: "Search agents...",
  memory: "Search memories...",
  pr: "Search pull requests...",
  git: "Search git events...",
  command: "Run a command...",
};

// ── Commands ─────────────────────────────────────────────────────────

function buildCommands(router: ReturnType<typeof useRouter>, store: ReturnType<typeof useAgencyStore>): FzfResult[] {
  return [
    {
      category: "command",
      id: "cmd-refresh",
      label: "Refresh data",
      sublabel: "Refetch all dashboard data",
      score: 1,
      action: () => {
        store.fetchHealth();
        store.fetchActiveSessions();
        store.fetchEvents(undefined, 30);
        store.fetchSummary();
      },
    },
    {
      category: "command",
      id: "cmd-dashboard",
      label: "Go to Dashboard",
      sublabel: "Navigate to overview",
      score: 1,
      action: () => router.push("/"),
    },
    {
      category: "command",
      id: "cmd-agents",
      label: "Go to Agents",
      sublabel: "Navigate to agents page",
      score: 1,
      action: () => router.push("/agents"),
    },
    {
      category: "command",
      id: "cmd-chat",
      label: "Go to Chat",
      sublabel: "Navigate to chat",
      score: 1,
      action: () => router.push("/chat"),
    },
    {
      category: "command",
      id: "cmd-memory",
      label: "Go to Memory",
      sublabel: "Navigate to memory page",
      score: 1,
      action: () => router.push("/memory"),
    },
    {
      category: "command",
      id: "cmd-prs",
      label: "Go to PRs & Git",
      sublabel: "Navigate to pull requests",
      score: 1,
      action: () => router.push("/prs"),
    },
    {
      category: "command",
      id: "cmd-daimyo-review",
      label: "Daimyo Review",
      sublabel: "Request a structured backlog prioritization ballot",
      score: 1,
      action: () => {
        const sessionId = store.selectedSessionId;
        if (sessionId) {
          store.sendChatMessage(sessionId, "@backlogger Start a Daimyo Review — structured decision ballot for pending features and backlog items.");
          router.push("/chat");
        } else {
          router.push("/chat");
        }
      },
    },
    {
      category: "command",
      id: "cmd-decision-log",
      label: "View Decision Log",
      sublabel: "Search past Daimyo Review decisions in memory",
      score: 1,
      action: () => router.push("/memory"),
    },
  ];
}

// ── Recent searches (localStorage) ───────────────────────────────────

const RECENTS_KEY = "acc-fzf-recents";
const MAX_RECENTS = 5;

function loadRecents(): RecentItem[] {
  try {
    const raw = localStorage.getItem(RECENTS_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

function saveRecent(item: RecentItem) {
  const recents = loadRecents().filter((r) => r.id !== item.id);
  recents.unshift(item);
  localStorage.setItem(RECENTS_KEY, JSON.stringify(recents.slice(0, MAX_RECENTS)));
}

// ── Main composable ──────────────────────────────────────────────────

export function useFzfSearch() {
  const store = useAgencyStore();
  const api = useApi();
  const router = useRouter();

  const query = ref("");
  const mode = computed<SearchMode>(() => {
    for (const [prefix, m] of Object.entries(PREFIX_MAP)) {
      if (query.value.startsWith(prefix)) return m;
    }
    return "all";
  });

  const cleanQuery = computed(() => {
    const q = query.value;
    for (const prefix of Object.keys(PREFIX_MAP)) {
      if (q.startsWith(prefix)) return q.slice(prefix.length).trim();
    }
    return q.trim();
  });

  const placeholder = computed(() => MODE_LABELS[mode.value]);
  const results = ref<FzfResult[]>([]);
  const isSearching = ref(false);
  const recents = ref<RecentItem[]>(loadRecents());

  // Debounce timer for backend search
  let backendTimer: ReturnType<typeof setTimeout> | null = null;

  // ── Phase 1: Instant Pinia search ──────────────────────────────────

  function searchLocal(q: string, m: SearchMode): FzfResult[] {
    const local: FzfResult[] = [];

    // Sessions
    if (m === "all" || m === "session") {
      const sessionFuse = new Fuse(store.sessions, {
        keys: ["name", "branch", "summary"],
        threshold: 0.4,
      });
      const sessionResults = q ? sessionFuse.search(q) : store.sessions.map((s, i) => ({ item: s, score: i * 0.01 }));
      for (const r of sessionResults.slice(0, 8)) {
        local.push({
          category: "session",
          id: r.item.id,
          label: r.item.name,
          sublabel: `${r.item.status} ${r.item.branch ? "on " + r.item.branch : ""}`.trim(),
          score: 1 - (r.score ?? 0.5),
          action: () => router.push(`/sessions/${r.item.id}`),
        });
      }
    }

    // Agents
    if (m === "all" || m === "agent") {
      const agentFuse = new Fuse(store.agents, {
        keys: ["handle", "role", "model"],
        threshold: 0.4,
      });
      const agentResults = q ? agentFuse.search(q) : store.agents.map((a, i) => ({ item: a, score: i * 0.01 }));
      for (const r of agentResults.slice(0, 8)) {
        local.push({
          category: "agent",
          id: r.item.id,
          label: r.item.handle,
          sublabel: `${r.item.status} \u00B7 ${r.item.model}`,
          score: 1 - (r.score ?? 0.5),
          action: () => router.push(`/sessions/${r.item.session_id}`),
        });
      }
    }

    // Cached memories
    if (m === "all" || m === "memory") {
      const memFuse = new Fuse(store.memories, {
        keys: ["content", "category"],
        threshold: 0.4,
      });
      const memResults = q ? memFuse.search(q) : store.memories.map((m, i) => ({ item: m, score: i * 0.01 }));
      for (const r of memResults.slice(0, 5)) {
        local.push({
          category: "memory",
          id: r.item.id,
          label: r.item.content.slice(0, 80) + (r.item.content.length > 80 ? "..." : ""),
          sublabel: r.item.category,
          score: 1 - (r.score ?? 0.5),
          action: () => router.push("/memory"),
        });
      }
    }

    // PRs and git events
    if (m === "all" || m === "pr" || m === "git") {
      const prs = store.gitEvents.filter((e) => m === "git" || e.event_type === "pr_created");
      const prFuse = new Fuse(prs, {
        keys: ["commit_msg", "ref", "author"],
        threshold: 0.4,
      });
      const prResults = q ? prFuse.search(q) : prs.map((p, i) => ({ item: p, score: i * 0.01 }));
      for (const r of prResults.slice(0, 5)) {
        const isPr = r.item.event_type === "pr_created";
        local.push({
          category: isPr ? "pr" : "git",
          id: `git-${r.item.occurred_at}-${r.item.commit_sha ?? r.item.ref}`,
          label: r.item.commit_msg ?? r.item.event_type,
          sublabel: `${r.item.ref ?? ""} ${r.item.author ?? ""}`.trim(),
          score: 1 - (r.score ?? 0.5),
          action: () => {
            const prUrl = (r.item.metadata as Record<string, unknown>)?.prUrl;
            if (isPr && typeof prUrl === "string") {
              window.open(prUrl, "_blank");
            } else {
              router.push("/prs");
            }
          },
        });
      }
    }

    // Commands
    if (m === "all" || m === "command") {
      const commands = buildCommands(router, store);
      if (q && m === "command") {
        const cmdFuse = new Fuse(commands, {
          keys: ["label", "sublabel"],
          threshold: 0.4,
        });
        for (const r of cmdFuse.search(q)) {
          local.push({ ...r.item, score: 1 - (r.score ?? 0.5) });
        }
      } else if (m === "command") {
        local.push(...commands);
      }
    }

    return local;
  }

  // ── Phase 2: Backend memory search (debounced) ─────────────────────

  async function searchBackend(q: string) {
    if (!q || q.length < 2) return;
    if (mode.value === "command") return;

    isSearching.value = true;
    try {
      const projectId = store.selectedProjectId;
      if (!projectId) return;

      const memoryResults = await api.searchMemories(q, projectId, 10);
      // Merge backend results, deduplicating by content prefix
      const existingIds = new Set(results.value.map((r) => r.id));
      for (const mem of memoryResults) {
        if (existingIds.has(mem.id)) continue;
        results.value.push({
          category: "memory",
          id: mem.id,
          label: mem.content.slice(0, 80) + (mem.content.length > 80 ? "..." : ""),
          sublabel: `${mem.category} \u00B7 ${Math.round(mem.similarity * 100)}% match`,
          score: mem.similarity,
          action: () => router.push("/memory"),
        });
      }
      // Re-sort by score
      results.value.sort((a, b) => b.score - a.score);
    } finally {
      isSearching.value = false;
    }
  }

  // ── Search orchestrator ────────────────────────────────────────────

  function search(q: string) {
    query.value = q;

    // Phase 1: instant local results
    results.value = searchLocal(cleanQuery.value, mode.value);

    // Phase 2: debounced backend search
    if (backendTimer) clearTimeout(backendTimer);
    if (cleanQuery.value.length >= 2 && mode.value !== "command") {
      backendTimer = setTimeout(() => searchBackend(cleanQuery.value), 300);
    }
  }

  function selectResult(result: FzfResult) {
    saveRecent({ category: result.category, id: result.id, label: result.label });
    recents.value = loadRecents();
    result.action();
  }

  function clear() {
    query.value = "";
    results.value = [];
    if (backendTimer) clearTimeout(backendTimer);
  }

  return {
    query,
    mode,
    placeholder,
    results,
    isSearching,
    recents,
    search,
    selectResult,
    clear,
  };
}
