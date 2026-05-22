import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openStore } from '../src/index.ts';

function vec(...nums: number[]): Float32Array {
  return new Float32Array(nums);
}

let tmp: string;
let dbPath: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), 'kb-store-'));
  dbPath = join(tmp, 'search.sqlite');
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

describe('store-sqlite', () => {
  test('upsert + searchText returns the matching chunk', () => {
    const store = openStore(dbPath);
    store.upsertPage({
      path: 'wiki/concepts/jwt-auth.md',
      title: 'JWT Authentication',
      mtime: 1_000,
      chunks: [
        { id: 'c-aabbccdd', content: 'JWT tokens encode claims for stateless authentication.' },
      ],
    });

    const hits = store.searchText('stateless authentication', { limit: 10 });

    expect(hits).toHaveLength(1);
    expect(hits[0]!.path).toBe('wiki/concepts/jwt-auth.md');
    expect(hits[0]!.chunkId).toBe('c-aabbccdd');
    expect(hits[0]!.score).toBeGreaterThan(0);

    store.close();
  });

  test('upsertEmbedding + searchVector returns chunks ordered by similarity', () => {
    const store = openStore(dbPath);
    store.upsertPage({
      path: 'a.md',
      title: 'A',
      mtime: 1,
      chunks: [{ id: 'c-aaaa', content: 'about cats' }],
    });
    store.upsertPage({
      path: 'b.md',
      title: 'B',
      mtime: 1,
      chunks: [{ id: 'c-bbbb', content: 'about dogs' }],
    });

    store.upsertEmbedding('a.md', 'c-aaaa', 'test-model', vec(1, 0, 0));
    store.upsertEmbedding('b.md', 'c-bbbb', 'test-model', vec(0, 1, 0));

    const hits = store.searchVector(vec(0.9, 0.1, 0), 'test-model', { limit: 2 });

    expect(hits).toHaveLength(2);
    expect(hits[0]!.chunkId).toBe('c-aaaa');
    expect(hits[1]!.chunkId).toBe('c-bbbb');
    expect(hits[0]!.distance).toBeLessThan(hits[1]!.distance);

    store.close();
  });

  test('searchHybrid fuses text + vector via reciprocal rank fusion', () => {
    const store = openStore(dbPath);

    store.upsertPage({
      path: 'cats.md',
      title: 'Cats',
      mtime: 1,
      chunks: [{ id: 'c-cat', content: 'a story about a cat' }],
    });
    store.upsertPage({
      path: 'dogs.md',
      title: 'Dogs',
      mtime: 1,
      chunks: [{ id: 'c-dog', content: 'a story about a dog' }],
    });
    store.upsertPage({
      path: 'fish.md',
      title: 'Fish',
      mtime: 1,
      chunks: [{ id: 'c-fish', content: 'something else entirely' }],
    });

    store.upsertEmbedding('cats.md', 'c-cat', 'm', vec(1, 0));
    store.upsertEmbedding('dogs.md', 'c-dog', 'm', vec(0, 1));
    store.upsertEmbedding('fish.md', 'c-fish', 'm', vec(0.5, 0.5));

    const hits = store.searchHybrid({
      text: 'cat',
      vector: vec(0.95, 0.05),
      model: 'm',
      limit: 3,
    });

    expect(hits.length).toBeGreaterThan(0);
    expect(hits[0]!.chunkId).toBe('c-cat');
    expect(hits[0]!.score).toBeGreaterThan(hits[hits.length - 1]!.score);

    store.close();
  });
});
