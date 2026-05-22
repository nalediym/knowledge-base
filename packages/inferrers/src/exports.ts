import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, posix, relative, resolve } from 'node:path';
import { chunkByHeading, type Chunk } from '@kb/core';

const LLMS_FULL_CAP = 5 * 1024 * 1024;
const SITE_BASE = 'https://example.invalid';

export type ExportFormat = 'llms-txt' | 'llms-full' | 'jsonld' | 'sitemap' | 'all';

export interface ExportOpts {
  kbRoot: string;
  format: ExportFormat;
  wikiDir?: string;
  outputDir?: string;
  siteBase?: string;
}

export interface ExportResult {
  paths: string[];
}

export interface Page {
  path: string;
  relPath: string;
  title: string;
  category: 'concept' | 'source' | 'candidate' | 'index' | 'page';
  body: string;
  frontmatter: Record<string, string>;
  summary: string;
  mtime: string;
  chunks: Chunk[];
}

export async function runExport(opts: ExportOpts): Promise<ExportResult> {
  const wikiDir = opts.wikiDir ?? join(opts.kbRoot, 'kb/wiki');
  const outputDir = opts.outputDir ?? join(opts.kbRoot, 'kb/output');
  const siteBase = opts.siteBase ?? SITE_BASE;
  mkdirSync(outputDir, { recursive: true });
  const pages = collectPages(wikiDir);

  switch (opts.format) {
    case 'llms-txt':
      return { paths: [writeLlmsTxt(pages, outputDir)] };
    case 'llms-full':
      return { paths: [writeLlmsFull(pages, outputDir)] };
    case 'jsonld':
      return { paths: [writeJsonLd(pages, outputDir, siteBase)] };
    case 'sitemap':
      return { paths: [writeSitemap(pages, outputDir, siteBase)] };
    case 'all':
      return {
        paths: [
          writeLlmsTxt(pages, outputDir),
          writeLlmsFull(pages, outputDir),
          writeJsonLd(pages, outputDir, siteBase),
          writeSitemap(pages, outputDir, siteBase),
        ],
      };
  }
}

export function writeSiblings(opts: { kbRoot: string; wikiDir?: string }): string[] {
  const wikiDir = opts.wikiDir ?? join(opts.kbRoot, 'kb/wiki');
  const pages = collectPages(wikiDir);
  const out: string[] = [];
  for (const page of pages) {
    const stem = page.path.slice(0, page.path.length - 3);
    const txt = stem + '.txt';
    const json = stem + '.json';
    writeFileSync(txt, toPlainText(page.body));
    writeFileSync(json, pageToJson(page));
    out.push(txt, json);
  }
  return out;
}

// ─── page collection ───────────────────────────────────────────────────

export function collectPages(wikiDir: string): Page[] {
  if (!existsSync(wikiDir)) return [];
  const files = walkMd(wikiDir).sort();
  return files.map((p) => readPage(p, wikiDir));
}

function walkMd(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walkMd(full));
    else if (entry.isFile() && full.endsWith('.md')) out.push(full);
  }
  return out;
}

function readPage(path: string, wikiDir: string): Page {
  const body = readFileSync(path, 'utf8');
  const { frontmatter, body: bodyNoFm } = splitFrontmatter(body);
  const title = extractTitle(bodyNoFm) ?? basename(path, '.md');
  const relPath = relative(wikiDir, path).split('\\').join('/');
  return {
    path,
    relPath,
    title,
    category: pageCategory(relPath),
    body: bodyNoFm,
    frontmatter,
    summary: extractSummary(bodyNoFm),
    mtime: fileMtime(path),
    chunks: chunkByHeading(bodyNoFm),
  };
}

function pageCategory(rel: string): Page['category'] {
  if (rel.startsWith('concepts/')) return 'concept';
  if (rel.startsWith('sources/')) return 'source';
  if (rel.startsWith('candidates/')) return 'candidate';
  if (rel === 'index.md') return 'index';
  return 'page';
}

function splitFrontmatter(content: string): { frontmatter: Record<string, string>; body: string } {
  if (!content.startsWith('---\n')) return { frontmatter: {}, body: content };
  const rest = content.slice(4);
  const end = rest.indexOf('\n---\n');
  if (end === -1) return { frontmatter: {}, body: content };
  const fmRaw = rest.slice(0, end);
  const body = rest.slice(end + 5);
  const fm: Record<string, string> = {};
  for (const line of fmRaw.split('\n')) {
    const m = /^([A-Za-z0-9_-]+)\s*:\s*(.*)$/.exec(line);
    if (m) fm[m[1]!] = stripQuotes(m[2]!.trim());
  }
  return { frontmatter: fm, body };
}

function stripQuotes(s: string): string {
  if ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'"))) {
    return s.slice(1, -1);
  }
  return s;
}

function extractTitle(body: string): string | null {
  const m = /^#\s+(.+)$/m.exec(body);
  return m ? m[1]!.trim() : null;
}

function extractSummary(body: string): string {
  const summaryMatch = /(?:^|\n)##\s+Summary\s*\n([\s\S]*?)(?=\n##\s|$)/.exec(body);
  if (summaryMatch) return firstParagraph(summaryMatch[1]!.trim());
  for (const p of body.split('\n\n').map((s) => s.trim())) {
    if (!p) continue;
    if (p.startsWith('#') || p.startsWith('>') || p.startsWith('<!--')) continue;
    return firstParagraph(p);
  }
  return '';
}

function firstParagraph(str: string): string {
  const first = str.split('\n\n')[0] ?? '';
  const collapsed = first.replace(/\s+/g, ' ').trim();
  return truncate(collapsed, 280);
}

function truncate(str: string, max: number): string {
  if (str.length > max) return str.slice(0, max - 1) + '…';
  return str;
}

function fileMtime(path: string): string {
  try {
    return statSync(path).mtime.toISOString();
  } catch {
    return new Date().toISOString();
  }
}

// ─── llms.txt ──────────────────────────────────────────────────────────

const SECTION_ORDER: Page['category'][] = ['concept', 'source', 'candidate', 'page'];
const SECTION_HEADINGS: Record<string, string> = {
  concept: 'Concepts',
  source: 'Sources',
  candidate: 'Candidates',
  page: 'Pages',
};

function writeLlmsTxt(pages: Page[], outputDir: string): string {
  const { title, summary } = indexMeta(pages);
  const grouped = new Map<Page['category'], Page[]>();
  for (const p of pages) {
    if (p.category === 'index') continue;
    const list = grouped.get(p.category) ?? [];
    list.push(p);
    grouped.set(p.category, list);
  }

  const head = `# ${title}\n\n> ${summary}\n`;
  const sections: string[] = [];
  for (const cat of SECTION_ORDER) {
    const entries = grouped.get(cat);
    if (!entries) continue;
    const sorted = [...entries].sort((a, b) => a.title.localeCompare(b.title));
    const lines = sorted
      .map((p) => `- [${p.title}](${p.relPath})${p.summary ? `: ${p.summary}` : ''}`)
      .join('\n');
    sections.push(`\n## ${SECTION_HEADINGS[cat]}\n\n${lines}\n`);
  }

  const path = join(outputDir, 'llms.txt');
  writeFileSync(path, head + sections.join(''));
  return path;
}

function indexMeta(pages: Page[]): { title: string; summary: string } {
  const idx = pages.find((p) => p.category === 'index');
  if (!idx) return { title: 'Knowledge Base', summary: 'LLM-compiled knowledge base' };
  const summary = extractSummary(idx.body);
  return {
    title: idx.title,
    summary: summary || 'LLM-compiled knowledge base',
  };
}

// ─── llms-full.txt ─────────────────────────────────────────────────────

function writeLlmsFull(pages: Page[], outputDir: string): string {
  const truncationNote = `\n\n<!-- llms-full truncated at ${LLMS_FULL_CAP} bytes -->\n`;
  let size = 0;
  let truncated = false;
  const parts: string[] = [];
  for (const page of pages) {
    if (truncated) break;
    const piece =
      `====================\n` +
      `# ${page.title}\n` +
      `Path: ${page.relPath}\n` +
      `Category: ${page.category}\n` +
      `====================\n\n` +
      `${toPlainText(page.body)}\n\n`;
    const pieceSize = Buffer.byteLength(piece, 'utf8');
    if (size + pieceSize > LLMS_FULL_CAP) {
      truncated = true;
      break;
    }
    parts.push(piece);
    size += pieceSize;
  }
  let payload = parts.join('');
  if (truncated) payload += truncationNote;
  const path = join(outputDir, 'llms-full.txt');
  writeFileSync(path, payload);
  return path;
}

// ─── graph.jsonld ──────────────────────────────────────────────────────

function writeJsonLd(pages: Page[], outputDir: string, siteBase: string): string {
  const nodes = pages.map((p) => pageToJsonLdNode(p, siteBase));
  const doc = {
    '@context': 'https://schema.org',
    '@graph': nodes,
  };
  const path = join(outputDir, 'graph.jsonld');
  writeFileSync(path, JSON.stringify(doc, null, 2) + '\n');
  return path;
}

function pageToJsonLdNode(page: Page, siteBase: string): Record<string, unknown> {
  const type =
    page.category === 'concept' || page.category === 'candidate'
      ? 'DefinedTerm'
      : page.category === 'source'
        ? 'CreativeWork'
        : page.category === 'index'
          ? 'CollectionPage'
          : 'Article';

  const base: Record<string, unknown> = {
    '@id': 'kb://' + page.relPath,
    '@type': type,
    name: page.title,
    url: siteBase.replace(/\/$/, '') + '/' + page.relPath,
    dateModified: page.mtime,
    category: page.category,
  };
  if (page.summary) base.description = page.summary;

  const related = extractMarkdownLinks(page.body).map((href) => ({
    '@id': linkToId(page, href),
  }));
  if (related.length) base.isRelatedTo = related;
  return base;
}

function linkToId(page: Page, href: string): string {
  if (/^https?:/.test(href)) return href;
  const baseDir = dirname(page.relPath);
  const resolved = posix.normalize(posix.join(baseDir, href)).replace(/^\.\//, '');
  return 'kb://' + resolved;
}

function extractMarkdownLinks(body: string): string[] {
  const re = /\[[^\]]+\]\(([^)]+\.md)\)/g;
  const seen = new Set<string>();
  let m: RegExpExecArray | null;
  while ((m = re.exec(body)) !== null) seen.add(m[1]!);
  return [...seen];
}

// ─── sitemap.xml ───────────────────────────────────────────────────────

function writeSitemap(pages: Page[], outputDir: string, siteBase: string): string {
  const urls = pages
    .map(
      (p) =>
        `  <url>\n    <loc>${xmlEscape(siteBase.replace(/\/$/, '') + '/' + p.relPath)}</loc>\n    <lastmod>${xmlEscape(p.mtime)}</lastmod>\n  </url>`,
    )
    .join('\n');
  const doc =
    `<?xml version="1.0" encoding="UTF-8"?>\n` +
    `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n` +
    `${urls}\n` +
    `</urlset>\n`;
  const path = join(outputDir, 'sitemap.xml');
  writeFileSync(path, doc);
  return path;
}

function xmlEscape(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

// ─── plain-text conversion ─────────────────────────────────────────────

export function toPlainText(body: string): string {
  return body
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/```[a-zA-Z0-9_\-]*\n?/g, '')
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/(\*\*|__)(.*?)\1/g, '$2')
    .replace(/(\*|_)(.*?)\1/g, '$2')
    .replace(/`([^`]+)`/g, '$1')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function pageToJson(page: Page): string {
  return (
    JSON.stringify(
      {
        path: page.relPath,
        title: page.title,
        category: page.category,
        frontmatter: page.frontmatter,
        summary: page.summary,
        lastmod: page.mtime,
        body: page.body,
        chunks: page.chunks.map((c) => ({
          id: c.id,
          heading: c.heading,
          content: c.content,
        })),
      },
      null,
      2,
    ) + '\n'
  );
}

// keep `resolve` exported for type-resolution
void resolve;
