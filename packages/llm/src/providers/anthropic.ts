import type { CompleteOptions, LLMProvider } from '../types.ts';

const DEFAULT_MODEL = 'claude-haiku-4-5-20251001';
const ENDPOINT = 'https://api.anthropic.com/v1/messages';

export interface AnthropicConfig {
  apiKey?: string;
  model?: string;
  baseURL?: string;
  fetch?: typeof fetch;
}

interface AnthropicTextBlock {
  type: 'text';
  text: string;
}

interface AnthropicResponse {
  content: AnthropicTextBlock[];
}

export function anthropicLLM(config: AnthropicConfig = {}): LLMProvider {
  const apiKey = config.apiKey ?? process.env.ANTHROPIC_API_KEY ?? '';
  const defaultModel = config.model ?? DEFAULT_MODEL;
  const baseURL = config.baseURL ?? ENDPOINT;
  const fetchImpl = config.fetch ?? fetch;

  return {
    name: 'anthropic',
    async complete(prompt: string, opts: CompleteOptions = {}): Promise<string> {
      if (!apiKey) {
        throw new Error(
          'anthropicLLM: ANTHROPIC_API_KEY is not set (pass apiKey in config or set env var).',
        );
      }

      const userContent =
        opts.cache?.documentContext !== undefined
          ? [
              {
                type: 'text' as const,
                text: opts.cache.documentContext,
                cache_control: { type: 'ephemeral' as const },
              },
              { type: 'text' as const, text: stripDocument(prompt, opts.cache.documentContext) },
            ]
          : prompt;

      const body: Record<string, unknown> = {
        model: opts.model ?? defaultModel,
        max_tokens: opts.maxTokens ?? 1024,
        messages: [{ role: 'user', content: userContent }],
      };
      if (opts.system !== undefined) body.system = opts.system;

      const res = await fetchImpl(baseURL, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'anthropic-beta': 'prompt-caching-2024-07-31',
        },
        body: JSON.stringify(body),
      });

      if (!res.ok) {
        const text = await res.text();
        throw new Error(`anthropic: HTTP ${res.status}: ${text}`);
      }

      const json = (await res.json()) as AnthropicResponse;
      return json.content.map((c) => c.text).join('');
    },
  };
}

function stripDocument(prompt: string, document: string): string {
  return prompt.replace(document, '').trim();
}
