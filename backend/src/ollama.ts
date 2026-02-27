// Embedding provider — supports Ollama (/api/embeddings) and OpenAI-compatible (/v1/embeddings) servers like LM Studio.
// Set EMBED_PROVIDER=openai to use LM Studio or any OpenAI-compatible server.

const OLLAMA_URL = Deno.env.get("OLLAMA_URL") ?? "http://localhost:11434";
const EMBED_MODEL = Deno.env.get("EMBED_MODEL") ?? "nomic-embed-text";
const EMBED_PROVIDER = Deno.env.get("EMBED_PROVIDER") ?? "ollama"; // "ollama" | "openai"

export async function generateEmbedding(text: string): Promise<number[]> {
  if (EMBED_PROVIDER === "openai") {
    return generateEmbeddingOpenAI(text);
  }
  return generateEmbeddingOllama(text);
}

async function generateEmbeddingOllama(text: string): Promise<number[]> {
  const response = await fetch(`${OLLAMA_URL}/api/embeddings`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ model: EMBED_MODEL, prompt: text }),
  });

  if (!response.ok) {
    throw new Error(`Ollama embedding failed: ${response.status} ${await response.text()}`);
  }

  const data = await response.json();
  return data.embedding;
}

async function generateEmbeddingOpenAI(text: string): Promise<number[]> {
  const response = await fetch(`${OLLAMA_URL}/v1/embeddings`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ model: EMBED_MODEL, input: text }),
  });

  if (!response.ok) {
    throw new Error(`Embedding failed: ${response.status} ${await response.text()}`);
  }

  const data = await response.json();
  return data.data[0].embedding;
}

export async function ollamaHealthCheck(): Promise<boolean> {
  try {
    if (EMBED_PROVIDER === "openai") {
      const response = await fetch(`${OLLAMA_URL}/v1/models`);
      return response.ok;
    }
    const response = await fetch(`${OLLAMA_URL}/api/tags`);
    return response.ok;
  } catch {
    return false;
  }
}
