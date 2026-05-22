import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createWatcher } from '../src/watch.ts';

let tmp: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), 'kb-watch-'));
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

describe('createWatcher', () => {
  test('detects a new file after pollNow + flush', async () => {
    const ingested: string[] = [];
    const w = createWatcher({
      paths: [tmp],
      pollMs: 1_000_000,
      debounceMs: 0,
      ingest: (p) => {
        ingested.push(p);
      },
    });

    writeFileSync(join(tmp, 'a.md'), 'hi');
    const changed = await w.pollNow();
    expect(changed).toBe(1);
    // debounce is 0; tick should have flushed already.
    expect(ingested).toEqual([join(tmp, 'a.md')]);
  });

  test('detects mtime changes', async () => {
    const file = join(tmp, 'b.md');
    writeFileSync(file, 'v1');
    const ingested: string[] = [];
    const w = createWatcher({
      paths: [tmp],
      pollMs: 1_000_000,
      debounceMs: 0,
      ingest: (p) => {
        ingested.push(p);
      },
    });
    // Force mtime forward — write twice with delay
    await new Promise((r) => setTimeout(r, 25));
    writeFileSync(file, 'v2');
    const c = await w.pollNow();
    expect(c).toBe(1);
    expect(ingested).toContain(file);
  });

  test('debounce holds the queue until quiet window elapses', async () => {
    const w = createWatcher({
      paths: [tmp],
      pollMs: 1_000_000,
      debounceMs: 100,
      ingest: () => {},
    });
    writeFileSync(join(tmp, 'c.md'), 'x');
    await w.pollNow();
    expect(w.queue()).toContain(join(tmp, 'c.md'));
    // wait less than debounce — still pending
    await new Promise((r) => setTimeout(r, 20));
    writeFileSync(join(tmp, 'c.md'), 'y');
    await w.pollNow();
    expect(w.queue().length).toBeGreaterThan(0);
    await new Promise((r) => setTimeout(r, 150));
    await w.pollNow();
    expect(w.queue().length).toBe(0);
  });

  test('flush ingests all pending paths', async () => {
    const ingested: string[] = [];
    const w = createWatcher({
      paths: [tmp],
      pollMs: 1_000_000,
      debounceMs: 1_000_000,
      ingest: (p) => {
        ingested.push(p);
      },
    });
    writeFileSync(join(tmp, 'd.md'), 'x');
    writeFileSync(join(tmp, 'e.md'), 'y');
    await w.pollNow();
    expect(w.queue().length).toBe(2);
    await w.flush();
    expect(ingested.sort()).toEqual([join(tmp, 'd.md'), join(tmp, 'e.md')].sort());
  });

  test('include filter drops non-matching files', async () => {
    const ingested: string[] = [];
    mkdirSync(join(tmp, 'sub'), { recursive: true });
    const w = createWatcher({
      paths: [tmp],
      pollMs: 1_000_000,
      debounceMs: 0,
      include: (p) => p.endsWith('.md'),
      ingest: (p) => {
        ingested.push(p);
      },
    });
    writeFileSync(join(tmp, 'sub', 'ok.md'), 'x');
    writeFileSync(join(tmp, 'sub', 'skip.txt'), 'y');
    await w.pollNow();
    expect(ingested).toEqual([join(tmp, 'sub', 'ok.md')]);
  });
});
