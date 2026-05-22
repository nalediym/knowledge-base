import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  addSource,
  newManifest,
  readManifest,
  writeManifest,
} from '../src/manifest.ts';

function makeSource(slug: string, hash = 'aaaaaaaa'): {
  slug: string;
  path: string;
  hash: string;
  ingestedAt: string;
  chunks: number;
} {
  return {
    slug,
    path: `kb/raw/${slug}.md`,
    hash,
    ingestedAt: '2026-05-21T00:00:00Z',
    chunks: 3,
  };
}

function writeLockFile(kbRoot: string, ageSec: number, operation = 'ingest'): void {
  const dir = join(kbRoot, 'kb');
  mkdirSync(dir, { recursive: true });
  const ts = new Date(Date.now() - ageSec * 1000).toISOString();
  writeFileSync(
    join(dir, '.kb-lock'),
    JSON.stringify({ pid: '99999', ts, operation }),
  );
}

let tmp: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), 'kb-manifest-'));
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

describe('manifest', () => {
  test('round-trips a fresh manifest through disk', async () => {
    const m = newManifest('my-project');
    const writeResult = await writeManifest(tmp, m);
    expect(writeResult.ok).toBe(true);

    const read = await readManifest(tmp);
    expect(read).toEqual(m);
  });

  test('reading a non-existent manifest returns null', async () => {
    const read = await readManifest(tmp);
    expect(read).toBeNull();
  });

  test('addSource appends a new source', () => {
    const m = newManifest('p');
    const updated = addSource(m, makeSource('foo'));
    expect(updated.sources).toHaveLength(1);
    expect(updated.sources[0]!.slug).toBe('foo');
  });

  test('addSource replaces an existing source with the same slug', () => {
    const m = addSource(newManifest('p'), makeSource('foo', 'hash-v1'));
    const updated = addSource(m, makeSource('foo', 'hash-v2'));
    expect(updated.sources).toHaveLength(1);
    expect(updated.sources[0]!.hash).toBe('hash-v2');
  });

  test('addSource is pure (does not mutate input)', () => {
    const m = newManifest('p');
    addSource(m, makeSource('foo'));
    expect(m.sources).toHaveLength(0);
  });

  test('writeManifest refuses when a fresh lock is held', async () => {
    writeLockFile(tmp, 10);
    const result = await writeManifest(tmp, newManifest('p'));
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe('locked');
      expect(result.holder.pid).toBe('99999');
    }
  });

  test('writeManifest overrides a stale lock (>300s old)', async () => {
    writeLockFile(tmp, 500);
    const result = await writeManifest(tmp, newManifest('p'));
    expect(result.ok).toBe(true);
  });

  test('writeManifest releases the lock on success', async () => {
    await writeManifest(tmp, newManifest('p'));
    const second = await writeManifest(tmp, newManifest('p'));
    expect(second.ok).toBe(true);
  });
});
