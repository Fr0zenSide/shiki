import { ZodError } from "zod";

// ── Request logging ─────────────────────────────────────────────────
const LOG_LEVEL = Deno.env.get("LOG_LEVEL") ?? "info";

function shouldLog(level: string): boolean {
  const levels = ["debug", "info", "warn", "error"];
  return levels.indexOf(level) >= levels.indexOf(LOG_LEVEL);
}

export function logRequest(req: Request, status: number, durationMs: number) {
  if (!shouldLog("info")) return;
  const url = new URL(req.url);
  const ts = new Date().toISOString();
  console.log(`[${ts}] ${req.method} ${url.pathname} ${status} ${durationMs}ms`);
}

export function logDebug(msg: string, ...args: unknown[]) {
  if (!shouldLog("debug")) return;
  console.log(`[debug] ${msg}`, ...args);
}

export function logWarn(msg: string, ...args: unknown[]) {
  if (!shouldLog("warn")) return;
  console.warn(`[warn] ${msg}`, ...args);
}

export function logError(msg: string, ...args: unknown[]) {
  if (!shouldLog("error")) return;
  console.error(`[error] ${msg}`, ...args);
}

// ── CORS headers ────────────────────────────────────────────────────
const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

export function corsHeaders(): Record<string, string> {
  return { ...CORS_HEADERS };
}

// ── JSON response helper ────────────────────────────────────────────
export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

// ── API Key auth middleware ─────────────────────────────────────────
const SHIKI_API_KEY = Deno.env.get("SHIKI_API_KEY");

export function authenticateRequest(req: Request): Response | null {
  // If no API key configured, auth is disabled (dev mode)
  if (!SHIKI_API_KEY) return null;

  // Health endpoint is always public
  const url = new URL(req.url);
  if (url.pathname === "/health") return null;

  const auth = req.headers.get("Authorization");
  if (!auth) {
    return json({ error: "Missing Authorization header" }, 401);
  }

  const token = auth.startsWith("Bearer ") ? auth.slice(7) : auth;
  if (token !== SHIKI_API_KEY) {
    return json({ error: "Invalid API key" }, 403);
  }

  return null; // Auth passed
}

// ── Global error handler ────────────────────────────────────────────
export function handleError(error: unknown): Response {
  // Zod validation errors → 400
  if (error instanceof ZodError) {
    const issues = error.issues.map((i) => ({
      path: i.path.join("."),
      message: i.message,
      code: i.code,
    }));
    return json({ error: "Validation failed", issues }, 400);
  }

  // Known errors with message
  if (error instanceof Error) {
    logError(`Unhandled error: ${error.message}`, error.stack);

    // Postgres-specific errors
    if ("code" in error) {
      const pgCode = (error as Record<string, unknown>).code;
      if (pgCode === "23503") {
        return json({ error: "Referenced entity not found (foreign key violation)" }, 422);
      }
      if (pgCode === "23505") {
        return json({ error: "Duplicate entry (unique constraint violation)" }, 409);
      }
    }

    // Don't leak internal details in production
    const isProduction = Deno.env.get("NODE_ENV") === "production";
    return json(
      { error: isProduction ? "Internal server error" : error.message },
      500,
    );
  }

  logError("Unknown error type:", error);
  return json({ error: "Internal server error" }, 500);
}

// ── Body parser with validation ─────────────────────────────────────
export async function parseBody<T>(req: Request, schema: { parse: (data: unknown) => T }): Promise<T> {
  const contentType = req.headers.get("Content-Type");
  if (!contentType?.includes("application/json")) {
    throw Object.assign(new Error("Content-Type must be application/json"), { status: 415 });
  }

  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    throw Object.assign(new Error("Invalid JSON body"), { status: 400 });
  }

  return schema.parse(raw);
}
