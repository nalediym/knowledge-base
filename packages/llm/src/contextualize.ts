import type { LLMProvider } from './types.ts';

export interface ContextualizeArgs {
  document: string;
  chunk: string;
  llm: LLMProvider;
  maxTokens?: number;
}

const SYSTEM_PROMPT = `<document>
{{DOCUMENT}}
</document>

Here is the chunk we want to situate within the whole document:
<chunk>
{{CHUNK}}
</chunk>

Please give a short, succinct context to situate this chunk within the overall document for the purposes of improving search retrieval of the chunk. Answer only with the succinct context and nothing else.`;

export async function contextualizeChunk(args: ContextualizeArgs): Promise<string> {
  const { document, chunk, llm, maxTokens } = args;
  const prompt = SYSTEM_PROMPT.replace('{{DOCUMENT}}', document).replace(
    '{{CHUNK}}',
    chunk,
  );

  const context = await llm.complete(prompt, {
    maxTokens: maxTokens ?? 100,
    cache: { documentContext: document },
  });

  const trimmed = context.trim();
  if (!trimmed) return chunk;
  return `${trimmed}\n\n${chunk}`;
}
