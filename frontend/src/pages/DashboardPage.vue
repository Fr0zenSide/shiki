<script setup lang="ts">
import { ref, onMounted, computed } from "vue";
import { useAgencyStore } from "@/composables/useAgencyStore";
import { useApi } from "@/composables/useApi";
import ActivityChart from "@/components/dashboard/ActivityChart.vue";
import type { CostLeaderEntry } from "@/types";

const store = useAgencyStore();
const api = useApi();
const costs = ref<CostLeaderEntry[]>([]);

onMounted(async () => {
  await Promise.all([
    store.fetchActiveSessions(),
    store.fetchEvents(undefined, 30),
    store.fetchSummary(),
    store.fetchGitEvents(),
    store.fetchAgents(),
    fetchCosts(),
  ]);
});

async function fetchCosts() {
  try {
    costs.value = await api.getCosts();
  } catch {
    // Dashboard degradation is fine
  }
}

async function refresh() {
  await Promise.all([
    store.fetchHealth(),
    store.fetchActiveSessions(),
    store.fetchEvents(undefined, 30),
    store.fetchSummary(),
    store.fetchGitEvents(),
    store.fetchAgents(),
    fetchCosts(),
  ]);
}

function formatCost(usd: number | null): string {
  if (usd == null || typeof usd !== "number" || isNaN(usd)) return "$0.0000";
  return `$${usd.toFixed(4)}`;
}

function formatTime(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
}

function formatDuration(hours: number): string {
  if (hours < 1) return `${Math.round(hours * 60)}m`;
  return `${Math.round(hours * 10) / 10}h`;
}

function formatTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return String(n);
}

const statusColors: Record<string, string> = {
  spawned: "text-blue-400",
  running: "text-green-400",
  completed: "text-surface-500",
  failed: "text-red-400",
  cancelled: "text-surface-600",
};

const agentDotColors: Record<string, string> = {
  spawned: "bg-blue-400",
  running: "bg-green-400",
  completed: "bg-surface-500",
  failed: "bg-red-400",
  cancelled: "bg-surface-600",
};

const recentPRs = computed(() =>
  store.gitEvents
    .filter((e) => e.event_type === "pr_created")
    .slice(0, 5),
);

function getPrUrl(event: (typeof store.gitEvents)[number]): string | null {
  const md = event.metadata as Record<string, unknown>;
  if (typeof md.prUrl === "string") return md.prUrl;
  return null;
}

// Token usage aggregation from costs
const totalTokens = computed(() =>
  costs.value.reduce((sum, c) => sum + (Number(c.total_tokens) || 0), 0),
);
const totalCostUsd = computed(() =>
  costs.value.reduce((sum, c) => sum + (Number(c.total_cost_usd) || 0), 0),
);

// Phase progress sessions
const phaseSessions = computed(() =>
  store.activeSessions.filter(
    (s) => (s as any).phase || (s as any).completionRate != null,
  ),
);

// Agent list for dashboard (migrated from sidebar)
const displayAgents = computed(() => store.sessionAgents.slice(0, 20));
</script>

<template>
  <div class="p-6 space-y-6 max-w-7xl mx-auto">
    <!-- Header -->
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-semibold text-surface-100">Dashboard</h1>
        <p class="text-sm text-surface-500 mt-1">
          <template v-if="store.selectedProject">
            {{ store.selectedProject.name }} overview
          </template>
          <template v-else>Agency overview</template>
        </p>
      </div>
      <button
        class="px-3 py-1.5 rounded-lg bg-surface-800 text-surface-300 text-sm hover:bg-surface-700 transition-colors"
        @click="refresh()"
      >
        Refresh
      </button>
    </div>

    <!-- Stats cards (5 columns) -->
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
      <!-- Active sessions -->
      <div class="bg-surface-900 border border-surface-800 rounded-xl p-4">
        <div class="text-xs text-surface-500 uppercase tracking-wider">Active Sessions</div>
        <div class="text-3xl font-bold text-surface-100 mt-2">
          {{ store.summary?.activeSessions ?? store.activeSessions.length }}
        </div>
      </div>

      <!-- Agents running -->
      <div class="bg-surface-900 border border-surface-800 rounded-xl p-4">
        <div class="text-xs text-surface-500 uppercase tracking-wider">Agents Running</div>
        <div class="text-3xl font-bold text-green-400 mt-2">
          {{ store.summary?.activeAgents ?? store.activeAgentCount }}
        </div>
        <div v-if="store.summary" class="text-xs text-surface-600 mt-1">
          {{ store.summary.totalAgents }} total
        </div>
      </div>

      <!-- PRs created -->
      <div class="bg-surface-900 border border-surface-800 rounded-xl p-4">
        <div class="text-xs text-surface-500 uppercase tracking-wider">PRs Created</div>
        <div class="text-3xl font-bold text-teal-400 mt-2">
          {{ store.summary?.prsCreated ?? recentPRs.length }}
        </div>
      </div>

      <!-- Recent activity -->
      <div class="bg-surface-900 border border-surface-800 rounded-xl p-4">
        <div class="text-xs text-surface-500 uppercase tracking-wider">Events (24h)</div>
        <div class="text-3xl font-bold text-amber-400 mt-2">
          {{ store.summary?.recentEvents24h ?? store.events.length }}
        </div>
        <div v-if="store.summary" class="text-xs text-surface-600 mt-1">
          {{ store.summary.messagesCount }} messages &middot; {{ store.summary.decisionsCount }} decisions
        </div>
      </div>

      <!-- Token usage -->
      <div class="bg-surface-900 border border-surface-800 rounded-xl p-4">
        <div class="text-xs text-surface-500 uppercase tracking-wider">Token Usage</div>
        <div class="text-3xl font-bold text-purple-400 mt-2">
          {{ formatTokens(totalTokens) }}
        </div>
        <div class="text-xs text-surface-600 mt-1">
          {{ formatCost(totalCostUsd) }} total cost
        </div>
      </div>
    </div>

    <!-- Phase Progress Bar -->
    <section v-if="phaseSessions.length > 0" class="bg-surface-900 border border-surface-800 rounded-xl p-4">
      <h2 class="text-xs uppercase tracking-wider text-surface-500 mb-3">Session Phases</h2>
      <div v-for="session in phaseSessions" :key="session.id" class="flex items-center gap-4 py-2">
        <span class="text-sm text-surface-200 w-40 truncate">{{ session.name }}</span>
        <div class="flex-1 h-2 bg-surface-800 rounded-full overflow-hidden">
          <div
            class="h-full bg-teal-400 rounded-full transition-all"
            :style="{ width: ((session as any).completionRate ?? 0) + '%' }"
          />
        </div>
        <span class="text-xs text-surface-500 w-16 text-right">
          {{ (session as any).phase ?? 'idle' }}
        </span>
        <span class="text-xs font-mono text-teal-400 w-10 text-right">
          {{ (session as any).completionRate ?? 0 }}%
        </span>
      </div>
    </section>

    <!-- Activity Chart -->
    <ActivityChart />

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <!-- Active Sessions -->
      <section class="lg:col-span-2 bg-surface-900 border border-surface-800 rounded-xl">
        <div class="px-5 py-4 border-b border-surface-800">
          <h2 class="text-sm font-semibold text-surface-200">Active Sessions</h2>
        </div>
        <div class="p-4">
          <div v-if="store.activeSessions.length === 0" class="text-sm text-surface-600 italic py-4 text-center">
            No active sessions
          </div>
          <ul class="space-y-2">
            <li
              v-for="session in store.activeSessions"
              :key="session.id"
              class="flex items-center justify-between px-3 py-2 rounded-lg hover:bg-surface-850 transition-colors cursor-pointer"
              @click="$router.push({ name: 'session', params: { id: session.id } })"
            >
              <div>
                <div class="text-sm font-medium text-surface-200">{{ session.name }}</div>
                <div class="text-xs text-surface-500 mt-0.5">
                  {{ session.project_name }} &middot; {{ session.branch ?? "no branch" }}
                </div>
              </div>
              <div class="flex items-center gap-2">
                <span
                  v-if="(session as any).phase"
                  class="text-xs px-1.5 py-0.5 rounded bg-amber-400/15 text-amber-400"
                >
                  {{ (session as any).phase }}
                </span>
                <span class="text-xs text-teal-400 font-mono">
                  {{ formatDuration(session.hours_active) }}
                </span>
              </div>
            </li>
          </ul>
        </div>
      </section>

      <!-- Agents (migrated from sidebar) -->
      <section class="bg-surface-900 border border-surface-800 rounded-xl">
        <div class="px-5 py-4 border-b border-surface-800 flex items-center justify-between">
          <h2 class="text-sm font-semibold text-surface-200">Agents</h2>
          <span
            v-if="store.activeAgentCount > 0"
            class="text-xs px-1.5 py-0.5 rounded-full bg-green-400/15 text-green-400"
          >
            {{ store.activeAgentCount }} active
          </span>
        </div>
        <div class="p-4">
          <div v-if="store.agents.length === 0" class="text-sm text-surface-600 italic py-4 text-center">
            No agents yet
          </div>
          <ul class="space-y-1">
            <li
              v-for="agent in displayAgents"
              :key="agent.id"
              class="flex items-center gap-2 px-2 py-1.5 rounded text-sm"
            >
              <span
                class="w-2 h-2 rounded-full flex-shrink-0"
                :class="[
                  agentDotColors[agent.status] ?? 'bg-surface-600',
                  (agent.status === 'running' || agent.status === 'spawned') && store.stableActiveAgents.some(a => a.id === agent.id)
                    ? 'animate-pulse'
                    : '',
                ]"
              />
              <span class="truncate text-surface-300 flex-1">{{ agent.handle }}</span>
              <span class="text-xs text-surface-600 flex-shrink-0">{{ agent.model.split('/').pop() }}</span>
            </li>
          </ul>
          <div v-if="store.agents.length > 20" class="text-xs text-surface-600 mt-1 text-center">
            +{{ store.agents.length - 20 }} more
          </div>
        </div>
      </section>
    </div>

    <!-- Recent Events -->
    <section class="bg-surface-900 border border-surface-800 rounded-xl">
      <div class="px-5 py-4 border-b border-surface-800">
        <h2 class="text-sm font-semibold text-surface-200">Activity Feed</h2>
      </div>
      <div class="p-4 max-h-80 overflow-y-auto">
        <div v-if="store.events.length === 0" class="text-sm text-surface-600 italic py-4 text-center">
          No recent events
        </div>
        <ul class="space-y-2">
          <li
            v-for="(event, idx) in store.events.slice(0, 20)"
            :key="idx"
            class="flex items-start gap-3 px-2 py-1.5 text-sm"
          >
            <span class="text-xs text-surface-600 font-mono flex-shrink-0 mt-0.5">
              {{ formatTime(event.occurred_at) }}
            </span>
            <span class="flex-shrink-0 px-1.5 py-0.5 rounded text-xs font-medium bg-surface-800 text-surface-400">
              {{ event.event_type }}
            </span>
            <span class="text-surface-400 truncate">
              {{ event.message ?? '' }}
            </span>
          </li>
        </ul>
      </div>
    </section>

    <!-- Recent PRs -->
    <section v-if="recentPRs.length > 0" class="bg-surface-900 border border-surface-800 rounded-xl">
      <div class="px-5 py-4 border-b border-surface-800 flex items-center justify-between">
        <h2 class="text-sm font-semibold text-surface-200">Recent Pull Requests</h2>
        <RouterLink to="/prs" class="text-xs text-teal-400 hover:text-teal-300 transition-colors">
          View all
        </RouterLink>
      </div>
      <div class="p-4 space-y-2">
        <div
          v-for="(pr, idx) in recentPRs"
          :key="idx"
          class="flex items-center justify-between px-3 py-2 rounded-lg hover:bg-surface-850 transition-colors"
        >
          <div class="flex items-center gap-3 min-w-0">
            <span class="px-1.5 py-0.5 rounded text-xs font-medium bg-green-400/15 text-green-400 flex-shrink-0">
              PR
            </span>
            <span class="text-sm text-surface-200 truncate">{{ pr.commit_msg ?? "Untitled" }}</span>
            <span v-if="pr.ref" class="text-xs font-mono text-surface-500 bg-surface-800 px-2 py-0.5 rounded flex-shrink-0">
              {{ pr.ref }}
            </span>
          </div>
          <a
            v-if="getPrUrl(pr)"
            :href="getPrUrl(pr)!"
            target="_blank"
            rel="noopener noreferrer"
            class="text-xs text-teal-400 hover:text-teal-300 transition-colors flex-shrink-0 ml-3"
          >
            GitHub
          </a>
        </div>
      </div>
    </section>

    <!-- Cost Leaderboard -->
    <section v-if="costs.length > 0" class="bg-surface-900 border border-surface-800 rounded-xl">
      <div class="px-5 py-4 border-b border-surface-800">
        <h2 class="text-sm font-semibold text-surface-200">Agent Cost Leaderboard</h2>
      </div>
      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead>
            <tr class="text-xs text-surface-500 uppercase tracking-wider border-b border-surface-800">
              <th class="text-left px-5 py-3">Handle</th>
              <th class="text-left px-5 py-3">Model</th>
              <th class="text-left px-5 py-3">Status</th>
              <th class="text-right px-5 py-3">API Calls</th>
              <th class="text-right px-5 py-3">Tokens</th>
              <th class="text-right px-5 py-3">Cost</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in costs.slice(0, 10)"
              :key="row.handle"
              class="border-b border-surface-800/50 hover:bg-surface-850 transition-colors"
            >
              <td class="px-5 py-3 font-medium text-surface-200">{{ row.handle }}</td>
              <td class="px-5 py-3 text-surface-400 font-mono text-xs">{{ row.model }}</td>
              <td class="px-5 py-3" :class="statusColors[row.status] ?? 'text-surface-400'">
                {{ row.status }}
              </td>
              <td class="px-5 py-3 text-right text-surface-400">{{ row.api_calls ?? 0 }}</td>
              <td class="px-5 py-3 text-right text-surface-400 font-mono text-xs">
                {{ (row.total_tokens ?? 0).toLocaleString() }}
              </td>
              <td class="px-5 py-3 text-right text-amber-400 font-mono">
                {{ formatCost(row.total_cost_usd) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- Empty state when nothing is running -->
    <section
      v-if="store.activeSessions.length === 0 && store.events.length === 0 && costs.length === 0"
      class="bg-surface-900 border border-surface-800 rounded-xl p-12 text-center"
    >
      <div class="text-surface-600 space-y-3">
        <div class="text-5xl font-light text-surface-700">ACC v3</div>
        <p class="text-sm">Agency Command Center is ready. No agents are currently reporting.</p>
        <div class="pt-4 space-y-1 text-xs text-surface-700">
          <p>To start tracking agents, send events to:</p>
          <p class="font-mono text-surface-500">POST /api/agent-update</p>
          <p class="font-mono text-surface-500">POST /api/chat-message</p>
          <p class="font-mono text-surface-500">POST /api/pr-created</p>
          <p class="font-mono text-surface-500">POST /api/data-sync</p>
          <p class="font-mono text-surface-500">POST /api/stats-update</p>
        </div>
      </div>
    </section>
  </div>
</template>
