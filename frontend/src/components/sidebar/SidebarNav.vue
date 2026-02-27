<script setup lang="ts">
import { useRoute } from "vue-router";

const route = useRoute();

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
</script>

<template>
  <nav class="px-3 py-3 border-b border-surface-800">
    <ul class="space-y-1">
      <li v-for="link in links" :key="link.to">
        <RouterLink
          :to="link.to"
          class="flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors"
          :class="isActive(link.to)
            ? 'bg-teal-400/10 text-teal-400'
            : 'text-surface-400 hover:text-surface-200 hover:bg-surface-800'"
        >
          <!-- Simple icon indicators -->
          <span
            class="w-5 h-5 rounded flex items-center justify-center text-xs"
            :class="isActive(link.to) ? 'bg-teal-400/20' : 'bg-surface-800'"
          >
            <!-- Dashboard grid icon -->
            <template v-if="link.icon === 'grid'">
              <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 16 16">
                <path d="M1 2.5A1.5 1.5 0 012.5 1h3A1.5 1.5 0 017 2.5v3A1.5 1.5 0 015.5 7h-3A1.5 1.5 0 011 5.5v-3zM2.5 2a.5.5 0 00-.5.5v3a.5.5 0 00.5.5h3a.5.5 0 00.5-.5v-3a.5.5 0 00-.5-.5h-3zm6.5.5A1.5 1.5 0 0110.5 1h3A1.5 1.5 0 0115 2.5v3A1.5 1.5 0 0113.5 7h-3A1.5 1.5 0 019 5.5v-3zm1.5-.5a.5.5 0 00-.5.5v3a.5.5 0 00.5.5h3a.5.5 0 00.5-.5v-3a.5.5 0 00-.5-.5h-3zM1 10.5A1.5 1.5 0 012.5 9h3A1.5 1.5 0 017 10.5v3A1.5 1.5 0 015.5 15h-3A1.5 1.5 0 011 13.5v-3zm1.5-.5a.5.5 0 00-.5.5v3a.5.5 0 00.5.5h3a.5.5 0 00.5-.5v-3a.5.5 0 00-.5-.5h-3zm6.5.5A1.5 1.5 0 0110.5 9h3a1.5 1.5 0 011.5 1.5v3a1.5 1.5 0 01-1.5 1.5h-3A1.5 1.5 0 019 13.5v-3zm1.5-.5a.5.5 0 00-.5.5v3a.5.5 0 00.5.5h3a.5.5 0 00.5-.5v-3a.5.5 0 00-.5-.5h-3z"/>
              </svg>
            </template>
            <!-- Agents (people) icon -->
            <template v-else-if="link.icon === 'agents'">
              <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 16 16">
                <path d="M7 14s-1 0-1-1 1-4 5-4 5 3 5 4-1 1-1 1H7zm4-6a3 3 0 100-6 3 3 0 000 6z"/>
                <path fill-rule="evenodd" d="M5.216 14A2.238 2.238 0 015 13c0-1.355.68-2.75 1.936-3.72A6.325 6.325 0 005 9c-4 0-5 3-5 4s1 1 1 1h4.216z"/>
                <path d="M4.5 8a2.5 2.5 0 100-5 2.5 2.5 0 000 5z"/>
              </svg>
            </template>
            <!-- Chat message icon -->
            <template v-else-if="link.icon === 'message'">
              <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 16 16">
                <path d="M2.678 11.894a1 1 0 01.287.801 10.97 10.97 0 01-.398 2c1.395-.323 2.247-.697 2.634-.893a1 1 0 01.71-.074A8.06 8.06 0 008 14c3.996 0 7-2.807 7-6 0-3.192-3.004-6-7-6S1 4.808 1 8c0 1.468.617 2.83 1.678 3.894zm-.493 3.905a21.682 21.682 0 01-.713.129c-.2.032-.352-.176-.273-.362a9.68 9.68 0 00.244-.637l.003-.01c.248-.72.45-1.548.524-2.319C.743 11.37 0 9.76 0 8c0-3.866 3.582-7 8-7s8 3.134 8 7-3.582 7-8 7a9.06 9.06 0 01-2.347-.306c-.52.263-1.639.742-3.468 1.105z"/>
              </svg>
            </template>
            <!-- Memory (brain/database) icon -->
            <template v-else-if="link.icon === 'memory'">
              <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 16 16">
                <path d="M0 5a2 2 0 012-2h12a2 2 0 012 2v2a2 2 0 01-2 2H2a2 2 0 01-2-2V5zm13 1a1 1 0 10-2 0 1 1 0 002 0zm-1 4a1 1 0 100 2 1 1 0 000-2zM2 11a2 2 0 00-2 2v.5a.5.5 0 00.5.5h15a.5.5 0 00.5-.5V13a2 2 0 00-2-2H2z"/>
              </svg>
            </template>
            <!-- Git (branch) icon -->
            <template v-else-if="link.icon === 'git'">
              <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 16 16">
                <path d="M6 3a3 3 0 11-2 5.65V11a2 2 0 002 2h4.5a.5.5 0 000-1H6a1 1 0 01-1-1V8.65A3 3 0 006 3zm0 4.5a1.5 1.5 0 100-3 1.5 1.5 0 000 3zm6.5 1a3 3 0 110 6 3 3 0 010-6zm0 4.5a1.5 1.5 0 100-3 1.5 1.5 0 000 3z"/>
              </svg>
            </template>
          </span>
          {{ link.label }}
        </RouterLink>
      </li>
    </ul>
  </nav>
</template>
