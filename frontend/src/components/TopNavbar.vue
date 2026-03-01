<script setup lang="ts">
import { ref } from "vue";
import { useRoute } from "vue-router";
import { useAgencyStore } from "@/composables/useAgencyStore";
import { useWebSocket } from "@/composables/useWebSocket";
import { helpOpen } from "@/composables/useKeyboardShortcuts";

const route = useRoute();
const store = useAgencyStore();
const ws = useWebSocket();

const projectDropdownOpen = ref(false);

const links = [
  { to: "/", label: "Dashboard", icon: "grid" },
  { to: "/agents", label: "Agents", icon: "agents" },
  { to: "/chat", label: "Chat", icon: "message" },
  { to: "/memory", label: "Memory", icon: "memory" },
  { to: "/prs", label: "PRs & Git", icon: "git" },
];

function isActive(path: string): boolean {
  if (path === "/") return route.path === "/";
  return route.path.startsWith(path);
}

function toggleProjectDropdown() {
  projectDropdownOpen.value = !projectDropdownOpen.value;
}

function selectProject(id: string) {
  store.selectProject(id);
  projectDropdownOpen.value = false;
}

// Close dropdown on outside click
function onDropdownBlur() {
  // Delay to allow click to register
  setTimeout(() => {
    projectDropdownOpen.value = false;
  }, 150);
}

type HealthColor = "bg-green-400" | "bg-red-400" | "bg-amber-400" | "bg-surface-600";

function healthDotColor(): HealthColor {
  if (!store.health) return "bg-surface-600";
  if (ws.status.value !== "connected") return "bg-amber-400";
  return store.isHealthy ? "bg-green-400" : "bg-red-400";
}

function healthTooltip(): string {
  if (!store.health) return "Backend unreachable";
  const parts = [`Backend ${store.health.status}`];
  parts.push(`Uptime: ${store.health.uptime.human}`);
  parts.push(`WS: ${ws.status.value}`);
  if (store.health.services.websocket) {
    parts.push(`${store.health.services.websocket.clientCount} WS client(s)`);
  }
  if (store.health.version) {
    parts.push(`v${store.health.version}`);
  }
  return parts.join(" \u00B7 ");
}
</script>

<template>
  <header class="h-14 flex-shrink-0 flex items-center px-4 border-b border-surface-800 bg-surface-900">
    <!-- Left: Logo + Nav -->
    <div class="flex items-center gap-1 min-w-0">
      <!-- Logo -->
      <RouterLink to="/" class="flex items-center gap-2 mr-4 flex-shrink-0">
        <div class="w-7 h-7 rounded-lg bg-teal-400 flex items-center justify-center">
          <span class="text-xs font-bold text-surface-900">A3</span>
        </div>
        <span class="text-sm font-semibold text-surface-200 hidden sm:inline">ACC</span>
      </RouterLink>

      <!-- Nav links -->
      <nav class="flex items-center gap-0.5">
        <RouterLink
          v-for="link in links"
          :key="link.to"
          :to="link.to"
          class="relative flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm transition-colors"
          :class="isActive(link.to)
            ? 'text-teal-400 bg-teal-400/10'
            : 'text-surface-400 hover:text-surface-200 hover:bg-surface-800'"
        >
          <!-- Inline SVG icons -->
          <svg v-if="link.icon === 'grid'" class="w-3.5 h-3.5 flex-shrink-0" fill="currentColor" viewBox="0 0 16 16">
            <path d="M1 2.5A1.5 1.5 0 012.5 1h3A1.5 1.5 0 017 2.5v3A1.5 1.5 0 015.5 7h-3A1.5 1.5 0 011 5.5v-3zM2.5 2a.5.5 0 00-.5.5v3a.5.5 0 00.5.5h3a.5.5 0 00.5-.5v-3a.5.5 0 00-.5-.5h-3zm6.5.5A1.5 1.5 0 0110.5 1h3A1.5 1.5 0 0115 2.5v3A1.5 1.5 0 0113.5 7h-3A1.5 1.5 0 019 5.5v-3zm1.5-.5a.5.5 0 00-.5.5v3a.5.5 0 00.5.5h3a.5.5 0 00.5-.5v-3a.5.5 0 00-.5-.5h-3zM1 10.5A1.5 1.5 0 012.5 9h3A1.5 1.5 0 017 10.5v3A1.5 1.5 0 015.5 15h-3A1.5 1.5 0 011 13.5v-3zm1.5-.5a.5.5 0 00-.5.5v3a.5.5 0 00.5.5h3a.5.5 0 00.5-.5v-3a.5.5 0 00-.5-.5h-3zm6.5.5A1.5 1.5 0 0110.5 9h3a1.5 1.5 0 011.5 1.5v3a1.5 1.5 0 01-1.5 1.5h-3A1.5 1.5 0 019 13.5v-3zm1.5-.5a.5.5 0 00-.5.5v3a.5.5 0 00.5.5h3a.5.5 0 00.5-.5v-3a.5.5 0 00-.5-.5h-3z"/>
          </svg>
          <svg v-else-if="link.icon === 'agents'" class="w-3.5 h-3.5 flex-shrink-0" fill="currentColor" viewBox="0 0 16 16">
            <path d="M7 14s-1 0-1-1 1-4 5-4 5 3 5 4-1 1-1 1H7zm4-6a3 3 0 100-6 3 3 0 000 6z"/>
            <path fill-rule="evenodd" d="M5.216 14A2.238 2.238 0 015 13c0-1.355.68-2.75 1.936-3.72A6.325 6.325 0 005 9c-4 0-5 3-5 4s1 1 1 1h4.216z"/>
            <path d="M4.5 8a2.5 2.5 0 100-5 2.5 2.5 0 000 5z"/>
          </svg>
          <svg v-else-if="link.icon === 'message'" class="w-3.5 h-3.5 flex-shrink-0" fill="currentColor" viewBox="0 0 16 16">
            <path d="M2.678 11.894a1 1 0 01.287.801 10.97 10.97 0 01-.398 2c1.395-.323 2.247-.697 2.634-.893a1 1 0 01.71-.074A8.06 8.06 0 008 14c3.996 0 7-2.807 7-6 0-3.192-3.004-6-7-6S1 4.808 1 8c0 1.468.617 2.83 1.678 3.894zm-.493 3.905a21.682 21.682 0 01-.713.129c-.2.032-.352-.176-.273-.362a9.68 9.68 0 00.244-.637l.003-.01c.248-.72.45-1.548.524-2.319C.743 11.37 0 9.76 0 8c0-3.866 3.582-7 8-7s8 3.134 8 7-3.582 7-8 7a9.06 9.06 0 01-2.347-.306c-.52.263-1.639.742-3.468 1.105z"/>
          </svg>
          <svg v-else-if="link.icon === 'memory'" class="w-3.5 h-3.5 flex-shrink-0" fill="currentColor" viewBox="0 0 16 16">
            <path d="M0 5a2 2 0 012-2h12a2 2 0 012 2v2a2 2 0 01-2 2H2a2 2 0 01-2-2V5zm13 1a1 1 0 10-2 0 1 1 0 002 0zm-1 4a1 1 0 100 2 1 1 0 000-2zM2 11a2 2 0 00-2 2v.5a.5.5 0 00.5.5h15a.5.5 0 00.5-.5V13a2 2 0 00-2-2H2z"/>
          </svg>
          <svg v-else-if="link.icon === 'git'" class="w-3.5 h-3.5 flex-shrink-0" fill="currentColor" viewBox="0 0 16 16">
            <path d="M6 3a3 3 0 11-2 5.65V11a2 2 0 002 2h4.5a.5.5 0 000-1H6a1 1 0 01-1-1V8.65A3 3 0 006 3zm0 4.5a1.5 1.5 0 100-3 1.5 1.5 0 000 3zm6.5 1a3 3 0 110 6 3 3 0 010-6zm0 4.5a1.5 1.5 0 100-3 1.5 1.5 0 000 3z"/>
          </svg>

          <span class="hidden md:inline">{{ link.label }}</span>

          <!-- Chat unread badge -->
          <span
            v-if="link.icon === 'message' && store.unreadChatCount > 0"
            class="absolute -top-0.5 -right-0.5 min-w-[1rem] h-4 px-1 rounded-full bg-red-500 text-white text-[10px] font-bold flex items-center justify-center"
          >
            {{ store.unreadChatCount > 99 ? '99+' : store.unreadChatCount }}
          </span>
        </RouterLink>
      </nav>
    </div>

    <!-- Spacer -->
    <div class="flex-1" />

    <!-- Right: Project selector, Health, Help, FZF -->
    <div class="flex items-center gap-2">
      <!-- Project dropdown -->
      <div class="relative">
        <button
          class="flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm transition-colors hover:bg-surface-800"
          :class="projectDropdownOpen ? 'bg-surface-800 text-surface-200' : 'text-surface-400'"
          @click="toggleProjectDropdown"
          @blur="onDropdownBlur"
        >
          <span class="truncate max-w-[140px]">{{ store.selectedProject?.name ?? 'No project' }}</span>
          <svg class="w-3 h-3 transition-transform" :class="projectDropdownOpen ? 'rotate-180' : ''" fill="currentColor" viewBox="0 0 16 16">
            <path fill-rule="evenodd" d="M1.646 4.646a.5.5 0 01.708 0L8 10.293l5.646-5.647a.5.5 0 01.708.708l-6 6a.5.5 0 01-.708 0l-6-6a.5.5 0 010-.708z"/>
          </svg>
        </button>

        <!-- Dropdown menu -->
        <div
          v-if="projectDropdownOpen"
          class="absolute right-0 top-full mt-1 w-56 bg-surface-850 border border-surface-700 rounded-xl shadow-xl z-50 py-1 overflow-hidden"
        >
          <div class="px-3 py-2 text-xs text-surface-500 uppercase tracking-wider">Projects</div>
          <button
            v-for="project in store.projects"
            :key="project.id"
            class="w-full text-left px-3 py-2 text-sm transition-colors"
            :class="store.selectedProjectId === project.id
              ? 'bg-teal-400/10 text-teal-400'
              : 'text-surface-300 hover:bg-surface-800 hover:text-surface-100'"
            @mousedown.prevent="selectProject(project.id)"
          >
            <div class="font-medium">{{ project.name }}</div>
            <div class="text-xs text-surface-500 mt-0.5">{{ project.slug }}</div>
          </button>
          <div v-if="store.projects.length === 0" class="px-3 py-2 text-xs text-surface-600 italic">
            No projects found
          </div>
        </div>
      </div>

      <!-- Health indicator -->
      <div class="relative group">
        <div
          class="w-6 h-6 rounded-lg flex items-center justify-center cursor-default"
          :title="healthTooltip()"
        >
          <span class="w-2.5 h-2.5 rounded-full" :class="healthDotColor()" />
        </div>
      </div>

      <!-- Help button -->
      <button
        class="w-7 h-7 rounded-lg bg-surface-800 text-surface-500 hover:text-surface-300 hover:bg-surface-700 flex items-center justify-center text-xs font-bold transition-colors"
        title="Keyboard shortcuts (Cmd+/)"
        @click="helpOpen = true"
      >
        ?
      </button>

      <!-- FZF trigger -->
      <button
        class="hidden sm:flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg bg-surface-800 text-surface-500 hover:text-surface-300 hover:bg-surface-700 text-xs transition-colors"
        title="Command palette (Cmd+P)"
        @click="$emit('openFzf')"
      >
        <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z"/>
        </svg>
        <kbd class="font-mono text-[10px] text-surface-600">&#8984;P</kbd>
      </button>
    </div>
  </header>
</template>
