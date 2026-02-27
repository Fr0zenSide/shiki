<script setup lang="ts">
import { ref, onMounted, computed } from "vue";
import { useAgencyStore } from "@/composables/useAgencyStore";
import { useApi } from "@/composables/useApi";
import type { MemorySearchResult } from "@/types";

const store = useAgencyStore();
const api = useApi();

const searchQuery = ref("");
const searchResults = ref<MemorySearchResult[]>([]);
const isSearching = ref(false);
const showSearch = ref(false);

onMounted(async () => {
  await store.fetchMemories();
});

async function doSearch() {
  const query = searchQuery.value.trim();
  if (!query || !store.selectedProjectId) return;

  isSearching.value = true;
  try {
    searchResults.value = await api.searchMemories(query, store.selectedProjectId);
    showSearch.value = true;
  } catch {
    // Search may fail if Ollama is not running
    searchResults.value = [];
  } finally {
    isSearching.value = false;
  }
}

function clearSearch() {
  searchQuery.value = "";
  searchResults.value = [];
  showSearch.value = false;
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function truncate(text: string, maxLength = 300): string {
  if (text.length <= maxLength) return text;
  return text.slice(0, maxLength) + "...";
}

const categoryColors: Record<string, string> = {
  general: "bg-surface-700 text-surface-300",
  architecture: "bg-blue-400/15 text-blue-400",
  decision: "bg-amber-400/15 text-amber-400",
  bug: "bg-red-400/15 text-red-400",
  feature: "bg-green-400/15 text-green-400",
  context: "bg-teal-400/15 text-teal-400",
};

const groupedMemories = computed(() => {
  const groups: Record<string, typeof store.memories.value> = {};
  for (const m of store.memories) {
    const cat = m.category || "general";
    if (!groups[cat]) groups[cat] = [];
    groups[cat].push(m);
  }
  return groups;
});
</script>

<template>
  <div class="p-6 space-y-6 max-w-7xl mx-auto">
    <!-- Header -->
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-semibold text-surface-100">Memory</h1>
        <p class="text-sm text-surface-500 mt-1">
          {{ store.memories.length }} entries stored
          <template v-if="store.selectedProject"> for {{ store.selectedProject.name }}</template>
        </p>
      </div>
      <button
        class="px-3 py-1.5 rounded-lg bg-surface-800 text-surface-300 text-sm hover:bg-surface-700 transition-colors"
        @click="store.fetchMemories()"
      >
        Refresh
      </button>
    </div>

    <!-- Search bar -->
    <div class="bg-surface-900 border border-surface-800 rounded-xl p-4">
      <div class="flex gap-3">
        <input
          v-model="searchQuery"
          type="text"
          placeholder="Semantic search across memories (requires Ollama)..."
          class="flex-1 bg-surface-850 border border-surface-700 rounded-lg px-4 py-2.5 text-sm text-surface-200 placeholder-surface-600 focus:outline-none focus:border-teal-400/50 focus:ring-1 focus:ring-teal-400/20"
          @keydown.enter="doSearch"
        />
        <button
          class="px-4 py-2.5 rounded-lg bg-teal-400 text-surface-900 font-medium text-sm hover:bg-teal-300 transition-colors disabled:opacity-50"
          :disabled="!searchQuery.trim() || isSearching"
          @click="doSearch"
        >
          {{ isSearching ? "Searching..." : "Search" }}
        </button>
        <button
          v-if="showSearch"
          class="px-3 py-2.5 rounded-lg bg-surface-800 text-surface-400 text-sm hover:bg-surface-700 transition-colors"
          @click="clearSearch"
        >
          Clear
        </button>
      </div>
    </div>

    <!-- Search results -->
    <section v-if="showSearch" class="bg-surface-900 border border-teal-400/20 rounded-xl">
      <div class="px-5 py-4 border-b border-surface-800">
        <h2 class="text-sm font-semibold text-teal-400">
          Search Results ({{ searchResults.length }})
        </h2>
      </div>
      <div class="p-4">
        <div v-if="searchResults.length === 0" class="text-sm text-surface-600 italic py-4 text-center">
          No matching memories found. Try a different query or lower the similarity threshold.
        </div>
        <div class="space-y-3">
          <div
            v-for="result in searchResults"
            :key="result.id"
            class="bg-surface-850 border border-surface-800 rounded-lg p-4"
          >
            <div class="flex items-center gap-2 mb-2">
              <span
                class="text-xs px-1.5 py-0.5 rounded-full font-medium"
                :class="categoryColors[result.category] ?? categoryColors.general"
              >
                {{ result.category }}
              </span>
              <span class="text-xs text-teal-400 font-mono">
                {{ (result.similarity * 100).toFixed(1) }}% match
              </span>
              <span class="text-xs text-surface-600 ml-auto">
                {{ formatDate(result.createdAt) }}
              </span>
            </div>
            <p class="text-sm text-surface-300 whitespace-pre-wrap">{{ truncate(result.content) }}</p>
            <div v-if="result.fromAgent" class="text-xs text-surface-600 mt-2">
              From agent: {{ result.fromAgent }}
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- Memory entries by category -->
    <div v-if="!showSearch">
      <div v-if="store.memories.length === 0" class="bg-surface-900 border border-surface-800 rounded-xl p-8 text-center">
        <div class="text-surface-600 space-y-2">
          <div class="text-4xl">--</div>
          <p class="text-sm">No memories stored yet.</p>
          <p class="text-xs text-surface-700">
            Memories are created via POST /api/memories or POST /api/data-sync
          </p>
        </div>
      </div>

      <div v-else class="space-y-6">
        <section
          v-for="(memos, category) in groupedMemories"
          :key="category"
          class="bg-surface-900 border border-surface-800 rounded-xl"
        >
          <div class="px-5 py-4 border-b border-surface-800 flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span
                class="text-xs px-2 py-0.5 rounded-full font-medium"
                :class="categoryColors[category] ?? categoryColors.general"
              >
                {{ category }}
              </span>
              <h2 class="text-sm font-semibold text-surface-200">{{ memos.length }} entries</h2>
            </div>
          </div>
          <div class="p-4 space-y-3 max-h-96 overflow-y-auto">
            <div
              v-for="memory in memos"
              :key="memory.id"
              class="bg-surface-850 border border-surface-800 rounded-lg p-3"
            >
              <div class="flex items-center gap-2 mb-1.5">
                <span class="text-xs text-surface-600">{{ formatDate(memory.created_at) }}</span>
                <span v-if="memory.importance > 1" class="text-xs text-amber-400 font-mono">
                  importance: {{ memory.importance.toFixed(1) }}
                </span>
              </div>
              <p class="text-sm text-surface-300 whitespace-pre-wrap">{{ truncate(memory.content, 500) }}</p>
            </div>
          </div>
        </section>
      </div>
    </div>
  </div>
</template>
