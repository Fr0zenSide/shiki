<script setup lang="ts">
import { useAgencyStore } from "@/composables/useAgencyStore";
import { useWebSocket } from "@/composables/useWebSocket";
import { helpOpen } from "@/composables/useKeyboardShortcuts";

const store = useAgencyStore();
const ws = useWebSocket();
</script>

<template>
  <footer class="px-4 py-3 border-t border-surface-800 space-y-2 relative">
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

    <!-- WS clients from health endpoint -->
    <div v-if="store.health?.services.websocket" class="flex items-center gap-2 text-xs">
      <span class="w-2 h-2 rounded-full bg-teal-400/50" />
      <span class="text-surface-500">
        {{ store.health.services.websocket.clientCount }} WS client{{ store.health.services.websocket.clientCount !== 1 ? 's' : '' }},
        {{ store.health.services.websocket.channelCount }} channel{{ store.health.services.websocket.channelCount !== 1 ? 's' : '' }}
      </span>
    </div>

    <!-- Version + Help -->
    <div class="flex items-center justify-between">
      <div v-if="store.health" class="text-xs text-surface-600">
        v{{ store.health.version }}
      </div>
      <button
        class="w-6 h-6 rounded-lg bg-surface-800 text-surface-500 hover:text-surface-300 hover:bg-surface-700 flex items-center justify-center text-xs font-bold transition-colors"
        title="Keyboard shortcuts (Cmd+/)"
        @click="helpOpen = true"
      >
        ?
      </button>
    </div>
  </footer>
</template>
