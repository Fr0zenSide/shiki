import { sql } from "./db.ts";
import { generateEmbedding } from "./ollama.ts";

export interface Memory {
  projectId: string;
  sessionId?: string;
  agentId?: string;
  content: string;
  category?: string;
  importance?: number;
}

export async function storeMemory(memory: Memory): Promise<string> {
  // Insert immediately with null embedding
  const [row] = await sql`
    INSERT INTO agent_memories (project_id, session_id, agent_id, content, category, importance)
    VALUES (${memory.projectId}, ${memory.sessionId ?? null}, ${memory.agentId ?? null}, ${memory.content}, ${memory.category ?? "general"}, ${memory.importance ?? 1.0})
    RETURNING id
  `;

  // Generate and store embedding asynchronously
  embedMemoryAsync(row.id, memory.content);

  return row.id;
}

async function embedMemoryAsync(memoryId: string, content: string) {
  try {
    const embedding = await generateEmbedding(content);
    await sql`
      UPDATE agent_memories SET embedding = ${JSON.stringify(embedding)}::vector
      WHERE id = ${memoryId}
    `;
  } catch (error) {
    console.error(`Failed to embed memory ${memoryId}:`, error);
  }
}

export interface SearchResult {
  id: string;
  content: string;
  category: string;
  similarity: number;
  freshness: number;
  createdAt: Date;
  corroborationCount: number;
  fromAgent: string | null;
}

export async function searchMemories(
  query: string,
  projectIds: string[] | null,
  limit = 10,
  threshold = 0.7,
  types?: string[] | null,
): Promise<SearchResult[]> {
  const queryEmbedding = await generateEmbedding(query);

  // Build WHERE clauses dynamically
  const conditions = [
    sql`embedding IS NOT NULL`,
    sql`1 - (embedding <=> ${JSON.stringify(queryEmbedding)}::vector) > ${threshold}`,
  ];

  if (projectIds && projectIds.length > 0) {
    conditions.push(sql`project_id = ANY(${projectIds})`);
  }

  if (types && types.length > 0) {
    conditions.push(sql`category = ANY(${types})`);
  }

  const whereClause = conditions.reduce((acc, cond, i) => i === 0 ? cond : sql`${acc} AND ${cond}`);

  const results = await sql`
    SELECT
      id,
      content,
      category,
      1 - (embedding <=> ${JSON.stringify(queryEmbedding)}::vector) AS similarity,
      compute_freshness(COALESCE(last_corroborated_at, created_at)) AS freshness,
      created_at,
      corroboration_count,
      (SELECT handle FROM agents WHERE id = agent_memories.agent_id) AS from_agent
    FROM agent_memories
    WHERE ${whereClause}
    ORDER BY
      (1 - (embedding <=> ${JSON.stringify(queryEmbedding)}::vector))
      * compute_freshness(COALESCE(last_corroborated_at, created_at))
      DESC
    LIMIT ${limit}
  `;

  // Corroborate accessed memories (they were referenced by a search)
  const ids = results.map((r: any) => r.id);
  if (ids.length > 0) {
    sql`UPDATE agent_memories SET
      last_corroborated_at = NOW(),
      freshness = 1.0,
      corroboration_count = corroboration_count + 1,
      last_accessed_at = NOW(),
      access_count = access_count + 1
    WHERE id = ANY(${ids})`.catch(() => {});
  }

  return results.map((r: any) => ({
    id: r.id,
    content: r.content,
    category: r.category,
    similarity: parseFloat(r.similarity),
    freshness: parseFloat(r.freshness),
    createdAt: r.created_at,
    corroborationCount: r.corroboration_count,
    fromAgent: r.from_agent,
  }));
}
