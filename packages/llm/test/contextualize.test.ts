import { describe, expect, test } from 'bun:test';
import { contextualizeChunk, mockLLM } from '../src/index.ts';

describe('contextualizeChunk', () => {
  test('prepends an LLM-generated context to the chunk', async () => {
    const llm = mockLLM({
      respondWith: () => 'This chunk explains JWT expiration policy.',
    });

    const result = await contextualizeChunk({
      document: '# Auth Guide\n\n## JWT\n\n24h expiry...\n\n## Refresh\n\n...',
      chunk: '## JWT\n\n24h expiry...',
      llm,
    });

    expect(result.startsWith('This chunk explains JWT expiration policy.')).toBe(true);
    expect(result).toContain('## JWT');
    expect(result).toContain('24h expiry');
  });

  test('passes the document into the cache hint for prompt caching', async () => {
    const llm = mockLLM({ respondWith: () => 'ctx' });

    await contextualizeChunk({
      document: 'DOC',
      chunk: 'CHUNK',
      llm,
    });

    expect(llm.calls).toHaveLength(1);
    expect(llm.calls[0]!.opts?.cache?.documentContext).toBe('DOC');
  });

  test('returns the chunk unchanged when the LLM returns empty', async () => {
    const llm = mockLLM({ respondWith: () => '   ' });

    const result = await contextualizeChunk({
      document: 'doc',
      chunk: 'chunk-body',
      llm,
    });

    expect(result).toBe('chunk-body');
  });
});
