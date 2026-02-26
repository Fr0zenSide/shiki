import { ref, onUnmounted } from "vue";
import type { WsIncoming, WsOutgoing } from "@/types";

export type WsStatus = "connecting" | "connected" | "disconnected" | "error";

const MAX_RECONNECT_DELAY = 30_000;
const INITIAL_RECONNECT_DELAY = 1_000;

// Singleton WebSocket — shared across the app
let socket: WebSocket | null = null;
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let reconnectDelay = INITIAL_RECONNECT_DELAY;
let refCount = 0;

const status = ref<WsStatus>("disconnected");
const clientId = ref<string | null>(null);
const listeners = new Set<(msg: WsIncoming) => void>();

function getWsUrl(): string {
  const envUrl = import.meta.env.VITE_WS_URL;
  if (envUrl) return envUrl;
  const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
  return `${proto}//${window.location.host}`;
}

function connect() {
  if (socket?.readyState === WebSocket.OPEN || socket?.readyState === WebSocket.CONNECTING) {
    return;
  }

  status.value = "connecting";
  const url = getWsUrl();

  try {
    socket = new WebSocket(url);
  } catch {
    status.value = "error";
    scheduleReconnect();
    return;
  }

  socket.onopen = () => {
    status.value = "connected";
    reconnectDelay = INITIAL_RECONNECT_DELAY;
    console.log("[ws] Connected to", url);
  };

  socket.onclose = () => {
    status.value = "disconnected";
    clientId.value = null;
    socket = null;
    if (refCount > 0) {
      scheduleReconnect();
    }
  };

  socket.onerror = () => {
    status.value = "error";
  };

  socket.onmessage = (event) => {
    try {
      const msg: WsIncoming = JSON.parse(event.data);

      if (msg.type === "connected") {
        clientId.value = msg.clientId;
      }

      for (const listener of listeners) {
        listener(msg);
      }
    } catch {
      console.warn("[ws] Failed to parse message:", event.data);
    }
  };
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  console.log(`[ws] Reconnecting in ${reconnectDelay}ms...`);
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
    reconnectDelay = Math.min(reconnectDelay * 2, MAX_RECONNECT_DELAY);
  }, reconnectDelay);
}

function disconnect() {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
  if (socket) {
    socket.close(1000, "Client disconnect");
    socket = null;
  }
  status.value = "disconnected";
  clientId.value = null;
}

function send(msg: WsOutgoing) {
  if (socket?.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(msg));
  } else {
    console.warn("[ws] Cannot send, not connected");
  }
}

export function useWebSocket() {
  // Track usage for auto-disconnect
  refCount++;

  // Connect if first user
  if (refCount === 1) {
    connect();
  }

  function onMessage(handler: (msg: WsIncoming) => void) {
    listeners.add(handler);
    onUnmounted(() => {
      listeners.delete(handler);
    });
  }

  function subscribe(channel: string) {
    send({ type: "subscribe", channel });
  }

  function unsubscribe(channel: string) {
    send({ type: "unsubscribe", channel });
  }

  function sendChat(data: { sessionId: string; projectId: string; agentId?: string; role?: string; content: string }) {
    send({ type: "chat", ...data });
  }

  onUnmounted(() => {
    refCount--;
    if (refCount <= 0) {
      refCount = 0;
      disconnect();
    }
  });

  return {
    status,
    clientId,
    onMessage,
    subscribe,
    unsubscribe,
    sendChat,
    send,
    reconnect: connect,
  };
}
