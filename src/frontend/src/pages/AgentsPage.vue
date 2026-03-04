<script setup lang="ts">
import { onMounted, computed } from "vue";
import { useAgencyStore } from "@/composables/useAgencyStore";

const store = useAgencyStore();

onMounted(async () => {
  await store.fetchAgents();
  await store.fetchEvents(undefined, 100);
});

function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
}

const statusDot: Record<string, string> = {
  spawned: "bg-blue-400",
  running: "bg-green-400 animate-pulse",
  completed: "bg-surface-500",
  failed: "bg-red-400",
  cancelled: "bg-surface-600",
};

const statusBadge: Record<string, string> = {
  spawned: "bg-blue-400/15 text-blue-400",
  running: "bg-green-400/15 text-green-400",
  completed: "bg-surface-700 text-surface-400",
  failed: "bg-red-400/15 text-red-400",
  cancelled: "bg-surface-700 text-surface-500",
};

const runningAgents = computed(() =>
  store.agents.filter((a) => a.status === "running" || a.status === "spawned"),
);

const completedAgents = computed(() =>
  store.agents.filter((a) => a.status === "completed"),
);

const failedAgents = computed(() =>
  store.agents.filter((a) => a.status === "failed"),
);
</script>

<template>
  <div class="p-6 space-y-6 max-w-7xl mx-auto">
    <!-- Header -->
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-semibold text-surface-100">Agents</h1>
        <p class="text-sm text-surface-500 mt-1">
          {{ store.agents.length }} total &middot;
          {{ runningAgents.length }} running &middot;
          {{ completedAgents.length }} completed &middot;
          {{ failedAgents.length }} failed
        </p>
      </div>
      <button
        class="px-3 py-1.5 rounded-lg bg-surface-800 text-surface-300 text-sm hover:bg-surface-700 transition-colors"
        @click="store.fetchAgents()"
      >
        Refresh
      </button>
    </div>

    <!-- Running agents (highlighted) -->
    <section v-if="runningAgents.length > 0">
      <h2 class="text-xs font-medium uppercase tracking-wider text-green-400 mb-3">Active</h2>
      <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
        <div
          v-for="agent in runningAgents"
          :key="agent.id"
          class="bg-surface-900 border border-green-400/20 rounded-xl p-4 hover:border-green-400/40 transition-colors cursor-pointer"
          @click="$router.push({ name: 'session', params: { id: agent.session_id } })"
        >
          <div class="flex items-center gap-2 mb-2">
            <span class="w-2.5 h-2.5 rounded-full animate-pulse" :class="statusDot[agent.status]" />
            <span class="text-sm font-semibold text-surface-100">{{ agent.handle }}</span>
            <span
              class="ml-auto text-xs px-2 py-0.5 rounded-full font-medium"
              :class="statusBadge[agent.status]"
            >
              {{ agent.status }}
            </span>
          </div>
          <div class="text-xs text-surface-500 space-y-1">
            <div class="flex items-center gap-2">
              <span class="text-surface-600">Role:</span>
              <span>{{ agent.role }}</span>
            </div>
            <div class="flex items-center gap-2">
              <span class="text-surface-600">Model:</span>
              <span class="font-mono">{{ agent.model }}</span>
            </div>
            <div class="flex items-center gap-2">
              <span class="text-surface-600">Spawned:</span>
              <span>{{ formatDate(agent.spawned_at) }}</span>
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- All agents table -->
    <section class="bg-surface-900 border border-surface-800 rounded-xl">
      <div class="px-5 py-4 border-b border-surface-800">
        <h2 class="text-sm font-semibold text-surface-200">All Agents</h2>
      </div>

      <div v-if="store.agents.length === 0" class="p-8 text-center">
        <div class="text-surface-600 space-y-2">
          <div class="text-4xl">--</div>
          <p class="text-sm">No agents have been spawned yet.</p>
          <p class="text-xs text-surface-700">
            Agents will appear here when they report via POST /api/agent-update
          </p>
        </div>
      </div>

      <div v-else class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead>
            <tr class="text-xs text-surface-500 uppercase tracking-wider border-b border-surface-800">
              <th class="text-left px-5 py-3">Status</th>
              <th class="text-left px-5 py-3">Handle</th>
              <th class="text-left px-5 py-3">Role</th>
              <th class="text-left px-5 py-3">Model</th>
              <th class="text-left px-5 py-3">Spawned</th>
              <th class="text-left px-5 py-3">Completed</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="agent in store.agents"
              :key="agent.id"
              class="border-b border-surface-800/50 hover:bg-surface-850 transition-colors cursor-pointer"
              @click="$router.push({ name: 'session', params: { id: agent.session_id } })"
            >
              <td class="px-5 py-3">
                <div class="flex items-center gap-2">
                  <span class="w-2 h-2 rounded-full" :class="statusDot[agent.status]" />
                  <span
                    class="text-xs px-1.5 py-0.5 rounded-full font-medium"
                    :class="statusBadge[agent.status]"
                  >
                    {{ agent.status }}
                  </span>
                </div>
              </td>
              <td class="px-5 py-3 font-medium text-surface-200">{{ agent.handle }}</td>
              <td class="px-5 py-3 text-surface-400">{{ agent.role }}</td>
              <td class="px-5 py-3 text-surface-400 font-mono text-xs">{{ agent.model }}</td>
              <td class="px-5 py-3 text-surface-500 text-xs">{{ formatDate(agent.spawned_at) }}</td>
              <td class="px-5 py-3 text-surface-500 text-xs">
                {{ agent.completed_at ? formatDate(agent.completed_at) : "---" }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- Event Timeline -->
    <section class="bg-surface-900 border border-surface-800 rounded-xl">
      <div class="px-5 py-4 border-b border-surface-800">
        <h2 class="text-sm font-semibold text-surface-200">Recent Agent Events</h2>
      </div>
      <div class="p-4 max-h-96 overflow-y-auto">
        <div v-if="store.events.length === 0" class="text-sm text-surface-600 italic py-4 text-center">
          No events recorded
        </div>
        <div class="space-y-2">
          <div
            v-for="(event, idx) in store.events.slice(0, 50)"
            :key="idx"
            class="flex items-start gap-3 text-sm"
          >
            <div class="flex flex-col items-center flex-shrink-0 mt-1">
              <div class="w-2 h-2 rounded-full bg-teal-400/60" />
              <div v-if="idx < Math.min(store.events.length, 50) - 1" class="w-px h-4 bg-surface-800 mt-1" />
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 flex-wrap">
                <span class="text-xs font-mono text-surface-600">{{ formatTime(event.occurred_at) }}</span>
                <span class="px-1.5 py-0.5 rounded text-xs font-medium bg-teal-400/10 text-teal-400">
                  {{ event.event_type }}
                </span>
                <span v-if="event.progress_pct != null" class="text-xs text-surface-500">
                  {{ event.progress_pct }}%
                </span>
              </div>
              <p v-if="event.message" class="text-surface-400 mt-0.5 text-xs truncate">
                {{ event.message }}
              </p>
            </div>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
