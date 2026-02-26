<script setup lang="ts">
import { computed } from "vue";
import { useAgencyStore } from "@/composables/useAgencyStore";

const store = useAgencyStore();

const statusColors: Record<string, string> = {
  spawned: "bg-blue-400",
  running: "bg-green-400",
  completed: "bg-surface-500",
  failed: "bg-red-400",
  cancelled: "bg-surface-600",
};

const displayAgents = computed(() => store.sessionAgents.slice(0, 20));
</script>

<template>
  <section>
    <div class="flex items-center justify-between mb-2">
      <h2 class="text-xs font-medium uppercase tracking-wider text-surface-500">Agents</h2>
      <span
        v-if="store.activeAgentCount > 0"
        class="text-xs px-1.5 py-0.5 rounded-full bg-green-400/15 text-green-400"
      >
        {{ store.activeAgentCount }} active
      </span>
    </div>

    <div v-if="store.agents.length === 0" class="text-xs text-surface-600 italic">
      No agents yet
    </div>

    <ul class="space-y-1">
      <li
        v-for="agent in displayAgents"
        :key="agent.id"
        class="flex items-center gap-2 px-2 py-1.5 rounded text-sm"
      >
        <span class="w-2 h-2 rounded-full flex-shrink-0" :class="statusColors[agent.status] ?? 'bg-surface-600'" />
        <span class="truncate text-surface-300 flex-1">{{ agent.handle }}</span>
        <span class="text-xs text-surface-600 flex-shrink-0">{{ agent.model.split('/').pop() }}</span>
      </li>
    </ul>

    <div v-if="store.agents.length > 20" class="text-xs text-surface-600 mt-1 text-center">
      +{{ store.agents.length - 20 }} more
    </div>
  </section>
</template>
