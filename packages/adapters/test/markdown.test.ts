import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { markdownAdapter } from '../src/markdown.ts';

let tmp: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), 'kb-adapter-md-'));
  mkdirSync(join(tmp, 'kb/raw'), { recursive: true });
  mkdirSync(join(tmp, 'kb/wiki/sources'), { recursive: true });
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

function writeSource(rel: string, content: string): string {
  const full = join(tmp, rel);
  mkdirSync(join(tmp, rel.split('/').slice(0, -1).join('/') || '.'), { recursive: true });
  writeFileSync(full, content);
  return full;
}

describe('markdown adapter', () => {
  test('ingests a single .md file and writes the raw + source artifacts', async () => {
    const src = writeSource(
      'docs/auth.md',
      '# Auth\n\n## JWT\n\nstateless tokens.\n\n## Refresh\n\nlonger-lived.\n',
    );

    const results = await markdownAdapter.ingest(src, { kbRoot: tmp });

    expect(results).toHaveLength(1);
    const [entry] = results;
    expect(entry!.source.slug).toMatch(/auth\.md$/);
    // Two `## ` headings plus the leading `# Auth` preamble = 3 chunks.
    expect(entry!.source.chunks).toBe(3);

    const rawPath = join(tmp, 'kb/raw', entry!.source.slug);
    expect(existsSync(rawPath)).toBe(true);
    expect(readFileSync(rawPath, 'utf8')).toContain('## JWT');

    const sourcePagePath = join(
      tmp,
      'kb/wiki/sources',
      `${entry!.source.slug.replace(/\.md$/, '')}.md`,
    );
    expect(existsSync(sourcePagePath)).toBe(true);
    const pageBody = readFileSync(sourcePagePath, 'utf8');
    expect(pageBody).toContain('**Hash:**');
    expect(pageBody).toContain('<!-- human notes below -->');
  });
});
