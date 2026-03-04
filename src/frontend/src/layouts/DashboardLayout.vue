<script setup lang="ts">
import { onMounted } from "vue";
import { useAgencyStore } from "@/composables/useAgencyStore";
import { useWebSocket } from "@/composables/useWebSocket";
import { useKeyboardShortcuts, fzfOpen } from "@/composables/useKeyboardShortcuts";
import TopNavbar from "@/components/TopNavbar.vue";
import ShortcutHelpModal from "@/components/ShortcutHelpModal.vue";
import FzfPanel from "@/components/fzf/FzfPanel.vue";
import type { WsIncoming } from "@/types";

const store = useAgencyStore();
const ws = useWebSocket();

// Initialize keyboard shortcuts at layout level
useKeyboardShortcuts();

// Wire WebSocket messages into the store
ws.onMessage((msg: WsIncoming) => {
  switch (msg.type) {
    case "chat":
      store.handleWsChat(msg);
      break;
    case "agent_event":
      store.handleWsAgentEvent(msg.event);
      break;
    case "pr_created":
      store.handleWsPrCreated(msg);
      store.fetchEvents();
      break;
    case "data_sync":
      store.fetchEvents();
      break;
    case "stats_update":
      store.handleWsStatsUpdate();
      break;
  }
});

onMounted(async () => {
  await store.fetchSessions();
  await store.fetchActiveSessions();
  // Subscribe to the "all" channel for global updates
  ws.subscribe("all");
});

function openFzf() {
  fzfOpen.value = true;
}
</script>

<template>
  <div class="flex flex-col h-screen overflow-hidden bg-surface-950">
    <!-- Top Navbar -->
    <TopNavbar @open-fzf="openFzf" />

    <!-- Main content -->
    <main class="flex-1 overflow-y-auto">
      <RouterView />
    </main>
  </div>

  <!-- Global overlays -->
  <ShortcutHelpModal />
  <FzfPanel />
</template>
