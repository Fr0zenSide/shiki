<script setup lang="ts">
import { ref, watch, computed } from "vue";
import type { FzfResult, RecentItem, EntityCategory } from "@/composables/useFzfSearch";

const props = defineProps<{
  results: FzfResult[];
  recents: RecentItem[];
  query: string;
  isSearching: boolean;
}>();

const emit = defineEmits<{
  select: [result: FzfResult];
}>();

const selectedIndex = ref(0);

// Reset selection when results change
watch(
  () => props.results.length,
  () => {
    selectedIndex.value = 0;
  },
);

// Group results by category
const groupedResults = computed(() => {
  const groups: { category: EntityCategory; label: string; items: FzfResult[] }[] = [];
  const categoryOrder: EntityCategory[] = ["session", "agent", "memory", "pr", "git", "command"];
  const categoryLabels: Record<EntityCategory, string> = {
    session: "Sessions",
    agent: "Agents",
    memory: "Memories",
    pr: "Pull Requests",
    git: "Git Events",
    command: "Commands",
  };

  for (const cat of categoryOrder) {
    const items = props.results.filter((r) => r.category === cat);
    if (items.length > 0) {
      groups.push({ category: cat, label: categoryLabels[cat], items });
    }
  }
  return groups;
});

// Flat list for keyboard navigation
const flatResults = computed(() => props.results);

// Keyboard navigation
function handleKeydown(e: KeyboardEvent) {
  if (e.key === "ArrowDown") {
    e.preventDefault();
    selectedIndex.value = Math.min(selectedIndex.value + 1, flatResults.value.length - 1);
    scrollToSelected();
  } else if (e.key === "ArrowUp") {
    e.preventDefault();
    selectedIndex.value = Math.max(selectedIndex.value - 1, 0);
    scrollToSelected();
  } else if (e.key === "Enter" && flatResults.value.length > 0) {
    e.preventDefault();
    emit("select", flatResults.value[selectedIndex.value]);
  } else if (e.key === "Tab") {
    e.preventDefault();
    // Jump to next category
    let currentCat = flatResults.value[selectedIndex.value]?.category;
    for (let i = selectedIndex.value + 1; i < flatResults.value.length; i++) {
      if (flatResults.value[i].category !== currentCat) {
        selectedIndex.value = i;
        scrollToSelected();
        return;
      }
    }
    // Wrap to start
    selectedIndex.value = 0;
    scrollToSelected();
  }
}

function scrollToSelected() {
  const el = document.querySelector(`[data-fzf-index="${selectedIndex.value}"]`);
  el?.scrollIntoView({ block: "nearest" });
}

// Expose for parent to wire up
defineExpose({ handleKeydown });

// Track global index for each result
function getGlobalIndex(result: FzfResult): number {
  return flatResults.value.indexOf(result);
}

// Category icons
const categoryIcons: Record<EntityCategory, string> = {
  session: "M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z",
  agent: "M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z",
  memory: "M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4",
  pr: "M7 8h10M7 12h4m1 8l-4-4H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-3l-4 4z",
  git: "M13 10V3L4 14h7v7l9-11h-7z",
  command: "M9 5l7 7-7 7",
};

// Category badge colors
const categoryColors: Record<EntityCategory, string> = {
  session: "text-blue-400",
  agent: "text-green-400",
  memory: "text-teal-400",
  pr: "text-amber-400",
  git: "text-surface-400",
  command: "text-purple-400",
};
</script>

<template>
  <div class="flex-1 overflow-y-auto" @keydown="handleKeydown">
    <!-- Empty + no query: show recents -->
    <div v-if="results.length === 0 && !query && recents.length > 0" class="px-4 py-3">
      <div class="text-xs font-semibold text-surface-600 uppercase tracking-wider mb-2">Recent</div>
      <ul class="space-y-0.5">
        <li
          v-for="(recent, i) in recents"
          :key="i"
          class="flex items-center gap-3 px-3 py-2 rounded-lg text-sm cursor-pointer hover:bg-surface-800 transition-colors"
          :class="categoryColors[recent.category]"
          @click="$emit('select', { ...recent, sublabel: '', score: 1, action: () => {} } as FzfResult)"
        >
          <svg class="w-4 h-4 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <span class="text-surface-300">{{ recent.label }}</span>
          <span class="text-xs text-surface-600 ml-auto">{{ recent.category }}</span>
        </li>
      </ul>
    </div>

    <!-- Empty + has query: no results -->
    <div v-else-if="results.length === 0 && query && !isSearching" class="px-4 py-8 text-center">
      <p class="text-sm text-surface-500">No results for "{{ query }}"</p>
      <p class="text-xs text-surface-600 mt-1">Try a different search or use prefix filters: s: a: m: p: g: &gt;</p>
    </div>

    <!-- Results grouped by category -->
    <div v-else class="py-1">
      <div v-for="group in groupedResults" :key="group.category" class="mb-1">
        <!-- Category header -->
        <div class="px-4 py-1.5 text-xs font-semibold text-surface-600 uppercase tracking-wider sticky top-0 bg-surface-900/95 backdrop-blur-sm">
          {{ group.label }}
        </div>

        <!-- Items -->
        <ul>
          <li
            v-for="result in group.items"
            :key="result.id"
            :data-fzf-index="getGlobalIndex(result)"
            class="flex items-center gap-3 px-4 py-2 cursor-pointer transition-colors"
            :class="getGlobalIndex(result) === selectedIndex
              ? 'bg-teal-400/10 text-teal-300'
              : 'text-surface-300 hover:bg-surface-800'"
            @click="$emit('select', result)"
            @mouseenter="selectedIndex = getGlobalIndex(result)"
          >
            <!-- Category icon -->
            <svg
              class="w-4 h-4 flex-shrink-0"
              :class="categoryColors[result.category]"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              stroke-width="1.5"
            >
              <path stroke-linecap="round" stroke-linejoin="round" :d="categoryIcons[result.category]" />
            </svg>

            <!-- Label + sublabel -->
            <div class="flex-1 min-w-0">
              <div class="text-sm truncate">{{ result.label }}</div>
              <div v-if="result.sublabel" class="text-xs text-surface-600 truncate">{{ result.sublabel }}</div>
            </div>

            <!-- Action hint -->
            <span class="flex-shrink-0 text-xs text-surface-600">
              {{ result.category === "command" ? "run" : result.category === "pr" ? "open" : "go" }}
            </span>
          </li>
        </ul>
      </div>
    </div>

    <!-- Loading indicator for async results -->
    <div v-if="isSearching" class="flex items-center gap-2 px-4 py-2 text-xs text-surface-500">
      <svg class="w-3 h-3 animate-spin" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
      </svg>
      Searching memories...
    </div>
  </div>
</template>
