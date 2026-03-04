import { WsMessageSchema, type WsMessage } from "./schemas.ts";
import { logDebug, logWarn, logError } from "./middleware.ts";
import { sql } from "./db.ts";

// ── Client tracking ─────────────────────────────────────────────────
interface WsClient {
  socket: WebSocket;
  id: string;
  channels: Set<string>;
  connectedAt: number;
}

const clients = new Map<string, WsClient>();
const channels = new Map<string, Set<string>>(); // channel -> client ids

let clientIdCounter = 0;

// ── Public API ──────────────────────────────────────────────────────

export function handleWsUpgrade(req: Request): Response {
  const { socket, response } = Deno.upgradeWebSocket(req);
  const clientId = `ws_${++clientIdCounter}_${Date.now()}`;

  socket.onopen = () => {
    clients.set(clientId, {
      socket,
      id: clientId,
      channels: new Set(),
      connectedAt: Date.now(),
    });
    logDebug(`[ws] client ${clientId} connected (${clients.size} total)`);

    // Send welcome message
    safeSend(socket, JSON.stringify({
      type: "connected",
      clientId,
      timestamp: new Date().toISOString(),
    }));
  };

  socket.onclose = () => {
    const client = clients.get(clientId);
    if (client) {
      // Remove from all channels
      for (const ch of client.channels) {
        channels.get(ch)?.delete(clientId);
        if (channels.get(ch)?.size === 0) {
          channels.delete(ch);
        }
      }
      clients.delete(clientId);
    }
    logDebug(`[ws] client ${clientId} disconnected (${clients.size} total)`);
  };

  socket.onerror = (event) => {
    logError(`[ws] client ${clientId} error:`, event);
  };

  socket.onmessage = (event) => {
    handleMessage(clientId, event.data);
  };

  return response;
}

async function handleMessage(clientId: string, raw: string | ArrayBuffer) {
  const client = clients.get(clientId);
  if (!client) return;

  try {
    const data = typeof raw === "string" ? raw : new TextDecoder().decode(raw);
    const parsed = JSON.parse(data);
    const message = WsMessageSchema.parse(parsed);

    switch (message.type) {
      case "subscribe":
        subscribeClient(clientId, message.channel);
        break;
      case "unsubscribe":
        unsubscribeClient(clientId, message.channel);
        break;
      case "chat":
        await handleChatMessage(clientId, message);
        break;
    }
  } catch (error) {
    logWarn(`[ws] invalid message from ${clientId}:`, error);
    safeSend(client.socket, JSON.stringify({
      type: "error",
      message: error instanceof Error ? error.message : "Invalid message format",
    }));
  }
}

// ── Channel management ──────────────────────────────────────────────

function subscribeClient(clientId: string, channel: string) {
  const client = clients.get(clientId);
  if (!client) return;

  client.channels.add(channel);
  if (!channels.has(channel)) {
    channels.set(channel, new Set());
  }
  channels.get(channel)!.add(clientId);

  logDebug(`[ws] ${clientId} subscribed to ${channel} (${channels.get(channel)!.size} subscribers)`);

  safeSend(client.socket, JSON.stringify({
    type: "subscribed",
    channel,
    timestamp: new Date().toISOString(),
  }));
}

function unsubscribeClient(clientId: string, channel: string) {
  const client = clients.get(clientId);
  if (!client) return;

  client.channels.delete(channel);
  channels.get(channel)?.delete(clientId);
  if (channels.get(channel)?.size === 0) {
    channels.delete(channel);
  }

  safeSend(client.socket, JSON.stringify({
    type: "unsubscribed",
    channel,
    timestamp: new Date().toISOString(),
  }));
}

// ── Chat relay ──────────────────────────────────────────────────────

async function handleChatMessage(senderId: string, msg: Extract<WsMessage, { type: "chat" }>) {
  // Persist to DB
  try {
    await sql`
      INSERT INTO chat_messages (occurred_at, session_id, project_id, agent_id, role, content, metadata)
      VALUES (NOW(), ${msg.sessionId}, ${msg.projectId}, ${msg.agentId ?? null}, ${msg.role}, ${msg.content}, ${JSON.stringify({ via: "websocket", senderId })}::jsonb)
    `;
  } catch (err) {
    logError("[ws] Failed to persist chat message:", err);
  }

  // Broadcast to session channel and global
  const envelope = JSON.stringify({
    type: "chat",
    sessionId: msg.sessionId,
    projectId: msg.projectId,
    agentId: msg.agentId,
    role: msg.role,
    content: msg.content,
    timestamp: new Date().toISOString(),
  });

  // Send to project channel subscribers
  const projectChannel = `project:${msg.projectId}`;
  broadcastToChannel(projectChannel, envelope, senderId);

  // Send to session channel subscribers
  const sessionChannel = `session:${msg.sessionId}`;
  broadcastToChannel(sessionChannel, envelope, senderId);

  // Broadcast to "all" channel subscribers
  broadcastToChannel("all", envelope, senderId);
}

// ── Broadcast utilities ─────────────────────────────────────────────

function broadcastToChannel(channel: string, data: string, excludeClientId?: string) {
  const subscribers = channels.get(channel);
  if (!subscribers) return;

  for (const clientId of subscribers) {
    if (clientId === excludeClientId) continue;
    const client = clients.get(clientId);
    if (client) {
      safeSend(client.socket, data);
    }
  }
}

/** Broadcast an event to all connected clients (used by REST endpoints to push real-time updates) */
export function broadcastEvent(event: Record<string, unknown>) {
  const data = JSON.stringify(event);
  for (const client of clients.values()) {
    safeSend(client.socket, data);
  }
}

/** Broadcast to a specific channel (for REST-triggered pushes) */
export function broadcastToProject(projectId: string, event: Record<string, unknown>) {
  const data = JSON.stringify(event);
  const channel = `project:${projectId}`;
  broadcastToChannel(channel, data);
  broadcastToChannel("all", data);
}

function safeSend(socket: WebSocket, data: string) {
  try {
    if (socket.readyState === WebSocket.OPEN) {
      socket.send(data);
    }
  } catch (err) {
    logWarn("[ws] send failed:", err);
  }
}

// ── Stats ───────────────────────────────────────────────────────────

export function getWsStats() {
  return {
    clientCount: clients.size,
    channelCount: channels.size,
    channels: Object.fromEntries(
      [...channels.entries()].map(([ch, subs]) => [ch, subs.size]),
    ),
  };
}

// ── Cleanup (for graceful shutdown) ─────────────────────────────────

export function closeAllClients() {
  for (const client of clients.values()) {
    try {
      client.socket.close(1001, "Server shutting down");
    } catch { /* ignore */ }
  }
  clients.clear();
  channels.clear();
}
