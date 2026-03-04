import postgres from "postgres";

const DATABASE_URL = Deno.env.get("DATABASE_URL") ?? "postgres://shiki:shiki@localhost:5433/shiki";

export const sql = postgres(DATABASE_URL, {
  max: 10,
  idle_timeout: 20,
  connect_timeout: 10,
});

export async function healthCheck(): Promise<boolean> {
  try {
    await sql`SELECT 1`;
    return true;
  } catch {
    return false;
  }
}

export interface DbPoolStats {
  totalConnections: number;
  idleConnections: number;
  waitingQueries: number;
}

export function getPoolStats(): DbPoolStats {
  // postgres.js exposes connection counts on the sql object
  const pool = sql as unknown as Record<string, unknown>;
  return {
    totalConnections: typeof pool.totalConnections === "number" ? pool.totalConnections : -1,
    idleConnections: typeof pool.idleConnections === "number" ? pool.idleConnections : -1,
    waitingQueries: typeof pool.waitingQueries === "number" ? pool.waitingQueries : -1,
  };
}

export async function closePool(): Promise<void> {
  await sql.end({ timeout: 5 });
}
