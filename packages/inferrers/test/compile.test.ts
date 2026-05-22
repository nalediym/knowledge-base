import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { mockEmbeddings, mockLLM } from '@kb/llm';
import { openStore } from '@kb/store-sqlite';
import { compileInferrer } from '../src/compile.ts';

let tmp: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), 'kb-compile-'));
  mkdirSync(join(tmp, 'kb/raw'), { recursive: true });
  mkdirSync(join(tmp, 'kb/.index'), { recursive: true });
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

describe('compileInferrer', () => {
  test('indexes every raw chunk into the store with contextualised text + embeddings', async () => {
    writeFileSync(
      join(tmp, 'kb/raw/auth--jwt.md'),
      '# Auth\n\n## JWT\n\n24h expiry...\n\n## Refresh\n\n...',
    );

    const llm = mockLLM({ respondWith: () => 'context for chunk' });
    const embeddings = mockEmbeddings({ dim: 8 });
    const dbPath = join(tmp, 'kb/.index/search.sqlite');

    const result = await compileInferrer({
      kbRoot: tmp,
      llm,
      embeddings,
      embeddingModel: 'mock-embeddings',
      dbPath,
    }).run({ kbRoot: tmp });

    expect(result.pagesWritten).toBeGreaterThan(0);

    const store = openStore(dbPath);
    const hits = store.searchText('context for chunk', { limit: 10 });
    expect(hits.length).toBeGreaterThan(0);

    const vectorHits = store.searchVector(await embeddings.embed('JWT'), 'mock-embeddings', {
      limit: 1,
    });
    expect(vectorHits).toHaveLength(1);

    store.close();
  });

  test('calls contextualize once per chunk', async () => {
    writeFileSync(
      join(tmp, 'kb/raw/notes.md'),
      '# Notes\n\n## one\n\nbody.\n\n## two\n\nbody.\n\n## three\n\nbody.\n',
    );

    const llm = mockLLM({ respondWith: () => 'ctx' });
    const embeddings = mockEmbeddings();

    await compileInferrer({
      kbRoot: tmp,
      llm,
      embeddings,
      embeddingModel: 'mock-embeddings',
      dbPath: join(tmp, 'kb/.index/search.sqlite'),
    }).run({ kbRoot: tmp });

    expect(llm.calls.length).toBe(4);
  });

  test('skipContextualize=true disables LLM calls (vector-only mode)', async () => {
    writeFileSync(join(tmp, 'kb/raw/notes.md'), '# A\n\n## one\n\nbody.\n');

    const llm = mockLLM();
    const embeddings = mockEmbeddings();

    await compileInferrer({
      kbRoot: tmp,
      llm,
      embeddings,
      embeddingModel: 'mock-embeddings',
      dbPath: join(tmp, 'kb/.index/search.sqlite'),
      skipContextualize: true,
    }).run({ kbRoot: tmp });

    expect(llm.calls).toHaveLength(0);
  });
});
