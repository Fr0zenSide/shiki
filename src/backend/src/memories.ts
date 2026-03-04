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
  createdAt: Date;
  fromAgent: string | null;
}

export async function searchMemories(query: string, projectId: string, limit = 10, threshold = 0.7): Promise<SearchResult[]> {
  const queryEmbedding = await generateEmbedding(query);

  const results = await sql`
    SELECT
      id,
      content,
      category,
      1 - (embedding <=> ${JSON.stringify(queryEmbedding)}::vector) AS similarity,
      created_at,
      (SELECT handle FROM agents WHERE id = agent_memories.agent_id) AS from_agent
    FROM agent_memories
    WHERE project_id = ${projectId}
      AND embedding IS NOT NULL
      AND 1 - (embedding <=> ${JSON.stringify(queryEmbedding)}::vector) > ${threshold}
    ORDER BY embedding <=> ${JSON.stringify(queryEmbedding)}::vector
    LIMIT ${limit}
  `;

  return results.map((r: any) => ({
    id: r.id,
    content: r.content,
    category: r.category,
    similarity: parseFloat(r.similarity),
    createdAt: r.created_at,
    fromAgent: r.from_agent,
  }));
}
