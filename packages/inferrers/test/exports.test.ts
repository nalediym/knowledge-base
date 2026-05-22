import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { collectPages, runExport, toPlainText, writeSiblings } from '../src/exports.ts';

let tmp: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), 'kb-exports-'));
  mkdirSync(join(tmp, 'kb/wiki/concepts'), { recursive: true });
  mkdirSync(join(tmp, 'kb/wiki/sources'), { recursive: true });
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

function write(rel: string, content: string) {
  const full = join(tmp, 'kb/wiki', rel);
  mkdirSync(join(full, '..'), { recursive: true });
  writeFileSync(full, content);
  return full;
}

describe('collectPages', () => {
  test('categorises pages by directory', () => {
    write('index.md', '# Index\n\nLLM-compiled wiki for the team.\n');
    write('concepts/attention.md', '# Attention\n\nMechanism over tokens.\n');
    write('sources/paper.md', '# Paper\n\n## Key Claims\n\n- foo — c-12345678\n');

    const pages = collectPages(join(tmp, 'kb/wiki'));
    expect(pages).toHaveLength(3);
    const byCat = Object.fromEntries(pages.map((p) => [p.relPath, p.category]));
    expect(byCat['index.md']).toBe('index');
    expect(byCat['concepts/attention.md']).toBe('concept');
    expect(byCat['sources/paper.md']).toBe('source');
  });
});

describe('toPlainText', () => {
  test('strips html, fences, images, links, emphasis, inline code', () => {
    const md = '<!-- hi -->\n```ts\nconst x = 1;\n```\n\n![alt](img.png) and [link](x.md) and **bold** and `code`.\n';
    const out = toPlainText(md);
    expect(out).not.toContain('<!--');
    expect(out).not.toContain('```');
    expect(out).toContain('alt');
    expect(out).toContain('link');
    expect(out).toContain('bold');
    expect(out).toContain('code');
  });
});

describe('runExport llms-txt', () => {
  test('emits sections grouped by category with summaries', async () => {
    write('index.md', '# Knowledge Base\n\nA compiled wiki of design notes.\n');
    write('concepts/attention.md', '# Attention\n\nMechanism that weights tokens.\n');
    write('sources/paper.md', '# Paper\n\nA short summary line about the paper.\n');

    const r = await runExport({ kbRoot: tmp, format: 'llms-txt' });
    expect(r.paths).toHaveLength(1);
    const body = readFileSync(r.paths[0]!, 'utf8');
    expect(body.startsWith('# Knowledge Base')).toBe(true);
    expect(body).toContain('## Concepts');
    expect(body).toContain('## Sources');
    expect(body).toContain('[Attention](concepts/attention.md)');
  });
});

describe('runExport jsonld', () => {
  test('emits @graph with kb:// ids and resolved related links', async () => {
    write('index.md', '# Index\n\nbody.\n');
    write('concepts/attention.md', '# Attention\n\nSee [Paper](../sources/paper.md).\n');
    write('sources/paper.md', '# Paper\n\nbody.\n');

    const r = await runExport({ kbRoot: tmp, format: 'jsonld' });
    const doc = JSON.parse(readFileSync(r.paths[0]!, 'utf8'));
    expect(doc['@context']).toBe('https://schema.org');
    const attention = doc['@graph'].find((n: { '@id': string }) =>
      n['@id'].endsWith('attention.md'),
    );
    expect(attention['@type']).toBe('DefinedTerm');
    expect(attention.isRelatedTo[0]['@id']).toBe('kb://sources/paper.md');
  });
});

describe('runExport sitemap', () => {
  test('xml-escapes locs and lists each page', async () => {
    write('index.md', '# i\n\nb\n');
    write('concepts/a&b.md', '# a&b\n\nb\n');
    const r = await runExport({ kbRoot: tmp, format: 'sitemap', siteBase: 'https://kb.test' });
    const body = readFileSync(r.paths[0]!, 'utf8');
    expect(body).toContain('<urlset');
    expect(body).toContain('https://kb.test/index.md');
    expect(body).toContain('a&amp;b.md');
  });
});

describe('runExport llms-full', () => {
  test('flattens all pages with banner separators', async () => {
    write('index.md', '# Index\n\nbody.\n');
    write('concepts/x.md', '# X\n\nbody-of-X.\n');
    const r = await runExport({ kbRoot: tmp, format: 'llms-full' });
    const body = readFileSync(r.paths[0]!, 'utf8');
    expect(body).toContain('# Index');
    expect(body).toContain('# X');
    expect(body).toContain('body-of-X');
  });
});

describe('runExport all', () => {
  test('writes all four artifacts', async () => {
    write('index.md', '# i\n\nb\n');
    const r = await runExport({ kbRoot: tmp, format: 'all' });
    expect(r.paths).toHaveLength(4);
    for (const p of r.paths) expect(existsSync(p)).toBe(true);
  });
});

describe('writeSiblings', () => {
  test('emits .txt and .json sibling for each page', () => {
    write('index.md', '# Index\n\nbody.\n');
    const out = writeSiblings({ kbRoot: tmp });
    expect(out).toHaveLength(2);
    expect(out.some((p) => p.endsWith('.txt'))).toBe(true);
    expect(out.some((p) => p.endsWith('.json'))).toBe(true);
    const json = JSON.parse(readFileSync(out.find((p) => p.endsWith('.json'))!, 'utf8'));
    expect(json.title).toBe('Index');
  });
});
