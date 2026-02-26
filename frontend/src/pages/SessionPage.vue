<script setup lang="ts">
import { onMounted, watch } from "vue";
import { useAgencyStore } from "@/composables/useAgencyStore";
import { useWebSocket } from "@/composables/useWebSocket";

const props = defineProps<{ id: string }>();
const store = useAgencyStore();
const ws = useWebSocket();

const statusBadge: Record<string, string> = {
  active: "bg-green-400/15 text-green-400",
  paused: "bg-amber-400/15 text-amber-400",
  completed: "bg-surface-700 text-surface-400",
  failed: "bg-red-400/15 text-red-400",
};

const agentStatusDot: Record<string, string> = {
  spawned: "bg-blue-400",
  running: "bg-green-400 animate-pulse",
  completed: "bg-surface-500",
  failed: "bg-red-400",
  cancelled: "bg-surface-600",
};

function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
}

async function loadSession() {
  store.selectSession(props.id);
  // Also subscribe to session-specific WS channel
  ws.subscribe(`session:${props.id}`);
}

onMounted(loadSession);
watch(() => props.id, loadSession);
</script>

<template>
  <div class="p-6 space-y-6 max-w-6xl mx-auto">
    <!-- Session header -->
    <div v-if="store.selectedSession" class="space-y-2">
      <div class="flex items-center gap-3">
        <h1 class="text-2xl font-semibold text-surface-100">{{ store.selectedSession.name }}</h1>
        <span
          class="text-xs px-2 py-0.5 rounded-full font-medium"
          :class="statusBadge[store.selectedSession.status] ?? 'bg-surface-700 text-surface-400'"
        >
          {{ store.selectedSession.status }}
        </span>
      </div>
      <div class="text-sm text-surface-500 flex items-center gap-4">
        <span v-if="store.selectedSession.branch" class="font-mono text-xs bg-surface-800 px-2 py-0.5 rounded">
          {{ store.selectedSession.branch }}
        </span>
        <span>Started {{ formatDate(store.selectedSession.started_at) }}</span>
      </div>
      <p v-if="store.selectedSession.summary" class="text-sm text-surface-400 mt-2">
        {{ store.selectedSession.summary }}
      </p>
    </div>

    <div v-else class="text-surface-500">Loading session...</div>

    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <!-- Agents list -->
      <section class="lg:col-span-1 bg-surface-900 border border-surface-800 rounded-xl">
        <div class="px-5 py-4 border-b border-surface-800 flex items-center justify-between">
          <h2 class="text-sm font-semibold text-surface-200">Agents</h2>
          <span class="text-xs text-surface-500">{{ store.sessionAgents.length }}</span>
        </div>
        <div class="p-3 space-y-1 max-h-96 overflow-y-auto">
          <div v-if="store.sessionAgents.length === 0" class="text-sm text-surface-600 italic py-4 text-center">
            No agents in this session
          </div>
          <div
            v-for="agent in store.sessionAgents"
            :key="agent.id"
            class="px-3 py-2.5 rounded-lg hover:bg-surface-850 transition-colors"
          >
            <div class="flex items-center gap-2">
              <span class="w-2 h-2 rounded-full flex-shrink-0" :class="agentStatusDot[agent.status]" />
              <span class="text-sm font-medium text-surface-200 truncate">{{ agent.handle }}</span>
            </div>
            <div class="text-xs text-surface-500 mt-1 ml-4 flex items-center gap-2">
              <span class="font-mono">{{ agent.model }}</span>
              <span>&middot;</span>
              <span>{{ agent.role }}</span>
            </div>
            <div class="text-xs text-surface-600 mt-0.5 ml-4">
              Spawned {{ formatTime(agent.spawned_at) }}
              <template v-if="agent.completed_at"> &middot; Done {{ formatTime(agent.completed_at) }}</template>
            </div>
          </div>
        </div>
      </section>

      <!-- Events timeline -->
      <section class="lg:col-span-2 bg-surface-900 border border-surface-800 rounded-xl">
        <div class="px-5 py-4 border-b border-surface-800 flex items-center justify-between">
          <h2 class="text-sm font-semibold text-surface-200">Event Timeline</h2>
          <span class="text-xs text-surface-500">{{ store.events.length }} events</span>
        </div>
        <div class="p-4 max-h-[600px] overflow-y-auto">
          <div v-if="store.events.length === 0" class="text-sm text-surface-600 italic py-8 text-center">
            No events recorded yet
          </div>
          <div class="space-y-3">
            <div
              v-for="(event, idx) in store.events"
              :key="idx"
              class="flex items-start gap-3 text-sm"
            >
              <!-- Timeline dot -->
              <div class="flex flex-col items-center flex-shrink-0 mt-1">
                <div class="w-2 h-2 rounded-full bg-teal-400/60" />
                <div v-if="idx < store.events.length - 1" class="w-px h-6 bg-surface-800 mt-1" />
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
                <p v-if="event.message" class="text-surface-400 mt-0.5 text-sm">
                  {{ event.message }}
                </p>
              </div>
            </div>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>
