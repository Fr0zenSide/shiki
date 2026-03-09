import { sql } from "./db.ts";
import { generateEmbedding } from "./ollama.ts";
import { logDebug, logError } from "./middleware.ts";

// ── Types ──────────────────────────────────────────────────────────

export interface IngestChunk {
  content: string;
  category?: string;
  importance?: number;
  filePath?: string;
  chunkIndex?: number;
}

export interface IngestRequest {
  projectId: string;
  sourceType: "github_repo" | "local_path" | "url" | "raw_text";
  sourceUri: string;
  displayName?: string;
  contentHash?: string;
  chunks: IngestChunk[];
  totalChunks?: number;
  config?: {
    dedupThreshold?: number;
    autoCategory?: boolean;
  };
}

export interface IngestResult {
  sourceId: string;
  inserted: number;
  duplicates: number;
  total: number;
  status: string;
}

// ── Auto-categorization ────────────────────────────────────────────

const CATEGORY_RULES: [RegExp, string][] = [
  [/\b(security|auth|token|encrypt|OWASP|vulnerability|CVE|credentials|keychain)\b/i, "security"],
  [/\b(architecture|design.?pattern|SOLID|clean.?arch|hexagonal|MVVM|MVC|coordinator|DI|dependency.?injection)\b/i, "architecture"],
  [/\b(test|spec|assert|mock|coverage|TDD|BDD|fixture)\b/i, "testing"],
  [/\b(deploy|CI\/CD|docker|kubernetes|pipeline|github.?action|infra)\b/i, "devops"],
  [/\b(API|endpoint|REST|GraphQL|schema|route|middleware|request|response)\b/i, "api"],
  [/\b(performance|optimi[zs]|cache|latency|profil|benchmark|memory.?leak)\b/i, "performance"],
  [/\b(error|bug|fix|debug|trace|crash|exception|stack.?trace)\b/i, "debugging"],
  [/\b(UX|UI|accessibility|WCAG|color|typography|layout|animation|responsive)\b/i, "ux"],
  [/\b(database|SQL|migration|schema|index|query|ORM|relation)\b/i, "database"],
  [/\b(config|environment|setting|flag|feature.?flag|toggle)\b/i, "configuration"],
];

function categorizeContent(content: string): string {
  for (const [pattern, category] of CATEGORY_RULES) {
    if (pattern.test(content)) return category;
  }
  return "general";
}

// ── Deduplication ──────────────────────────────────────────────────

async function isDuplicate(
  embedding: number[],
  projectId: string,
  threshold: number,
): Promise<boolean> {
  const results = await sql`
    SELECT 1 - (embedding <=> ${JSON.stringify(embedding)}::vector) AS similarity
    FROM agent_memories
    WHERE project_id = ${projectId}
      AND embedding IS NOT NULL
      AND 1 - (embedding <=> ${JSON.stringify(embedding)}::vector) > ${threshold}
    LIMIT 1
  `;
  return results.length > 0;
}

// ── Core Ingestion Pipeline ────────────────────────────────────────

export async function ingestChunks(request: IngestRequest): Promise<IngestResult> {
  const dedupThreshold = request.config?.dedupThreshold ?? 0.92;
  const autoCategory = request.config?.autoCategory ?? true;

  // 1. Upsert ingestion source
  const [source] = await sql`
    INSERT INTO ingestion_sources (project_id, source_type, source_uri, display_name, content_hash, status, config)
    VALUES (
      ${request.projectId},
      ${request.sourceType},
      ${request.sourceUri},
      ${request.displayName ?? null},
      ${request.contentHash ?? null},
      'processing',
      ${JSON.stringify(request.config ?? {})}
    )
    ON CONFLICT (project_id, source_type, source_uri) DO UPDATE SET
      status = 'processing',
      content_hash = COALESCE(EXCLUDED.content_hash, ingestion_sources.content_hash),
      display_name = COALESCE(EXCLUDED.display_name, ingestion_sources.display_name),
      updated_at = NOW()
    RETURNING id, content_hash
  `;

  const sourceId = source.id;

  // 2. If re-ingesting, delete old chunks from this source
  await sql`
    DELETE FROM agent_memories
    WHERE project_id = ${request.projectId}
      AND metadata->>'source_id' = ${sourceId}
  `;

  // 3. Process each chunk
  let inserted = 0;
  let duplicates = 0;
  const totalChunks = request.totalChunks ?? request.chunks.length;

  for (const chunk of request.chunks) {
    try {
      // Generate embedding
      const embedding = await generateEmbedding(chunk.content);

      // Check for duplicates (skip chunks from this same source — they were just deleted)
      if (await isDuplicate(embedding, request.projectId, dedupThreshold)) {
        duplicates++;
        logDebug(`Chunk ${chunk.chunkIndex ?? "?"} skipped (duplicate)`);
        continue;
      }

      // Determine category
      const category = chunk.category ?? (autoCategory ? categorizeContent(chunk.content) : "general");

      // Build metadata
      const metadata = {
        source_id: sourceId,
        source_type: request.sourceType,
        source_uri: request.sourceUri,
        chunk_index: chunk.chunkIndex ?? inserted,
        total_chunks: totalChunks,
        ...(chunk.filePath ? { file_path: chunk.filePath } : {}),
      };

      // Insert with embedding
      await sql`
        INSERT INTO agent_memories (project_id, content, category, importance, embedding, metadata)
        VALUES (
          ${request.projectId},
          ${chunk.content},
          ${category},
          ${chunk.importance ?? 1.0},
          ${JSON.stringify(embedding)}::vector,
          ${JSON.stringify(metadata)}
        )
      `;
      inserted++;
    } catch (error) {
      logError(`Failed to ingest chunk ${chunk.chunkIndex ?? "?"}:`, error);
    }
  }

  // 4. Update source record
  const status = inserted > 0 ? "completed" : (duplicates === request.chunks.length ? "completed" : "failed");
  await sql`
    UPDATE ingestion_sources
    SET status = ${status},
        chunk_count = ${inserted},
        ingested_at = NOW(),
        updated_at = NOW()
    WHERE id = ${sourceId}
  `;

  return { sourceId, inserted, duplicates, total: request.chunks.length, status };
}

// ── Source Management ──────────────────────────────────────────────

export async function listSources(projectId: string) {
  return await sql`
    SELECT * FROM ingestion_sources
    WHERE project_id = ${projectId}
    ORDER BY created_at DESC
  `;
}

export async function getSource(id: string) {
  const [source] = await sql`SELECT * FROM ingestion_sources WHERE id = ${id}`;
  return source ?? null;
}

export async function deleteSource(id: string): Promise<boolean> {
  // Delete associated memories first
  const [source] = await sql`SELECT project_id FROM ingestion_sources WHERE id = ${id}`;
  if (!source) return false;

  await sql`
    DELETE FROM agent_memories
    WHERE project_id = ${source.project_id}
      AND metadata->>'source_id' = ${id}
  `;

  const result = await sql`DELETE FROM ingestion_sources WHERE id = ${id} RETURNING id`;
  return result.length > 0;
}
