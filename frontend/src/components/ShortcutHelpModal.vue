<script setup lang="ts">
import { computed, onMounted, onUnmounted } from "vue";
import { getShortcuts, helpOpen, pushEscapeHandler, popEscapeHandler } from "@/composables/useKeyboardShortcuts";

function close() {
  helpOpen.value = false;
}

onMounted(() => {
  pushEscapeHandler("help-modal", close);
});

onUnmounted(() => {
  popEscapeHandler("help-modal");
});

const groupedShortcuts = computed(() => {
  const all = getShortcuts();
  const groups: Record<string, typeof all> = {};
  for (const s of all) {
    if (!groups[s.group]) groups[s.group] = [];
    groups[s.group].push(s);
  }
  return groups;
});

function formatKeys(keys: string): string[] {
  return keys
    .replace(/Cmd/gi, "\u2318")
    .replace(/Shift/gi, "\u21E7")
    .replace(/Alt/gi, "\u2325")
    .replace(/Ctrl/gi, "\u2303")
    .split("+");
}
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition duration-150 ease-out"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="transition duration-100 ease-in"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div v-if="helpOpen" class="fixed inset-0 z-[90] flex items-center justify-center">
        <!-- Backdrop -->
        <div class="absolute inset-0 bg-surface-950/70" @click="close" />

        <!-- Modal -->
        <div class="relative bg-surface-900 border border-surface-700 rounded-2xl shadow-2xl w-full max-w-lg mx-4 overflow-hidden">
          <!-- Header -->
          <div class="flex items-center justify-between px-6 py-4 border-b border-surface-800">
            <h2 class="text-base font-semibold text-surface-100">Keyboard Shortcuts</h2>
            <button
              class="text-surface-500 hover:text-surface-300 transition-colors"
              @click="close"
            >
              <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <!-- Content -->
          <div class="px-6 py-4 max-h-[60vh] overflow-y-auto space-y-5">
            <div v-for="(items, group) in groupedShortcuts" :key="group">
              <h3 class="text-xs font-semibold text-surface-500 uppercase tracking-wider mb-2">
                {{ group }}
              </h3>
              <ul class="space-y-1.5">
                <li
                  v-for="shortcut in items"
                  :key="shortcut.keys"
                  class="flex items-center justify-between py-1"
                >
                  <span class="text-sm text-surface-300">{{ shortcut.label }}</span>
                  <div class="flex items-center gap-1">
                    <kbd
                      v-for="(part, i) in formatKeys(shortcut.keys)"
                      :key="i"
                      class="px-1.5 py-0.5 rounded bg-surface-800 border border-surface-700 text-xs font-mono text-surface-400 min-w-[1.5rem] text-center"
                    >
                      {{ part }}
                    </kbd>
                  </div>
                </li>
              </ul>
            </div>
          </div>

          <!-- Footer -->
          <div class="px-6 py-3 border-t border-surface-800 text-xs text-surface-600">
            Press <kbd class="px-1 py-0.5 rounded bg-surface-800 text-surface-400 font-mono">Esc</kbd> to close
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
