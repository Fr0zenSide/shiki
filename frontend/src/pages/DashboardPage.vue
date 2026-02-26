<script setup lang="ts">
import { ref, onMounted, computed } from "vue";
import { useAgencyStore } from "@/composables/useAgencyStore";
import { useApi } from "@/composables/useApi";
import type { CostLeaderEntry } from "@/types";

const store = useAgencyStore();
const api = useApi();
const costs = ref<CostLeaderEntry[]>([]);

onMounted(async () => {
  await Promise.all([
    store.fetchActiveSessions(),
    store.fetchEvents(undefined, 30),
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

const totalCost = computed(() =>
  costs.value.reduce((sum, c) => sum + (c.total_cost_usd ?? 0), 0),
);

function formatCost(usd: number | null): string {
  if (usd == null) return "$0.00";
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

const statusColors: Record<string, string> = {
  spawned: "text-blue-400",
  running: "text-green-400",
  completed: "text-surface-500",
  failed: "text-red-400",
  cancelled: "text-surface-600",
};
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
        @click="store.fetchHealth()"
      >
        Refresh
      </button>
    </div>

    <!-- Stats cards -->
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
      <!-- Active sessions -->
      <div class="bg-surface-900 border border-surface-800 rounded-xl p-4">
        <div class="text-xs text-surface-500 uppercase tracking-wider">Active Sessions</div>
        <div class="text-3xl font-bold text-surface-100 mt-2">{{ store.activeSessions.length }}</div>
      </div>

      <!-- Agents running -->
      <div class="bg-surface-900 border border-surface-800 rounded-xl p-4">
        <div class="text-xs text-surface-500 uppercase tracking-wider">Agents Running</div>
        <div class="text-3xl font-bold text-green-400 mt-2">{{ store.activeAgentCount }}</div>
      </div>

      <!-- Total agents -->
      <div class="bg-surface-900 border border-surface-800 rounded-xl p-4">
        <div class="text-xs text-surface-500 uppercase tracking-wider">Total Agents</div>
        <div class="text-3xl font-bold text-surface-100 mt-2">{{ store.agents.length }}</div>
      </div>

      <!-- Total cost -->
      <div class="bg-surface-900 border border-surface-800 rounded-xl p-4">
        <div class="text-xs text-surface-500 uppercase tracking-wider">Total Cost</div>
        <div class="text-3xl font-bold text-amber-400 mt-2">{{ formatCost(totalCost) }}</div>
      </div>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <!-- Active Sessions -->
      <section class="bg-surface-900 border border-surface-800 rounded-xl">
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
              <div class="text-xs text-teal-400 font-mono">
                {{ formatDuration(session.hours_active) }}
              </div>
            </li>
          </ul>
        </div>
      </section>

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
    </div>

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
  </div>
</template>
