import type {
  CompleteOptions,
  EmbedOptions,
  EmbeddingProvider,
  LLMProvider,
} from '../types.ts';

const DEFAULT_BASE = 'https://api.openai.com/v1';
const DEFAULT_LLM_MODEL = 'gpt-4o-mini';
const DEFAULT_EMBED_MODEL = 'text-embedding-3-small';

export interface OpenAIConfig {
  apiKey?: string;
  baseURL?: string;
  model?: string;
  fetch?: typeof fetch;
}

interface ChatResponse {
  choices: { message: { content: string } }[];
}

interface EmbedResponse {
  data: { embedding: number[] }[];
}

export function openaiLLM(config: OpenAIConfig = {}): LLMProvider {
  const apiKey = config.apiKey ?? process.env.OPENAI_API_KEY ?? '';
  const baseURL = config.baseURL ?? DEFAULT_BASE;
  const defaultModel = config.model ?? DEFAULT_LLM_MODEL;
  const fetchImpl = config.fetch ?? fetch;

  return {
    name: 'openai',
    async complete(prompt: string, opts: CompleteOptions = {}): Promise<string> {
      if (!apiKey) {
        throw new Error('openaiLLM: OPENAI_API_KEY is not set.');
      }

      const messages = opts.system
        ? [
            { role: 'system' as const, content: opts.system },
            { role: 'user' as const, content: prompt },
          ]
        : [{ role: 'user' as const, content: prompt }];

      const res = await fetchImpl(`${baseURL}/chat/completions`, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          model: opts.model ?? defaultModel,
          max_tokens: opts.maxTokens ?? 1024,
          messages,
        }),
      });
      if (!res.ok) {
        throw new Error(`openai: HTTP ${res.status}: ${await res.text()}`);
      }
      const json = (await res.json()) as ChatResponse;
      return json.choices[0]?.message.content ?? '';
    },
  };
}

export function openaiEmbeddings(config: OpenAIConfig = {}): EmbeddingProvider {
  const apiKey = config.apiKey ?? process.env.OPENAI_API_KEY ?? '';
  const baseURL = config.baseURL ?? DEFAULT_BASE;
  const defaultModel = config.model ?? DEFAULT_EMBED_MODEL;
  const fetchImpl = config.fetch ?? fetch;

  async function call(texts: string[], opts: EmbedOptions = {}): Promise<Float32Array[]> {
    if (!apiKey) {
      throw new Error('openaiEmbeddings: OPENAI_API_KEY is not set.');
    }
    const res = await fetchImpl(`${baseURL}/embeddings`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({ model: opts.model ?? defaultModel, input: texts }),
    });
    if (!res.ok) {
      throw new Error(`openai-embeddings: HTTP ${res.status}: ${await res.text()}`);
    }
    const json = (await res.json()) as EmbedResponse;
    return json.data.map((d) => new Float32Array(d.embedding));
  }

  return {
    name: 'openai-embeddings',
    async embed(text, opts) {
      const [v] = await call([text], opts);
      return v ?? new Float32Array();
    },
    async embedBatch(texts, opts) {
      return call(texts, opts);
    },
  };
}
