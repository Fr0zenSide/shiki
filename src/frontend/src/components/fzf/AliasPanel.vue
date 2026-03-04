<script setup lang="ts">
import { ref, computed } from "vue";
import { useAliasStore } from "@/composables/useAliasStore";
import { useAgencyStore } from "@/composables/useAgencyStore";
import type { AgentAlias } from "@/types";

const emit = defineEmits<{
  close: [];
}>();

const aliasStore = useAliasStore();
const agencyStore = useAgencyStore();

const editingAliasId = ref<string | null>(null);
const newAliasName = ref("");
const newAliasDesc = ref("");
const isCreating = ref(false);

// Agents not already in the currently-editing alias
const availableAgents = computed(() => {
  if (!editingAliasId.value) return agencyStore.agents;
  const alias = aliasStore.aliases.find((a) => a.id === editingAliasId.value);
  if (!alias) return agencyStore.agents;
  const memberSet = new Set(alias.memberIds);
  return agencyStore.agents.filter((a) => !memberSet.has(a.id));
});

const statusDotColor: Record<string, string> = {
  spawned: "bg-blue-400",
  running: "bg-green-400",
  completed: "bg-surface-500",
  failed: "bg-red-400",
  cancelled: "bg-surface-600",
};

function startCreating() {
  isCreating.value = true;
  newAliasName.value = "";
  newAliasDesc.value = "";
}

function cancelCreating() {
  isCreating.value = false;
  newAliasName.value = "";
  newAliasDesc.value = "";
}

function createAlias() {
  const name = newAliasName.value.trim();
  if (!name) return;
  const alias = aliasStore.createAlias(
    name,
    newAliasDesc.value.trim(),
    [],
    agencyStore.selectedProjectId,
  );
  isCreating.value = false;
  newAliasName.value = "";
  newAliasDesc.value = "";
  editingAliasId.value = alias.id;
}

function toggleEditing(alias: AgentAlias) {
  editingAliasId.value = editingAliasId.value === alias.id ? null : alias.id;
}

function removeMember(aliasId: string, agentId: string) {
  aliasStore.removeMember(aliasId, agentId);
}

function addMember(agentId: string) {
  if (!editingAliasId.value) return;
  aliasStore.addMember(editingAliasId.value, agentId);
}

function deleteAlias(id: string) {
  aliasStore.deleteAlias(id);
  if (editingAliasId.value === id) editingAliasId.value = null;
}

function getAgentInitial(handle: string): string {
  return handle.charAt(0).toUpperCase();
}
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden">
    <!-- Header -->
    <div class="flex items-center justify-between px-4 py-3 border-b border-surface-800">
      <div class="flex items-center gap-2">
        <button
          class="w-6 h-6 rounded-lg bg-surface-800 text-surface-400 hover:text-surface-200 flex items-center justify-center transition-colors"
          @click="emit('close')"
        >
          <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7"/>
          </svg>
        </button>
        <h2 class="text-sm font-semibold text-surface-200">Aliases</h2>
      </div>
      <button
        v-if="!isCreating"
        class="px-2.5 py-1 rounded-lg bg-teal-400/10 text-teal-400 text-xs font-medium hover:bg-teal-400/20 transition-colors"
        @click="startCreating"
      >
        + New Alias
      </button>
    </div>

    <div class="flex-1 overflow-y-auto">
      <!-- Create form -->
      <div v-if="isCreating" class="px-4 py-3 border-b border-surface-800 bg-surface-850">
        <div class="space-y-2">
          <input
            v-model="newAliasName"
            class="w-full bg-surface-800 border border-surface-700 rounded-lg px-3 py-1.5 text-sm text-surface-200 placeholder-surface-600 focus:outline-none focus:border-teal-400/50"
            placeholder="Alias name (e.g. shi team)"
            @keydown.enter="createAlias"
            @keydown.escape="cancelCreating"
          />
          <input
            v-model="newAliasDesc"
            class="w-full bg-surface-800 border border-surface-700 rounded-lg px-3 py-1.5 text-sm text-surface-200 placeholder-surface-600 focus:outline-none focus:border-teal-400/50"
            placeholder="Description (optional)"
            @keydown.enter="createAlias"
            @keydown.escape="cancelCreating"
          />
          <div class="flex gap-2">
            <button
              class="px-3 py-1 rounded-lg bg-teal-400 text-surface-900 text-xs font-medium hover:bg-teal-300 transition-colors disabled:opacity-50"
              :disabled="!newAliasName.trim()"
              @click="createAlias"
            >
              Create
            </button>
            <button
              class="px-3 py-1 rounded-lg bg-surface-800 text-surface-400 text-xs hover:text-surface-200 transition-colors"
              @click="cancelCreating"
            >
              Cancel
            </button>
          </div>
        </div>
      </div>

      <!-- Alias list -->
      <div v-if="aliasStore.activeAliases.length === 0 && !isCreating" class="px-4 py-8 text-center">
        <p class="text-sm text-surface-600">No aliases yet</p>
        <p class="text-xs text-surface-700 mt-1">Create one to group agents together</p>
      </div>

      <div v-for="alias in aliasStore.activeAliases" :key="alias.id" class="border-b border-surface-800/50">
        <!-- Alias header -->
        <div
          class="flex items-center justify-between px-4 py-2.5 cursor-pointer hover:bg-surface-850 transition-colors"
          @click="toggleEditing(alias)"
        >
          <div class="flex items-center gap-2 min-w-0">
            <span class="text-teal-400 text-sm font-medium">@{{ alias.name }}</span>
            <span class="text-xs text-surface-600">({{ alias.memberIds.length }})</span>
            <span v-if="alias.description" class="text-xs text-surface-500 truncate">
              — {{ alias.description }}
            </span>
          </div>
          <div class="flex items-center gap-1.5">
            <button
              class="w-5 h-5 rounded text-surface-600 hover:text-red-400 flex items-center justify-center transition-colors"
              title="Delete alias"
              @click.stop="deleteAlias(alias.id)"
            >
              <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
              </svg>
            </button>
            <svg
              class="w-3 h-3 text-surface-600 transition-transform"
              :class="editingAliasId === alias.id ? 'rotate-180' : ''"
              fill="currentColor" viewBox="0 0 16 16"
            >
              <path fill-rule="evenodd" d="M1.646 4.646a.5.5 0 01.708 0L8 10.293l5.646-5.647a.5.5 0 01.708.708l-6 6a.5.5 0 01-.708 0l-6-6a.5.5 0 010-.708z"/>
            </svg>
          </div>
        </div>

        <!-- Members (expanded) -->
        <div v-if="editingAliasId === alias.id" class="px-4 pb-3">
          <!-- Current members -->
          <div class="space-y-1 mb-3">
            <div
              v-for="agent in aliasStore.resolveMembers(alias)"
              :key="agent.id"
              class="flex items-center gap-2 px-2 py-1.5 rounded-lg bg-surface-850 group"
            >
              <!-- Avatar -->
              <div class="w-6 h-6 rounded-full bg-surface-700 flex items-center justify-center text-xs font-bold text-surface-300 flex-shrink-0">
                {{ getAgentInitial(agent.handle) }}
              </div>
              <!-- Status dot -->
              <span class="w-2 h-2 rounded-full flex-shrink-0" :class="statusDotColor[agent.status] ?? 'bg-surface-600'" />
              <!-- Info -->
              <span class="text-sm text-surface-200 flex-1 truncate">{{ agent.handle }}</span>
              <span class="text-xs text-surface-600 flex-shrink-0">{{ agent.model.split('/').pop() }}</span>
              <!-- Remove button -->
              <button
                class="w-5 h-5 rounded text-surface-600 hover:text-red-400 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-all"
                title="Remove from alias"
                @click="removeMember(alias.id, agent.id)"
              >
                <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12"/>
                </svg>
              </button>
            </div>
            <div v-if="alias.memberIds.length === 0" class="text-xs text-surface-600 italic py-1 px-2">
              No members — add agents below
            </div>
          </div>

          <!-- Available agents grid -->
          <div v-if="availableAgents.length > 0">
            <div class="text-xs text-surface-500 uppercase tracking-wider mb-2">Add agents</div>
            <div class="grid grid-cols-3 sm:grid-cols-4 gap-1.5">
              <button
                v-for="agent in availableAgents"
                :key="agent.id"
                class="flex flex-col items-center gap-1 px-2 py-2 rounded-lg bg-surface-850 border border-surface-800 hover:border-teal-400/30 hover:bg-teal-400/5 transition-colors"
                @click="addMember(agent.id)"
              >
                <div class="w-7 h-7 rounded-full bg-surface-700 flex items-center justify-center text-xs font-bold text-surface-300">
                  {{ getAgentInitial(agent.handle) }}
                </div>
                <span class="text-xs text-surface-300 truncate w-full text-center">{{ agent.handle }}</span>
                <span class="text-[10px] text-surface-600 truncate w-full text-center">{{ agent.role || agent.model.split('/').pop() }}</span>
              </button>
            </div>
          </div>
          <div v-else-if="agencyStore.agents.length === 0" class="text-xs text-surface-600 italic">
            No agents available — agents appear when sessions are active
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
