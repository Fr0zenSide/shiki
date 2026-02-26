<script setup lang="ts">
import { useAgencyStore } from "@/composables/useAgencyStore";
import { useWebSocket } from "@/composables/useWebSocket";

const store = useAgencyStore();
const ws = useWebSocket();
</script>

<template>
  <footer class="px-4 py-3 border-t border-surface-800 space-y-2">
    <!-- WebSocket status -->
    <div class="flex items-center gap-2 text-xs">
      <span
        class="w-2 h-2 rounded-full"
        :class="{
          'bg-green-400': ws.status.value === 'connected',
          'bg-amber-400 animate-pulse': ws.status.value === 'connecting',
          'bg-red-400': ws.status.value === 'error',
          'bg-surface-600': ws.status.value === 'disconnected',
        }"
      />
      <span class="text-surface-500">WS {{ ws.status.value }}</span>
    </div>

    <!-- Backend health -->
    <div class="flex items-center gap-2 text-xs">
      <span
        class="w-2 h-2 rounded-full"
        :class="store.isHealthy ? 'bg-green-400' : 'bg-red-400'"
      />
      <span class="text-surface-500">
        <template v-if="store.health">
          Backend {{ store.health.status }} ({{ store.health.uptime.human }})
        </template>
        <template v-else>Backend unreachable</template>
      </span>
    </div>

    <!-- Version -->
    <div v-if="store.health" class="text-xs text-surface-600">
      v{{ store.health.version }}
    </div>
  </footer>
</template>
