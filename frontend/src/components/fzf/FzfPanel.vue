<script setup lang="ts">
import { onMounted, onUnmounted, watch } from "vue";
import { fzfOpen, pushEscapeHandler, popEscapeHandler } from "@/composables/useKeyboardShortcuts";
import { aliasOpen } from "@/composables/usePanelState";
import { useFzfSearch, type FzfResult } from "@/composables/useFzfSearch";
import FzfSearchBar from "./FzfSearchBar.vue";
import FzfResultList from "./FzfResultList.vue";
import AliasPanel from "./AliasPanel.vue";

const fzf = useFzfSearch();

function close() {
  fzfOpen.value = false;
  aliasOpen.value = false;
  fzf.clear();
}

function closeAlias() {
  aliasOpen.value = false;
}

watch(fzfOpen, (open) => {
  if (open) {
    pushEscapeHandler("fzf-panel", () => {
      if (aliasOpen.value) {
        aliasOpen.value = false;
      } else {
        close();
      }
    });
    // Show recents when opening with empty search
    fzf.search("");
  } else {
    popEscapeHandler("fzf-panel");
    aliasOpen.value = false;
  }
});

onMounted(() => {
  if (fzfOpen.value) {
    pushEscapeHandler("fzf-panel", () => {
      if (aliasOpen.value) {
        aliasOpen.value = false;
      } else {
        close();
      }
    });
  }
});

onUnmounted(() => {
  popEscapeHandler("fzf-panel");
});

function handleSelect(result: FzfResult) {
  fzf.selectResult(result);
  // Don't close FZF if we're opening alias panel
  if (result.id === "cmd-alias" || result.category === "alias") return;
  close();
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
      <div v-if="fzfOpen" class="fixed inset-0 z-[80] flex justify-center pt-[12vh]">
        <!-- Backdrop -->
        <div class="absolute inset-0 bg-surface-950/60" @click="close" />

        <!-- Panel -->
        <Transition
          enter-active-class="transition duration-150 ease-out"
          enter-from-class="-translate-y-4 opacity-0"
          enter-to-class="translate-y-0 opacity-100"
          leave-active-class="transition duration-100 ease-in"
          leave-from-class="translate-y-0 opacity-100"
          leave-to-class="-translate-y-4 opacity-0"
        >
          <div
            v-if="fzfOpen"
            class="relative w-full max-w-2xl mx-4 bg-surface-900 border border-surface-700 rounded-2xl shadow-2xl overflow-hidden flex flex-col"
            style="max-height: 60vh"
          >
            <!-- Alias panel (replaces search when open) -->
            <template v-if="aliasOpen">
              <AliasPanel @close="closeAlias" />
            </template>

            <!-- Normal FZF search -->
            <template v-else>
              <!-- Search bar -->
              <FzfSearchBar
                :mode="fzf.mode.value"
                :placeholder="fzf.placeholder.value"
                :is-searching="fzf.isSearching.value"
                @search="fzf.search"
              />

              <!-- Results -->
              <FzfResultList
                :results="fzf.results.value"
                :recents="fzf.recents.value"
                :query="fzf.query.value"
                :is-searching="fzf.isSearching.value"
                @select="handleSelect"
              />

              <!-- Footer hints -->
              <div class="flex items-center gap-4 px-4 py-2 border-t border-surface-800 text-xs text-surface-600">
                <span>
                  <kbd class="px-1 py-0.5 rounded bg-surface-800 text-surface-500 font-mono">&uarr;&darr;</kbd>
                  navigate
                </span>
                <span>
                  <kbd class="px-1 py-0.5 rounded bg-surface-800 text-surface-500 font-mono">Enter</kbd>
                  select
                </span>
                <span>
                  <kbd class="px-1 py-0.5 rounded bg-surface-800 text-surface-500 font-mono">Tab</kbd>
                  cycle groups
                </span>
                <span>
                  <kbd class="px-1 py-0.5 rounded bg-surface-800 text-surface-500 font-mono">@:</kbd>
                  aliases
                </span>
                <span>
                  <kbd class="px-1 py-0.5 rounded bg-surface-800 text-surface-500 font-mono">Esc</kbd>
                  close
                </span>
              </div>
            </template>
          </div>
        </Transition>
      </div>
    </Transition>
  </Teleport>
</template>
