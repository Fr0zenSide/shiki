<script setup lang="ts">
import { onMounted } from "vue";
import { useAgencyStore } from "@/composables/useAgencyStore";
import { useWebSocket } from "@/composables/useWebSocket";
import { useKeyboardShortcuts } from "@/composables/useKeyboardShortcuts";
import SidebarNav from "@/components/sidebar/SidebarNav.vue";
import SidebarHealth from "@/components/sidebar/SidebarHealth.vue";
import SidebarProjects from "@/components/sidebar/SidebarProjects.vue";
import SidebarAgents from "@/components/sidebar/SidebarAgents.vue";
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
</script>

<template>
  <div class="flex h-screen overflow-hidden bg-surface-950">
    <!-- Sidebar -->
    <aside class="w-72 flex-shrink-0 flex flex-col border-r border-surface-800 bg-surface-900">
      <!-- Logo -->
      <div class="flex items-center gap-3 px-5 py-4 border-b border-surface-800">
        <div class="w-8 h-8 rounded-lg bg-teal-400 flex items-center justify-center">
          <span class="text-sm font-bold text-surface-900">A3</span>
        </div>
        <div>
          <h1 class="text-sm font-semibold text-surface-100">ACC v3</h1>
          <p class="text-xs text-surface-500">Agency Command Center</p>
        </div>
      </div>

      <!-- Nav links -->
      <SidebarNav />

      <!-- Scrollable content -->
      <div class="flex-1 overflow-y-auto px-4 py-3 space-y-5">
        <SidebarProjects />
        <SidebarAgents />
      </div>

      <!-- Health footer -->
      <SidebarHealth />
    </aside>

    <!-- Main content -->
    <main class="flex-1 overflow-y-auto">
      <RouterView />
    </main>
  </div>

  <!-- Global overlays -->
  <ShortcutHelpModal />
  <FzfPanel />
</template>
