import postgres from "postgres";

const DATABASE_URL = Deno.env.get("DATABASE_URL") ?? "postgres://acc:acc@localhost:5432/acc";

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
