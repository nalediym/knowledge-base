import { describe, expect, test } from 'bun:test';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  DEFAULT_PAGE_THRESHOLD,
  STREAMING_BACKLINKS_CEILING,
  countWikiPages,
  pageCountCheck,
} from '../src/lint.ts';

describe('pageCountCheck', () => {
  test('returns ok below threshold', () => {
    const r = pageCountCheck(42);
    expect(r.status).toBe('ok');
    expect(r.pageCount).toBe(42);
    expect(r.threshold).toBe(DEFAULT_PAGE_THRESHOLD);
    expect(r.ceiling).toBe(STREAMING_BACKLINKS_CEILING);
  });

  test('warns at and above threshold and references issue #1', () => {
    const r = pageCountCheck(DEFAULT_PAGE_THRESHOLD);
    expect(r.status).toBe('warn');
    expect(r.message).toContain('issue #1');
    expect(r.message).toContain(String(STREAMING_BACKLINKS_CEILING));
  });

  test('respects custom threshold and ceiling', () => {
    const r = pageCountCheck(50, { threshold: 10, ceiling: 100 });
    expect(r.status).toBe('warn');
    expect(r.threshold).toBe(10);
    expect(r.ceiling).toBe(100);
  });
});

describe('countWikiPages', () => {
  test('counts .md files in kb/concepts and kb/raw recursively', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'kb-lint-'));
    mkdirSync(join(tmp, 'kb/concepts/nested'), { recursive: true });
    mkdirSync(join(tmp, 'kb/raw'), { recursive: true });
    mkdirSync(join(tmp, 'kb/candidates'), { recursive: true });
    writeFileSync(join(tmp, 'kb/concepts/a.md'), '#');
    writeFileSync(join(tmp, 'kb/concepts/nested/b.md'), '#');
    writeFileSync(join(tmp, 'kb/raw/c.md'), '#');
    writeFileSync(join(tmp, 'kb/concepts/skip.txt'), 'no');
    writeFileSync(join(tmp, 'kb/candidates/x.md'), '# excluded');

    expect(countWikiPages(tmp)).toBe(3);
  });

  test('returns 0 on missing KB dirs', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'kb-lint-empty-'));
    expect(countWikiPages(tmp)).toBe(0);
  });
});
