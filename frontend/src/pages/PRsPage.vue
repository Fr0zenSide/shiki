<script setup lang="ts">
import { onMounted, computed } from "vue";
import { useAgencyStore } from "@/composables/useAgencyStore";

const store = useAgencyStore();

onMounted(async () => {
  await store.fetchGitEvents();
});

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function getPrUrl(event: typeof store.gitEvents.value[0]): string | null {
  const md = event.metadata as Record<string, unknown>;
  if (typeof md.prUrl === "string") return md.prUrl;
  return null;
}

function getBaseBranch(event: typeof store.gitEvents.value[0]): string | null {
  const md = event.metadata as Record<string, unknown>;
  if (typeof md.baseBranch === "string") return md.baseBranch;
  return null;
}

const eventTypeColors: Record<string, string> = {
  pr_created: "bg-green-400/15 text-green-400",
  commit: "bg-blue-400/15 text-blue-400",
  push: "bg-teal-400/15 text-teal-400",
  branch_created: "bg-amber-400/15 text-amber-400",
  branch_deleted: "bg-red-400/15 text-red-400",
};

const prEvents = computed(() =>
  store.gitEvents.filter((e) => e.event_type === "pr_created"),
);

const otherEvents = computed(() =>
  store.gitEvents.filter((e) => e.event_type !== "pr_created"),
);
</script>

<template>
  <div class="p-6 space-y-6 max-w-7xl mx-auto">
    <!-- Header -->
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-semibold text-surface-100">Pull Requests & Git</h1>
        <p class="text-sm text-surface-500 mt-1">
          {{ prEvents.length }} PRs &middot; {{ store.gitEvents.length }} total git events
        </p>
      </div>
      <button
        class="px-3 py-1.5 rounded-lg bg-surface-800 text-surface-300 text-sm hover:bg-surface-700 transition-colors"
        @click="store.fetchGitEvents()"
      >
        Refresh
      </button>
    </div>

    <!-- PR cards -->
    <section>
      <h2 class="text-xs font-medium uppercase tracking-wider text-surface-500 mb-3">Pull Requests</h2>

      <div v-if="prEvents.length === 0" class="bg-surface-900 border border-surface-800 rounded-xl p-8 text-center">
        <div class="text-surface-600 space-y-2">
          <div class="text-4xl">--</div>
          <p class="text-sm">No pull requests tracked yet.</p>
          <p class="text-xs text-surface-700">
            PRs are reported via POST /api/pr-created
          </p>
        </div>
      </div>

      <div v-else class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div
          v-for="(pr, idx) in prEvents"
          :key="idx"
          class="bg-surface-900 border border-surface-800 rounded-xl p-4 hover:border-green-400/30 transition-colors"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 mb-1">
                <span class="px-1.5 py-0.5 rounded text-xs font-medium bg-green-400/15 text-green-400">
                  PR
                </span>
                <span class="text-xs text-surface-600">{{ formatDate(pr.occurred_at) }}</span>
              </div>
              <h3 class="text-sm font-medium text-surface-200 truncate">
                {{ pr.commit_msg ?? "Untitled PR" }}
              </h3>
              <div class="flex items-center gap-2 mt-2 text-xs text-surface-500">
                <span v-if="pr.ref" class="font-mono bg-surface-800 px-2 py-0.5 rounded">
                  {{ pr.ref }}
                </span>
                <span v-if="getBaseBranch(pr)">
                  into
                  <span class="font-mono bg-surface-800 px-2 py-0.5 rounded">{{ getBaseBranch(pr) }}</span>
                </span>
              </div>
            </div>
            <a
              v-if="getPrUrl(pr)"
              :href="getPrUrl(pr)!"
              target="_blank"
              rel="noopener noreferrer"
              class="flex-shrink-0 px-3 py-1.5 rounded-lg bg-surface-800 text-teal-400 text-xs hover:bg-surface-700 transition-colors"
            >
              View on GitHub
            </a>
          </div>
          <div v-if="pr.additions != null || pr.deletions != null" class="flex items-center gap-3 mt-3 text-xs">
            <span v-if="pr.additions" class="text-green-400">+{{ pr.additions }}</span>
            <span v-if="pr.deletions" class="text-red-400">-{{ pr.deletions }}</span>
            <span v-if="pr.files_changed" class="text-surface-500">{{ pr.files_changed }} files</span>
          </div>
        </div>
      </div>
    </section>

    <!-- Other git events timeline -->
    <section v-if="otherEvents.length > 0" class="bg-surface-900 border border-surface-800 rounded-xl">
      <div class="px-5 py-4 border-b border-surface-800">
        <h2 class="text-sm font-semibold text-surface-200">Other Git Activity</h2>
      </div>
      <div class="p-4 max-h-96 overflow-y-auto">
        <div class="space-y-2">
          <div
            v-for="(event, idx) in otherEvents.slice(0, 30)"
            :key="idx"
            class="flex items-start gap-3 text-sm"
          >
            <span class="text-xs text-surface-600 font-mono flex-shrink-0 mt-0.5 w-20">
              {{ formatDate(event.occurred_at).split(",")[0] }}
            </span>
            <span
              class="flex-shrink-0 px-1.5 py-0.5 rounded text-xs font-medium"
              :class="eventTypeColors[event.event_type] ?? 'bg-surface-700 text-surface-400'"
            >
              {{ event.event_type }}
            </span>
            <span v-if="event.ref" class="text-surface-400 font-mono text-xs">
              {{ event.ref }}
            </span>
            <span v-if="event.commit_msg" class="text-surface-400 truncate text-xs">
              {{ event.commit_msg }}
            </span>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
