import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  crossSourcePairs,
  detectConflicts,
  extractClaims,
  findReferencedSources,
  heuristicComparator,
  lifecycle,
  llmComparator,
  renderReport,
  shouldScan,
  type ClaimComparator,
  type Finding,
} from '../src/conflicts.ts';
import type { LLMProvider } from '@kb/llm';

let tmp: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), 'kb-conflicts-'));
  mkdirSync(join(tmp, 'kb/wiki/concepts'), { recursive: true });
  mkdirSync(join(tmp, 'kb/wiki/sources'), { recursive: true });
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

function srcPage(name: string, claims: { text: string; id: string }[]): string {
  const path = join(tmp, 'kb/wiki/sources', `${name}.md`);
  const body = `# ${name}\n\n## Key Claims\n\n${claims
    .map((c) => `- ${c.text} — c-${c.id}`)
    .join('\n')}\n`;
  writeFileSync(path, body);
  return path;
}

function conceptPage(name: string, links: string[]): string {
  const path = join(tmp, 'kb/wiki/concepts', `${name}.md`);
  const body =
    `# ${name}\n\n` +
    links.map((l) => `- See [${l}](../sources/${l}.md)`).join('\n') +
    '\n';
  writeFileSync(path, body);
  return path;
}

describe('lifecycle / scan gating', () => {
  test('frontmatter lifecycle wins over body text', () => {
    expect(lifecycle('---\nlifecycle: draft\n---\nbody\n')).toBe('draft');
    expect(lifecycle('---\nlifecycle: reviewed\n---\nbody\n')).toBe('reviewed');
  });

  test('blockquote lifecycle outside frontmatter is detected', () => {
    expect(lifecycle('> lifecycle: verified\nhello')).toBe('verified');
  });

  test('no lifecycle => "none"', () => {
    expect(lifecycle('# no fm here')).toBe('none');
  });

  test('shouldScan skips draft, accepts none/reviewed/verified', () => {
    const draft = join(tmp, 'd.md');
    const review = join(tmp, 'r.md');
    writeFileSync(draft, '---\nlifecycle: draft\n---\n');
    writeFileSync(review, '---\nlifecycle: reviewed\n---\n');
    expect(shouldScan(draft)).toBe(false);
    expect(shouldScan(review)).toBe(true);
  });
});

describe('claim extraction', () => {
  test('parses key claim bullets with chunk ids', () => {
    const p = srcPage('alpha', [
      { text: 'attention is quadratic', id: 'a1b2c3d4' },
      { text: 'cache hit rates matter', id: 'deadbeef' },
    ]);
    const claims = extractClaims(p);
    expect(claims).toHaveLength(2);
    expect(claims[0]!.chunkId).toBe('c-a1b2c3d4');
    expect(claims[0]!.text).toBe('attention is quadratic');
    expect(claims[0]!.source).toBe('alpha');
  });

  test('crossSourcePairs ignores same-source pairs', () => {
    const claims = [
      { text: 'a', source: 'X', sourcePath: 'x', chunkId: 'c-1' },
      { text: 'b', source: 'X', sourcePath: 'x', chunkId: 'c-2' },
      { text: 'c', source: 'Y', sourcePath: 'y', chunkId: 'c-3' },
    ];
    const pairs = crossSourcePairs(claims);
    expect(pairs).toHaveLength(2);
    for (const [a, b] of pairs) expect(a.source).not.toBe(b.source);
  });
});

describe('findReferencedSources', () => {
  test('matches relative sources/<slug>.md links', () => {
    srcPage('alpha', []);
    srcPage('beta', []);
    const c = conceptPage('xforms', ['alpha', 'beta', 'missing']);
    const refs = findReferencedSources(c, tmp);
    const names = refs.map((p) => p.split('/').pop()).sort();
    expect(names).toEqual(['alpha.md', 'beta.md']);
  });
});

describe('heuristic comparator', () => {
  test('flags antonym pairs sharing topic', async () => {
    const a = { text: 'attention patterns are dense across tokens', source: 's1', sourcePath: '', chunkId: 'c-1' };
    const b = { text: 'attention patterns are sparse across tokens', source: 's2', sourcePath: '', chunkId: 'c-2' };
    expect(await heuristicComparator.compare(a, b)).toBe('disagree');
  });

  test('returns agree for aligned claims', async () => {
    const a = { text: 'attention is quadratic in tokens', source: 's1', sourcePath: '', chunkId: 'c-1' };
    const b = { text: 'attention scales quadratically with tokens', source: 's2', sourcePath: '', chunkId: 'c-2' };
    expect(await heuristicComparator.compare(a, b)).toBe('agree');
  });

  test('returns unknown when topic overlap is too small', async () => {
    const a = { text: 'unicorns gallop in the meadow', source: 's1', sourcePath: '', chunkId: 'c-1' };
    const b = { text: 'kernels schedule across cores', source: 's2', sourcePath: '', chunkId: 'c-2' };
    expect(await heuristicComparator.compare(a, b)).toBe('unknown');
  });

  test('flags negation asymmetry on shared topic', async () => {
    const a = { text: 'tokens are cached across requests', source: 's1', sourcePath: '', chunkId: 'c-1' };
    const b = { text: 'tokens are not cached across requests', source: 's2', sourcePath: '', chunkId: 'c-2' };
    expect(await heuristicComparator.compare(a, b)).toBe('disagree');
  });
});

describe('detectConflicts pipeline', () => {
  test('finds planted contradiction and writes report', async () => {
    const a = srcPage('paperA', [
      { text: 'attention patterns are dense across tokens', id: 'aaaaaaaa' },
    ]);
    const b = srcPage('paperB', [
      { text: 'attention patterns are sparse across tokens', id: 'bbbbbbbb' },
    ]);
    conceptPage('attention', ['paperA', 'paperB']);
    void a;
    void b;

    const result = await detectConflicts({ kbRoot: tmp, date: new Date('2026-05-21') });
    expect(result.findings).toHaveLength(1);
    expect(result.findings[0]!.concept).toBe('attention');
    expect(result.reportPath).toContain('contradictions-2026-05-21.md');
    const body = readFileSync(result.reportPath!, 'utf8');
    expect(body).toContain('## concept: attention.md');
    expect(body).toContain('c-aaaaaaaa');
    expect(body).toContain('c-bbbbbbbb');
  });

  test('emits "no contradictions" report when none found', async () => {
    srcPage('one', [{ text: 'cats purr softly', id: '11111111' }]);
    srcPage('two', [{ text: 'cats purr softly', id: '22222222' }]);
    conceptPage('cats', ['one', 'two']);
    const result = await detectConflicts({ kbRoot: tmp, date: new Date('2026-05-21') });
    expect(result.findings).toHaveLength(0);
    expect(readFileSync(result.reportPath!, 'utf8')).toContain('No contradictions found');
  });

  test('skips draft source pages', async () => {
    const a = srcPage('paperA', [
      { text: 'attention patterns are dense across tokens', id: 'aaaaaaaa' },
    ]);
    const b = srcPage('paperB', [
      { text: 'attention patterns are sparse across tokens', id: 'bbbbbbbb' },
    ]);
    // mark paperB draft
    writeFileSync(b, '---\nlifecycle: draft\n---\n' + readFileSync(b, 'utf8'));
    conceptPage('attention', ['paperA', 'paperB']);
    void a;
    const result = await detectConflicts({ kbRoot: tmp, date: new Date('2026-05-21') });
    expect(result.findings).toHaveLength(0);
  });

  test('skips when no concepts dir', async () => {
    rmSync(join(tmp, 'kb/wiki/concepts'), { recursive: true });
    const result = await detectConflicts({ kbRoot: tmp });
    expect(result.findings).toHaveLength(0);
    expect(result.reportPath).toBeNull();
  });

  test('llmComparator uses provider verdict', async () => {
    const provider: LLMProvider = {
      name: 'fake',
      async complete() {
        return 'DISAGREE';
      },
    };
    const cmp: ClaimComparator = llmComparator(provider);
    srcPage('paperA', [{ text: 'X is true', id: 'aaaaaaaa' }]);
    srcPage('paperB', [{ text: 'Y is false', id: 'bbbbbbbb' }]);
    conceptPage('thing', ['paperA', 'paperB']);
    const result = await detectConflicts({
      kbRoot: tmp,
      comparator: cmp,
      date: new Date('2026-05-21'),
    });
    expect(result.findings).toHaveLength(1);
  });
});

describe('renderReport', () => {
  test('groups findings by concept', () => {
    const findings: Finding[] = [
      {
        concept: 'b',
        claimA: { text: 't1', source: 'x', sourcePath: '', chunkId: 'c-1' },
        claimB: { text: 't2', source: 'y', sourcePath: '', chunkId: 'c-2' },
      },
      {
        concept: 'a',
        claimA: { text: 'u1', source: 'x', sourcePath: '', chunkId: 'c-3' },
        claimB: { text: 'u2', source: 'y', sourcePath: '', chunkId: 'c-4' },
      },
    ];
    const out = renderReport(findings, new Date('2026-05-21'));
    expect(out.indexOf('## concept: a.md')).toBeLessThan(out.indexOf('## concept: b.md'));
  });
});

// keep used import
void existsSync;
