<script setup lang="ts">
import { ref, onMounted, computed } from "vue";
import { useAgencyStore } from "@/composables/useAgencyStore";
import { useApi } from "@/composables/useApi";
import type { MemorySearchResult, MemorySource } from "@/types";

const store = useAgencyStore();
const api = useApi();

const searchQuery = ref("");
const searchResults = ref<MemorySearchResult[]>([]);
const isSearching = ref(false);
const showSearch = ref(false);
const searchError = ref<string | null>(null);

// Sources popover state
const showSources = ref(false);
const sources = ref<MemorySource[]>([]);
const sourcesFilter = ref("");
const loadingSources = ref(false);

onMounted(async () => {
  if (!store.selectedProjectId) {
    await store.init();
  }
  await store.fetchMemories();
});

async function doSearch() {
  const query = searchQuery.value.trim();
  searchError.value = null;

  if (!query) return;

  if (!store.selectedProjectId) {
    searchError.value = "No project selected. Select a project first.";
    return;
  }

  isSearching.value = true;
  try {
    searchResults.value = await api.searchMemories(query, store.selectedProjectId, 20, 0.3);
    showSearch.value = true;
    if (searchResults.value.length === 0) {
      searchError.value = "No matching memories found. Try a broader query.";
    }
  } catch (err) {
    searchResults.value = [];
    searchError.value = err instanceof Error ? err.message : "Search failed — check that the embedding server is running.";
  } finally {
    isSearching.value = false;
  }
}

function clearSearch() {
  searchQuery.value = "";
  searchResults.value = [];
  showSearch.value = false;
  searchError.value = null;
}

async function toggleSources() {
  showSources.value = !showSources.value;
  if (showSources.value && sources.value.length === 0) {
    loadingSources.value = true;
    try {
      sources.value = await api.getMemorySources(store.selectedProjectId ?? undefined);
    } catch {
      sources.value = [];
    } finally {
      loadingSources.value = false;
    }
  }
}

const filteredSources = computed(() => {
  const filter = sourcesFilter.value.toLowerCase().trim();
  if (!filter) return sources.value;
  return sources.value.filter((s) =>
    s.source_file.toLowerCase().includes(filter),
  );
});

function shortPath(fullPath: string): string {
  // Shorten long paths for display
  const parts = fullPath.split("/");
  if (parts.length <= 3) return fullPath;
  return ".../" + parts.slice(-3).join("/");
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function formatDateShort(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
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
  roadmap: "bg-purple-400/15 text-purple-400",
  process: "bg-indigo-400/15 text-indigo-400",
  vision: "bg-pink-400/15 text-pink-400",
  commands: "bg-cyan-400/15 text-cyan-400",
  environment: "bg-emerald-400/15 text-emerald-400",
};

const groupedMemories = computed(() => {
  const groups: Record<string, (typeof store.memories)[number][]> = {};
  for (const m of store.memories) {
    const cat = m.category || "general";
    if (!groups[cat]) groups[cat] = [];
    groups[cat].push(m);
  }
  return groups;
});

const categoryCount = computed(() => Object.keys(groupedMemories.value).length);

const totalImportance = computed(() => {
  if (store.memories.length === 0) return 0;
  const sum = store.memories.reduce((acc, m) => acc + (m.importance ?? 1), 0);
  return (sum / store.memories.length).toFixed(1);
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
      <div class="flex items-center gap-2 relative">
        <!-- Sources popover toggle -->
        <button
          class="px-3 py-1.5 rounded-lg text-sm transition-colors"
          :class="showSources
            ? 'bg-teal-400/15 text-teal-400 border border-teal-400/30'
            : 'bg-surface-800 text-surface-300 hover:bg-surface-700'"
          @click="toggleSources"
        >
          Sources
          <span v-if="sources.length" class="ml-1 text-xs opacity-60">({{ sources.length }})</span>
        </button>
        <!-- Refresh -->
        <button
          class="px-3 py-1.5 rounded-lg bg-surface-800 text-surface-300 text-sm hover:bg-surface-700 transition-colors"
          @click="store.fetchMemories()"
        >
          Refresh
        </button>

        <!-- Sources popover -->
        <Transition name="fade">
          <div
            v-if="showSources"
            class="absolute right-0 top-full mt-2 w-[480px] z-50 bg-surface-900 border border-surface-800 rounded-xl shadow-2xl overflow-hidden"
          >
            <div class="px-4 py-3 border-b border-surface-800">
              <div class="flex items-center justify-between mb-2">
                <h3 class="text-sm font-semibold text-surface-200">Backed-up Sources</h3>
                <span class="text-xs text-surface-600">{{ filteredSources.length }} files</span>
              </div>
              <input
                v-model="sourcesFilter"
                type="text"
                placeholder="Filter files..."
                class="w-full bg-surface-850 border border-surface-700 rounded-lg px-3 py-1.5 text-xs text-surface-200 placeholder-surface-600 focus:outline-none focus:border-teal-400/50"
              />
            </div>
            <div class="max-h-80 overflow-y-auto">
              <div v-if="loadingSources" class="p-4 text-center text-xs text-surface-600">
                Loading sources...
              </div>
              <div v-else-if="filteredSources.length === 0" class="p-4 text-center text-xs text-surface-600">
                No source files found.
              </div>
              <div v-else>
                <div
                  v-for="src in filteredSources"
                  :key="src.source_file"
                  class="px-4 py-2.5 border-b border-surface-800/50 hover:bg-surface-850 transition-colors"
                >
                  <div class="flex items-center justify-between">
                    <span class="text-xs text-surface-300 font-mono truncate max-w-[280px]" :title="src.source_file">
                      {{ shortPath(src.source_file) }}
                    </span>
                    <div class="flex items-center gap-2 shrink-0">
                      <span class="text-xs text-surface-600">
                        {{ src.chunk_count }} chunks
                      </span>
                    </div>
                  </div>
                  <div class="flex items-center gap-3 mt-1">
                    <span class="text-[10px] text-surface-600">
                      modified: <span class="text-surface-500">{{ formatDateShort(src.file_modified_at) }}</span>
                    </span>
                    <span class="text-[10px] text-surface-600">
                      backed up: <span class="text-teal-400/70">{{ formatDateShort(src.last_backed_up) }}</span>
                    </span>
                    <span class="text-[10px] text-amber-400/60 font-mono">
                      imp {{ src.avg_importance }}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </Transition>
      </div>
    </div>

    <!-- Search bar -->
    <div class="bg-surface-900 border border-surface-800 rounded-xl p-4">
      <div class="flex gap-3">
        <input
          v-model="searchQuery"
          type="text"
          placeholder="Ask anything about the project — architecture, decisions, roadmap..."
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
      <p v-if="searchError" class="mt-2 text-xs text-red-400">
        {{ searchError }}
      </p>
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

    <!-- Memory Status Footer -->
    <div class="bg-surface-900/60 border border-surface-800 rounded-xl px-5 py-3 flex items-center justify-between text-xs text-surface-500">
      <div class="flex items-center gap-4">
        <span>
          <span class="text-surface-300 font-medium">{{ store.memories.length }}</span> memories
        </span>
        <span>
          <span class="text-surface-300 font-medium">{{ categoryCount }}</span> categories
        </span>
        <span>
          avg importance <span class="text-amber-400 font-mono">{{ totalImportance }}</span>
        </span>
      </div>
      <div class="flex items-center gap-4">
        <span v-if="store.selectedProject" class="text-surface-600">
          project: <span class="text-surface-400">{{ store.selectedProject.name }}</span>
        </span>
        <span :class="store.isHealthy ? 'text-emerald-400' : 'text-red-400'">
          {{ store.isHealthy ? 'embeddings online' : 'embeddings offline' }}
        </span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.15s ease, transform 0.15s ease;
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
  transform: translateY(-4px);
}
</style>
