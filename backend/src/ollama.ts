const OLLAMA_URL = Deno.env.get("OLLAMA_URL") ?? "http://localhost:11434";
const EMBED_MODEL = Deno.env.get("EMBED_MODEL") ?? "nomic-embed-text";

export async function generateEmbedding(text: string): Promise<number[]> {
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

export async function ollamaHealthCheck(): Promise<boolean> {
  try {
    const response = await fetch(`${OLLAMA_URL}/api/tags`);
    return response.ok;
  } catch {
    return false;
  }
}
