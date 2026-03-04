import { handleRequest } from "./routes.ts";
import { handleWsUpgrade, closeAllClients, getWsStats } from "./ws.ts";
import { authenticateRequest, corsHeaders, json, logRequest, logError } from "./middleware.ts";
import { closePool } from "./db.ts";

const WS_PORT = parseInt(Deno.env.get("WS_PORT") ?? "3900");

// ── Server ──────────────────────────────────────────────────────────

const abortController = new AbortController();

const server = Deno.serve({
  port: WS_PORT,
  signal: abortController.signal,
  onListen({ port }) {
    console.log(`Shiki server running on http://localhost:${port}`);
    console.log(`WebSocket: ws://localhost:${port}`);
    console.log(`Health: http://localhost:${port}/health`);
    const apiKey = Deno.env.get("SHIKI_API_KEY");
    if (apiKey) {
      console.log("API key auth: enabled");
    } else {
      console.log("API key auth: disabled (set SHIKI_API_KEY to enable)");
    }
  },
}, async (req) => {
  const start = performance.now();
  let status = 200;

  try {
    // WebSocket upgrade (no auth needed for WS — auth happens via message)
    if (req.headers.get("upgrade") === "websocket") {
      return handleWsUpgrade(req);
    }

    // CORS preflight
    if (req.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders() });
    }

    // Auth check
    const authError = authenticateRequest(req);
    if (authError) {
      status = authError.status;
      return authError;
    }

    // WebSocket stats endpoint (internal)
    const url = new URL(req.url);
    if (url.pathname === "/api/ws-stats" && req.method === "GET") {
      return json(getWsStats());
    }

    // Route to REST handler
    const response = await handleRequest(req);
    status = response.status;
    return response;
  } catch (error) {
    logError("Unhandled server error:", error);
    status = 500;
    return json({ error: "Internal server error" }, 500);
  } finally {
    const duration = Math.round(performance.now() - start);
    logRequest(req, status, duration);
  }
});

// ── Graceful shutdown ───────────────────────────────────────────────

let isShuttingDown = false;

async function shutdown(signal: string) {
  if (isShuttingDown) return;
  isShuttingDown = true;

  console.log(`\n[shutdown] Received ${signal}, starting graceful shutdown...`);

  // 1. Stop accepting new connections
  console.log("[shutdown] Closing HTTP server...");
  abortController.abort();

  // 2. Close WebSocket clients
  console.log("[shutdown] Closing WebSocket clients...");
  closeAllClients();

  // 3. Wait for in-flight requests to finish (server.finished resolves)
  console.log("[shutdown] Waiting for in-flight requests...");
  await server.finished;

  // 4. Close DB pool
  console.log("[shutdown] Closing database pool...");
  try {
    await closePool();
  } catch (err) {
    logError("[shutdown] DB pool close error:", err);
  }

  console.log("[shutdown] Shutdown complete.");
  Deno.exit(0);
}

Deno.addSignalListener("SIGINT", () => shutdown("SIGINT"));
Deno.addSignalListener("SIGTERM", () => shutdown("SIGTERM"));
