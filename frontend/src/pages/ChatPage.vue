<script setup lang="ts">
import { ref, nextTick, watch, onMounted, computed } from "vue";
import { useAgencyStore } from "@/composables/useAgencyStore";
import { useWebSocket } from "@/composables/useWebSocket";
import type { WsIncoming } from "@/types";

const store = useAgencyStore();
const ws = useWebSocket();

const messageInput = ref("");
const chatContainer = ref<HTMLDivElement | null>(null);
const isSending = ref(false);

// Listen for incoming WS chat messages
ws.onMessage((msg: WsIncoming) => {
  if (msg.type === "chat" && msg.sessionId === store.selectedSessionId) {
    scrollToBottom();
  }
});

const sortedMessages = computed(() =>
  [...store.chatMessages].sort(
    (a, b) => new Date(a.occurred_at).getTime() - new Date(b.occurred_at).getTime(),
  ),
);

const hasSession = computed(() => !!store.selectedSessionId);

async function sendMessage() {
  const content = messageInput.value.trim();
  if (!content || isSending.value || !store.selectedSessionId || !store.selectedProjectId) return;

  isSending.value = true;
  messageInput.value = "";

  try {
    // Send via WebSocket for real-time
    ws.sendChat({
      sessionId: store.selectedSessionId,
      projectId: store.selectedProjectId,
      role: "user",
      content,
    });

    // Also send via REST to persist
    await store.sendChatMessage(content);
  } finally {
    isSending.value = false;
    scrollToBottom();
  }
}

function handleKeydown(event: KeyboardEvent) {
  if (event.key === "Enter" && !event.shiftKey) {
    event.preventDefault();
    sendMessage();
  }
}

function scrollToBottom() {
  nextTick(() => {
    if (chatContainer.value) {
      chatContainer.value.scrollTop = chatContainer.value.scrollHeight;
    }
  });
}

function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
}

const roleBadge: Record<string, string> = {
  user: "bg-blue-400/15 text-blue-400",
  assistant: "bg-teal-400/15 text-teal-400",
  system: "bg-amber-400/15 text-amber-400",
  orchestrator: "bg-surface-700 text-surface-300",
};

// Load chat when session changes
watch(() => store.selectedSessionId, (sessionId) => {
  if (sessionId) {
    store.fetchChatMessages(sessionId);
    ws.subscribe(`session:${sessionId}`);
  }
});

onMounted(() => {
  if (store.selectedSessionId) {
    store.fetchChatMessages(store.selectedSessionId);
  }
  scrollToBottom();
});

watch(sortedMessages, scrollToBottom);
</script>

<template>
  <div class="flex flex-col h-full">
    <!-- Header -->
    <header class="flex-shrink-0 px-6 py-4 border-b border-surface-800 bg-surface-900/50">
      <h1 class="text-lg font-semibold text-surface-100">Chat</h1>
      <p class="text-xs text-surface-500 mt-0.5">
        <template v-if="store.selectedSession">
          {{ store.selectedSession.name }}
        </template>
        <template v-else>Select a session to start chatting</template>
      </p>
    </header>

    <!-- Messages -->
    <div ref="chatContainer" class="flex-1 overflow-y-auto px-6 py-4 space-y-4">
      <!-- No session selected -->
      <div v-if="!hasSession" class="flex items-center justify-center h-full">
        <div class="text-center text-surface-600">
          <p class="text-lg">No session selected</p>
          <p class="text-sm mt-1">Pick a session from the sidebar, or go to the Dashboard to find one.</p>
        </div>
      </div>

      <!-- Empty chat -->
      <div
        v-else-if="sortedMessages.length === 0"
        class="flex items-center justify-center h-full"
      >
        <div class="text-center text-surface-600">
          <p class="text-lg">No messages yet</p>
          <p class="text-sm mt-1">Start the conversation below.</p>
        </div>
      </div>

      <!-- Message list -->
      <div
        v-for="msg in sortedMessages"
        :key="msg.id"
        class="flex gap-3 max-w-3xl"
        :class="msg.role === 'user' ? 'ml-auto' : ''"
      >
        <div
          class="rounded-xl px-4 py-3 max-w-full"
          :class="msg.role === 'user'
            ? 'bg-teal-400/10 border border-teal-400/20'
            : 'bg-surface-850 border border-surface-800'"
        >
          <div class="flex items-center gap-2 mb-1">
            <span
              class="text-xs px-1.5 py-0.5 rounded-full font-medium"
              :class="roleBadge[msg.role] ?? 'bg-surface-700 text-surface-400'"
            >
              {{ msg.role }}
            </span>
            <span class="text-xs text-surface-600 font-mono">{{ formatTime(msg.occurred_at) }}</span>
          </div>
          <div class="text-sm text-surface-200 whitespace-pre-wrap break-words">{{ msg.content }}</div>
        </div>
      </div>
    </div>

    <!-- Input -->
    <div class="flex-shrink-0 border-t border-surface-800 bg-surface-900/50 px-6 py-4">
      <div class="flex gap-3 max-w-3xl mx-auto">
        <textarea
          v-model="messageInput"
          :disabled="!hasSession || isSending"
          :placeholder="hasSession ? 'Type a message...' : 'Select a session first'"
          class="flex-1 bg-surface-850 border border-surface-700 rounded-xl px-4 py-3 text-sm text-surface-200 placeholder-surface-600 resize-none focus:outline-none focus:border-teal-400/50 focus:ring-1 focus:ring-teal-400/20 disabled:opacity-50"
          rows="2"
          @keydown="handleKeydown"
        />
        <button
          class="self-end px-4 py-3 rounded-xl bg-teal-400 text-surface-900 font-medium text-sm hover:bg-teal-300 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          :disabled="!hasSession || !messageInput.trim() || isSending"
          @click="sendMessage"
        >
          Send
        </button>
      </div>
    </div>
  </div>
</template>
