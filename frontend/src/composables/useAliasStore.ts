import { defineStore } from "pinia";
import { ref, computed } from "vue";
import { useAgencyStore } from "./useAgencyStore";
import type { AgentAlias, Agent } from "@/types";

const STORAGE_KEY = "acc-aliases";

function loadAliases(): AgentAlias[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

function persistAliases(aliases: AgentAlias[]) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(aliases));
}

export const useAliasStore = defineStore("alias", () => {
  const aliases = ref<AgentAlias[]>(loadAliases());

  // Get aliases relevant to current project (project-specific + global)
  const activeAliases = computed(() => {
    const store = useAgencyStore();
    const projectId = store.selectedProjectId;
    return aliases.value.filter(
      (a) => a.projectId === null || a.projectId === projectId,
    );
  });

  function createAlias(name: string, description: string, memberIds: string[], projectId: string | null): AgentAlias {
    const alias: AgentAlias = {
      id: crypto.randomUUID(),
      name: name.toLowerCase().trim(),
      description,
      memberIds,
      projectId,
      createdAt: new Date().toISOString(),
    };
    aliases.value.push(alias);
    persistAliases(aliases.value);
    return alias;
  }

  function updateAlias(id: string, updates: Partial<Pick<AgentAlias, "name" | "description" | "memberIds" | "projectId">>) {
    const idx = aliases.value.findIndex((a) => a.id === id);
    if (idx === -1) return;
    const alias = aliases.value[idx];
    if (updates.name !== undefined) alias.name = updates.name.toLowerCase().trim();
    if (updates.description !== undefined) alias.description = updates.description;
    if (updates.memberIds !== undefined) alias.memberIds = updates.memberIds;
    if (updates.projectId !== undefined) alias.projectId = updates.projectId;
    persistAliases(aliases.value);
  }

  function deleteAlias(id: string) {
    aliases.value = aliases.value.filter((a) => a.id !== id);
    persistAliases(aliases.value);
  }

  function addMember(aliasId: string, agentId: string) {
    const alias = aliases.value.find((a) => a.id === aliasId);
    if (!alias) return;
    if (!alias.memberIds.includes(agentId)) {
      alias.memberIds.push(agentId);
      persistAliases(aliases.value);
    }
  }

  function removeMember(aliasId: string, agentId: string) {
    const alias = aliases.value.find((a) => a.id === aliasId);
    if (!alias) return;
    alias.memberIds = alias.memberIds.filter((id) => id !== agentId);
    persistAliases(aliases.value);
  }

  function findByName(name: string): AgentAlias | undefined {
    const normalized = name.toLowerCase().replace(/^@/, "").trim();
    return activeAliases.value.find((a) => a.name === normalized);
  }

  // Resolve alias to actual agent objects
  function resolveMembers(alias: AgentAlias): Agent[] {
    const store = useAgencyStore();
    return alias.memberIds
      .map((id) => store.agents.find((a) => a.id === id))
      .filter((a): a is Agent => a != null);
  }

  return {
    aliases,
    activeAliases,
    createAlias,
    updateAlias,
    deleteAlias,
    addMember,
    removeMember,
    findByName,
    resolveMembers,
  };
});
