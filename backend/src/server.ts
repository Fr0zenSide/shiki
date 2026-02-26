import { handleRequest } from "./routes.ts";

const WS_PORT = parseInt(Deno.env.get("WS_PORT") ?? "3800");
const clients = new Set<WebSocket>();

Deno.serve({ port: WS_PORT }, (req) => {
  // WebSocket upgrade
  if (req.headers.get("upgrade") === "websocket") {
    const { socket, response } = Deno.upgradeWebSocket(req);
    socket.onopen = () => {
      clients.add(socket);
      console.log(`[ws] client connected (${clients.size} total)`);
    };
    socket.onclose = () => {
      clients.delete(socket);
      console.log(`[ws] client disconnected (${clients.size} total)`);
    };
    socket.onmessage = (event) => {
      // Broadcast to all other clients
      for (const client of clients) {
        if (client !== socket && client.readyState === WebSocket.OPEN) {
          client.send(event.data);
        }
      }
    };
    return response;
  }

  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
      },
    });
  }

  // REST API
  return handleRequest(req);
});

console.log(`ACC v3 server running on http://localhost:${WS_PORT}`);
console.log(`WebSocket: ws://localhost:${WS_PORT}`);
console.log(`Health: http://localhost:${WS_PORT}/health`);
