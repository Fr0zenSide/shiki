<script setup lang="ts">
import { ref, nextTick, watch } from "vue";
import type { SearchMode } from "@/composables/useFzfSearch";

const props = defineProps<{
  mode: SearchMode;
  placeholder: string;
  isSearching: boolean;
}>();

const emit = defineEmits<{
  search: [query: string];
}>();

const input = ref<HTMLInputElement | null>(null);
const inputValue = ref("");

// Auto-focus on mount
watch(
  () => input.value,
  (el) => {
    if (el) nextTick(() => el.focus());
  },
  { immediate: true },
);

function handleInput() {
  emit("search", inputValue.value);
}

const modeBadges: Record<SearchMode, { label: string; color: string } | null> = {
  all: null,
  session: { label: "Sessions", color: "bg-blue-400/15 text-blue-400" },
  agent: { label: "Agents", color: "bg-green-400/15 text-green-400" },
  alias: { label: "Aliases", color: "bg-pink-400/15 text-pink-400" },
  memory: { label: "Memory", color: "bg-teal-400/15 text-teal-400" },
  pr: { label: "PRs", color: "bg-amber-400/15 text-amber-400" },
  git: { label: "Git", color: "bg-surface-700 text-surface-300" },
  command: { label: "Commands", color: "bg-purple-400/15 text-purple-400" },
};
</script>

<template>
  <div class="flex items-center gap-3 px-4 py-3 border-b border-surface-800">
    <!-- Search icon -->
    <svg
      class="w-5 h-5 flex-shrink-0"
      :class="isSearching ? 'text-teal-400 animate-pulse' : 'text-surface-500'"
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      stroke-width="2"
    >
      <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
    </svg>

    <!-- Mode badge -->
    <span
      v-if="modeBadges[props.mode]"
      class="flex-shrink-0 px-2 py-0.5 rounded-full text-xs font-medium"
      :class="modeBadges[props.mode]!.color"
    >
      {{ modeBadges[props.mode]!.label }}
    </span>

    <!-- Input -->
    <input
      ref="input"
      v-model="inputValue"
      type="text"
      :placeholder="props.placeholder"
      class="flex-1 bg-transparent text-sm text-surface-100 placeholder-surface-600 outline-none"
      @input="handleInput"
    />

    <!-- Loading spinner -->
    <div v-if="isSearching" class="flex-shrink-0">
      <svg class="w-4 h-4 animate-spin text-teal-400" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
      </svg>
    </div>
  </div>
</template>
