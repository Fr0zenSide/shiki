<script setup lang="ts">
import { useAgencyStore } from "@/composables/useAgencyStore";

const store = useAgencyStore();
</script>

<template>
  <section>
    <h2 class="text-xs font-medium uppercase tracking-wider text-surface-500 mb-2">Projects</h2>
    <div v-if="store.projects.length === 0" class="text-xs text-surface-600 italic">
      No projects found
    </div>
    <ul class="space-y-1">
      <li v-for="project in store.projects" :key="project.id">
        <button
          class="w-full text-left px-3 py-2 rounded-lg text-sm transition-colors"
          :class="store.selectedProjectId === project.id
            ? 'bg-teal-400/10 text-teal-400'
            : 'text-surface-300 hover:bg-surface-800 hover:text-surface-100'"
          @click="store.selectProject(project.id)"
        >
          <div class="font-medium">{{ project.name }}</div>
          <div class="text-xs text-surface-500 mt-0.5">{{ project.slug }}</div>
        </button>
      </li>
    </ul>
  </section>
</template>
