import type {
  CompleteOptions,
  EmbedOptions,
  EmbeddingProvider,
  LLMProvider,
} from './types.ts';

export interface MockLLMOptions {
  respondWith?: (prompt: string, opts?: CompleteOptions) => string;
}

export function mockLLM(opts: MockLLMOptions = {}): LLMProvider & { calls: Array<{ prompt: string; opts?: CompleteOptions }> } {
  const calls: Array<{ prompt: string; opts?: CompleteOptions }> = [];
  const respond = opts.respondWith ?? ((p: string) => `MOCK: ${p.slice(0, 40)}`);
  return {
    name: 'mock',
    calls,
    async complete(prompt, options) {
      const call: { prompt: string; opts?: CompleteOptions } = { prompt };
      if (options !== undefined) call.opts = options;
      calls.push(call);
      return respond(prompt, options);
    },
  };
}

export interface MockEmbeddingOptions {
  dim?: number;
  seed?: number;
}

export function mockEmbeddings(opts: MockEmbeddingOptions = {}): EmbeddingProvider {
  const dim = opts.dim ?? 8;
  const seedOffset = opts.seed ?? 0;
  return {
    name: 'mock-embeddings',
    async embed(text, _options) {
      return deterministicVector(text, dim, seedOffset);
    },
    async embedBatch(texts, _options) {
      return texts.map((t) => deterministicVector(t, dim, seedOffset));
    },
  };
}

function deterministicVector(text: string, dim: number, seedOffset: number): Float32Array {
  const out = new Float32Array(dim);
  let h = 2166136261 ^ seedOffset;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  let state = h >>> 0;
  for (let i = 0; i < dim; i++) {
    state = (state * 1664525 + 1013904223) >>> 0;
    out[i] = (state / 0xffffffff) * 2 - 1;
  }
  const mag = Math.sqrt(out.reduce((s, v) => s + v * v, 0));
  if (mag > 0) {
    for (let i = 0; i < dim; i++) out[i] = out[i]! / mag;
  }
  return out;
}
