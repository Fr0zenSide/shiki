<script setup lang="ts">
import { ref, nextTick, watch, onMounted, onUnmounted, computed } from "vue";
import { useAgencyStore } from "@/composables/useAgencyStore";
import { useWebSocket } from "@/composables/useWebSocket";
import { registerShortcut, unregisterShortcut } from "@/composables/useKeyboardShortcuts";
import type { ChatMessage, WsIncoming } from "@/types";

const store = useAgencyStore();
const ws = useWebSocket();

const messageInput = ref("");
const chatContainer = ref<HTMLDivElement | null>(null);
const textareaRef = ref<HTMLTextAreaElement | null>(null);
const isSending = ref(false);
const chatFilter = ref<"all" | "active">("all");

// Reply state
const replyTo = ref<ChatMessage | null>(null);

// Drag-to-resize state
const inputHeight = ref(120);
const isDragging = ref(false);
const dragStartY = ref(0);
const dragStartHeight = ref(0);

// Track chat page visit for unread badge
onMounted(() => {
  store.enterChatPage();
  if (store.selectedSessionId) {
    store.fetchChatMessages(store.selectedSessionId);
  }
  scrollToBottom();

  // Register chat-specific shortcuts
  registerShortcut({
    keys: "Cmd+Shift+k",
    label: "Clear chat input",
    group: "Chat",
    handler: () => {
      messageInput.value = "";
      replyTo.value = null;
      textareaRef.value?.focus();
    },
  });

  registerShortcut({
    keys: "Cmd+j",
    label: "Scroll to latest",
    group: "Chat",
    handler: scrollToBottom,
  });
});

onUnmounted(() => {
  store.leaveChatPage();
  unregisterShortcut("Cmd+Shift+k");
  unregisterShortcut("Cmd+j");
  cleanupDrag();
});

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

// Filter messages based on Active/All toggle
const filteredMessages = computed(() => {
  if (chatFilter.value === "all") return sortedMessages.value;

  // "Active" filter: messages from agents with status 'running' or recent (last 5 min)
  const fiveMinAgo = Date.now() - 5 * 60 * 1000;
  const runningAgentIds = new Set(
    store.agents
      .filter((a) => a.status === "running" || a.status === "spawned")
      .map((a) => a.id),
  );

  return sortedMessages.value.filter((msg) => {
    // Always show user messages
    if (msg.role === "user") return true;
    // Show messages from running agents
    if (msg.agent_id && runningAgentIds.has(msg.agent_id)) return true;
    // Show recent messages (last 5 min)
    if (new Date(msg.occurred_at).getTime() > fiveMinAgo) return true;
    return false;
  });
});

const hasSession = computed(() => !!store.selectedSessionId);

// Claude response detection
function isClaudeResponse(msg: ChatMessage): boolean {
  if (msg.role !== "assistant") return false;
  if (!msg.agent_id) return true; // assistant with no agent = Claude
  const md = msg.metadata as Record<string, unknown>;
  return md?.isClaudeResponse === true;
}

async function sendMessage() {
  const content = messageInput.value.trim();
  if (!content || isSending.value || !store.selectedSessionId || !store.selectedProjectId) return;

  isSending.value = true;

  // Prepend reply context if replying
  let finalContent = content;
  if (replyTo.value) {
    const quotedOriginal = replyTo.value.content.slice(0, 120);
    finalContent = `> Re: ${quotedOriginal}${replyTo.value.content.length > 120 ? '...' : ''}\n\n${content}`;
  }

  messageInput.value = "";
  replyTo.value = null;

  try {
    // Send via WebSocket for real-time
    ws.sendChat({
      sessionId: store.selectedSessionId,
      projectId: store.selectedProjectId,
      role: "user",
      content: finalContent,
    });

    // Also send via REST to persist
    await store.sendChatMessage(finalContent);
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

function setReplyTo(msg: ChatMessage) {
  replyTo.value = msg;
  textareaRef.value?.focus();
}

function clearReply() {
  replyTo.value = null;
}

// Drag-to-resize handlers
function onDragStart(e: PointerEvent) {
  isDragging.value = true;
  dragStartY.value = e.clientY;
  dragStartHeight.value = inputHeight.value;
  document.addEventListener("pointermove", onDragMove);
  document.addEventListener("pointerup", onDragEnd);
  document.body.style.userSelect = "none";
  document.body.style.cursor = "row-resize";
}

function onDragMove(e: PointerEvent) {
  if (!isDragging.value) return;
  const delta = dragStartY.value - e.clientY; // moving up = bigger
  const newHeight = Math.min(
    Math.max(dragStartHeight.value + delta, 80),
    window.innerHeight * 0.5,
  );
  inputHeight.value = newHeight;
}

function onDragEnd() {
  isDragging.value = false;
  document.removeEventListener("pointermove", onDragMove);
  document.removeEventListener("pointerup", onDragEnd);
  document.body.style.userSelect = "";
  document.body.style.cursor = "";
}

function cleanupDrag() {
  document.removeEventListener("pointermove", onDragMove);
  document.removeEventListener("pointerup", onDragEnd);
  document.body.style.userSelect = "";
  document.body.style.cursor = "";
}

// Load chat when session changes
watch(() => store.selectedSessionId, (sessionId) => {
  if (sessionId) {
    store.fetchChatMessages(sessionId);
    ws.subscribe(`session:${sessionId}`);
  }
});

watch(filteredMessages, scrollToBottom);
</script>

<template>
  <div class="flex flex-col h-full">
    <!-- Header -->
    <header class="flex-shrink-0 px-6 py-4 border-b border-surface-800 bg-surface-900/50">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-lg font-semibold text-surface-100">Chat</h1>
          <p class="text-xs text-surface-500 mt-0.5">
            <template v-if="store.selectedSession">
              {{ store.selectedSession.name }}
            </template>
            <template v-else>Select a session to start chatting</template>
          </p>
        </div>

        <!-- Active/All toggle -->
        <div v-if="hasSession" class="flex items-center gap-1 bg-surface-850 rounded-lg p-0.5">
          <button
            class="px-3 py-1 rounded-md text-xs font-medium transition-colors"
            :class="chatFilter === 'all'
              ? 'bg-surface-700 text-surface-200'
              : 'text-surface-500 hover:text-surface-300'"
            @click="chatFilter = 'all'"
          >
            All
          </button>
          <button
            class="px-3 py-1 rounded-md text-xs font-medium transition-colors"
            :class="chatFilter === 'active'
              ? 'bg-teal-400/15 text-teal-400'
              : 'text-surface-500 hover:text-surface-300'"
            @click="chatFilter = 'active'"
          >
            Active
          </button>
        </div>
      </div>
    </header>

    <!-- Messages -->
    <div ref="chatContainer" class="flex-1 overflow-y-auto px-6 py-4 space-y-4">
      <!-- No session selected -->
      <div v-if="!hasSession" class="flex items-center justify-center h-full">
        <div class="text-center text-surface-600">
          <p class="text-lg">No session selected</p>
          <p class="text-sm mt-1">Pick a session from the Dashboard, or use Cmd+Shift+1 to navigate there.</p>
        </div>
      </div>

      <!-- Empty chat -->
      <div
        v-else-if="filteredMessages.length === 0"
        class="flex items-center justify-center h-full"
      >
        <div class="text-center text-surface-600">
          <p class="text-lg">{{ chatFilter === 'active' ? 'No active messages' : 'No messages yet' }}</p>
          <p class="text-sm mt-1">
            {{ chatFilter === 'active' ? 'Switch to All to see the full history.' : 'Start the conversation below.' }}
          </p>
        </div>
      </div>

      <!-- Message list -->
      <div
        v-for="msg in filteredMessages"
        :key="msg.id"
        class="flex gap-3 max-w-3xl group"
        :class="msg.role === 'user' ? 'ml-auto' : ''"
      >
        <div
          class="rounded-xl px-4 py-3 max-w-full relative"
          :class="[
            msg.role === 'user'
              ? 'bg-teal-400/10 border border-teal-400/20'
              : isClaudeResponse(msg)
                ? 'bg-gradient-to-r from-teal-400/5 to-transparent border-l-2 border-teal-400 border border-surface-800'
                : 'bg-surface-850 border border-surface-800',
          ]"
        >
          <div class="flex items-center gap-2 mb-1">
            <!-- Claude badge with sparkle -->
            <template v-if="isClaudeResponse(msg)">
              <span class="text-xs px-1.5 py-0.5 rounded-full font-medium bg-teal-400/15 text-teal-400 flex items-center gap-1">
                <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 16 16">
                  <path d="M8 0a.5.5 0 01.5.5v2a.5.5 0 01-1 0v-2A.5.5 0 018 0zm0 13a.5.5 0 01.5.5v2a.5.5 0 01-1 0v-2A.5.5 0 018 13zm8-5a.5.5 0 01-.5.5h-2a.5.5 0 010-1h2a.5.5 0 01.5.5zM3 8a.5.5 0 01-.5.5h-2a.5.5 0 010-1h2A.5.5 0 013 8zm10.657-5.657a.5.5 0 010 .707l-1.414 1.414a.5.5 0 11-.707-.707l1.414-1.414a.5.5 0 01.707 0zm-9.193 9.193a.5.5 0 010 .707L3.05 13.657a.5.5 0 11-.707-.707l1.414-1.414a.5.5 0 01.707 0zm9.193 2.121a.5.5 0 01-.707 0l-1.414-1.414a.5.5 0 01.707-.707l1.414 1.414a.5.5 0 010 .707zM4.464 4.465a.5.5 0 01-.707 0L2.343 3.05a.5.5 0 11.707-.707l1.414 1.414a.5.5 0 010 .708z"/>
                </svg>
                Claude
              </span>
            </template>
            <template v-else>
              <span
                class="text-xs px-1.5 py-0.5 rounded-full font-medium"
                :class="roleBadge[msg.role] ?? 'bg-surface-700 text-surface-400'"
              >
                {{ msg.role }}
              </span>
            </template>
            <span class="text-xs text-surface-600 font-mono">{{ formatTime(msg.occurred_at) }}</span>
          </div>
          <div class="text-sm text-surface-200 whitespace-pre-wrap break-words">{{ msg.content }}</div>

          <!-- Reply button (hover, non-user messages only) -->
          <button
            v-if="msg.role !== 'user'"
            class="absolute -right-2 top-2 w-6 h-6 rounded-lg bg-surface-800 border border-surface-700 text-surface-500 hover:text-teal-400 hover:border-teal-400/30 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity"
            title="Reply"
            @click="setReplyTo(msg)"
          >
            <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6"/>
            </svg>
          </button>
        </div>
      </div>
    </div>

    <!-- Drag handle -->
    <div
      class="flex-shrink-0 h-1.5 cursor-row-resize bg-surface-800 hover:bg-teal-400/30 transition-colors"
      :class="isDragging ? 'bg-teal-400/40' : ''"
      @pointerdown="onDragStart"
    />

    <!-- Input area -->
    <div
      class="flex-shrink-0 border-t border-surface-800 bg-surface-900/50 px-6 py-4"
      :style="{ height: inputHeight + 'px' }"
    >
      <!-- Reply context bar -->
      <div
        v-if="replyTo"
        class="flex items-center gap-2 mb-2 px-3 py-1.5 bg-surface-850 border border-surface-700 rounded-lg text-xs"
      >
        <svg class="w-3 h-3 text-teal-400 flex-shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6"/>
        </svg>
        <span class="text-surface-400">Replying to</span>
        <span class="text-teal-400 font-medium">{{ replyTo.role }}</span>
        <span class="text-surface-500 truncate flex-1">&mdash; {{ replyTo.content.slice(0, 80) }}{{ replyTo.content.length > 80 ? '...' : '' }}</span>
        <button
          class="text-surface-500 hover:text-surface-300 flex-shrink-0"
          @click="clearReply"
        >
          <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12"/>
          </svg>
        </button>
      </div>

      <div class="flex gap-3 max-w-3xl mx-auto h-full">
        <textarea
          ref="textareaRef"
          v-model="messageInput"
          :disabled="!hasSession || isSending"
          :placeholder="hasSession ? 'Type a message...' : 'Select a session first'"
          class="flex-1 bg-surface-850 border border-surface-700 rounded-xl px-4 py-3 text-sm text-surface-200 placeholder-surface-600 resize-none focus:outline-none focus:border-teal-400/50 focus:ring-1 focus:ring-teal-400/20 disabled:opacity-50"
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
