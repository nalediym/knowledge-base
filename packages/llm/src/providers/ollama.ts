import type {
  CompleteOptions,
  EmbedOptions,
  EmbeddingProvider,
  LLMProvider,
} from '../types.ts';

const DEFAULT_BASE = 'http://localhost:11434';
const DEFAULT_LLM_MODEL = 'llama3.1';
const DEFAULT_EMBED_MODEL = 'nomic-embed-text';

export interface OllamaConfig {
  baseURL?: string;
  model?: string;
  fetch?: typeof fetch;
}

interface OllamaGenerateResponse {
  response: string;
}

interface OllamaEmbedResponse {
  embedding: number[];
}

export function ollamaLLM(config: OllamaConfig = {}): LLMProvider {
  const baseURL = config.baseURL ?? DEFAULT_BASE;
  const defaultModel = config.model ?? DEFAULT_LLM_MODEL;
  const fetchImpl = config.fetch ?? fetch;

  return {
    name: 'ollama',
    async complete(prompt: string, opts: CompleteOptions = {}): Promise<string> {
      const res = await fetchImpl(`${baseURL}/api/generate`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          model: opts.model ?? defaultModel,
          prompt,
          system: opts.system,
          stream: false,
          options: { num_predict: opts.maxTokens ?? 1024 },
        }),
      });
      if (!res.ok) {
        throw new Error(`ollama: HTTP ${res.status}: ${await res.text()}`);
      }
      const json = (await res.json()) as OllamaGenerateResponse;
      return json.response;
    },
  };
}

export function ollamaEmbeddings(config: OllamaConfig = {}): EmbeddingProvider {
  const baseURL = config.baseURL ?? DEFAULT_BASE;
  const defaultModel = config.model ?? DEFAULT_EMBED_MODEL;
  const fetchImpl = config.fetch ?? fetch;

  async function one(text: string, opts: EmbedOptions = {}): Promise<Float32Array> {
    const res = await fetchImpl(`${baseURL}/api/embeddings`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ model: opts.model ?? defaultModel, prompt: text }),
    });
    if (!res.ok) {
      throw new Error(`ollama-embeddings: HTTP ${res.status}: ${await res.text()}`);
    }
    const json = (await res.json()) as OllamaEmbedResponse;
    return new Float32Array(json.embedding);
  }

  return {
    name: 'ollama-embeddings',
    async embed(text, opts) {
      return one(text, opts);
    },
    async embedBatch(texts, opts) {
      const out: Float32Array[] = [];
      for (const t of texts) out.push(await one(t, opts));
      return out;
    },
  };
}
