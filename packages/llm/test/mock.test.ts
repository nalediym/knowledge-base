import { describe, expect, test } from 'bun:test';
import { mockEmbeddings, mockLLM } from '../src/index.ts';

describe('mockLLM', () => {
  test('records every call', async () => {
    const llm = mockLLM();
    await llm.complete('first');
    await llm.complete('second', { maxTokens: 50 });
    expect(llm.calls).toHaveLength(2);
    expect(llm.calls[0]!.prompt).toBe('first');
    expect(llm.calls[1]!.opts?.maxTokens).toBe(50);
  });

  test('responds with the user-supplied function', async () => {
    const llm = mockLLM({ respondWith: (p) => `echo: ${p}` });
    expect(await llm.complete('hi')).toBe('echo: hi');
  });
});

describe('mockEmbeddings', () => {
  test('produces a unit-length vector of the requested dim', async () => {
    const e = mockEmbeddings({ dim: 16 });
    const v = await e.embed('hello');
    expect(v.length).toBe(16);
    const mag = Math.sqrt([...v].reduce((s, x) => s + x * x, 0));
    expect(mag).toBeCloseTo(1, 4);
  });

  test('same text produces the same vector (deterministic)', async () => {
    const e = mockEmbeddings();
    const a = await e.embed('hello');
    const b = await e.embed('hello');
    expect([...a]).toEqual([...b]);
  });

  test('different text produces different vectors', async () => {
    const e = mockEmbeddings();
    const a = await e.embed('cats');
    const b = await e.embed('dogs');
    expect([...a]).not.toEqual([...b]);
  });

  test('embedBatch returns one vector per input', async () => {
    const e = mockEmbeddings();
    const vecs = await e.embedBatch(['a', 'b', 'c']);
    expect(vecs).toHaveLength(3);
  });
});
