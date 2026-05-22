import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { markdownAdapter } from '@kb/adapters';
import { detectConflicts, runExport, type ExportFormat } from '@kb/inferrers';
import { kbRootWithStatus, safePath } from './path-guard.ts';

export interface ToolDef {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
}

export type ToolResult =
  | { kind: 'ok'; text: string }
  | { kind: 'error'; message: string }
  | { kind: 'unknown_tool'; name: string };

export const TOOLS: ToolDef[] = [
  {
    name: 'kb_query',
    description:
      'Keyword search across kb/wiki/. Returns matching pages with a short snippet. No LLM synthesis.',
    inputSchema: {
      type: 'object',
      properties: {
        question: { type: 'string', description: 'Natural-language question or keyword(s).' },
        max_pages: { type: 'integer', description: 'Maximum pages returned.', default: 10 },
      },
      required: ['question'],
    },
  },
  {
    name: 'kb_search',
    description:
      'Literal substring search across kb/wiki/ (and optionally kb/raw/). Returns file:line matches.',
    inputSchema: {
      type: 'object',
      properties: {
        term: { type: 'string', description: 'Literal substring to grep for.' },
        include_raw: { type: 'boolean', description: 'Also search kb/raw/.', default: false },
      },
      required: ['term'],
    },
  },
  {
    name: 'kb_list_sources',
    description: 'List sources recorded in the KB manifest.',
    inputSchema: {
      type: 'object',
      properties: {
        project: { type: 'string', description: 'Optional project name to filter by.' },
      },
    },
  },
  {
    name: 'kb_read_page',
    description: 'Read a single page inside KB_ROOT. Path is validated to prevent traversal.',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Page path relative to KB_ROOT.' },
      },
      required: ['path'],
    },
  },
  {
    name: 'kb_lint',
    description: 'Run contradiction detection across reviewed concept pages.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'kb_ingest',
    description: 'Ingest a file or directory under KB_ROOT.',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Path to a file or directory under KB_ROOT.' },
      },
      required: ['path'],
    },
  },
  {
    name: 'kb_compile',
    description: '(Re)compile the wiki from raw sources. Pass dry_run=true to preview.',
    inputSchema: {
      type: 'object',
      properties: {
        dry_run: { type: 'boolean', description: 'Preview without writing.', default: false },
      },
    },
  },
  {
    name: 'kb_export',
    description:
      'Render the wiki: llms-txt | llms-full | jsonld | sitemap | all. Returns the written artifact paths.',
    inputSchema: {
      type: 'object',
      properties: {
        format: {
          type: 'string',
          enum: ['llms-txt', 'llms-full', 'jsonld', 'sitemap', 'all'],
        },
      },
      required: ['format'],
    },
  },
  {
    name: 'kb_dashboard',
    description: 'Compact dashboard: source count, concept count, generated ratio, last compiled.',
    inputSchema: { type: 'object', properties: {} },
  },
];

export const KNOWN_TOOL_NAMES = new Set(TOOLS.map((t) => t.name));

export async function callTool(
  name: string,
  args: Record<string, unknown>,
): Promise<ToolResult> {
  if (!KNOWN_TOOL_NAMES.has(name)) return { kind: 'unknown_tool', name };
  try {
    switch (name) {
      case 'kb_query':
        return await callKbQuery(args);
      case 'kb_search':
        return await callKbSearch(args);
      case 'kb_list_sources':
        return await callKbListSources(args);
      case 'kb_read_page':
        return await callKbReadPage(args);
      case 'kb_lint':
        return await callKbLint();
      case 'kb_ingest':
        return await callKbIngest(args);
      case 'kb_compile':
        return await callKbCompile(args);
      case 'kb_export':
        return await callKbExport(args);
      case 'kb_dashboard':
        return await callKbDashboard();
      default:
        return { kind: 'unknown_tool', name };
    }
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return { kind: 'error', message: `${name} failed: ${msg}` };
  }
}

// ─── Handlers ──────────────────────────────────────────────────────────

async function callKbQuery(args: Record<string, unknown>): Promise<ToolResult> {
  const question = typeof args.question === 'string' ? args.question.trim() : '';
  if (!question) return { kind: 'error', message: 'question is required' };
  const maxPages = toInt(args.max_pages, 10);
  const { root } = kbRootWithStatus();
  const needle = question.toLowerCase();
  const files = [
    ...mdFiles(join(root, 'kb/wiki/concepts')),
    ...mdFiles(join(root, 'kb/wiki/sources')),
  ];
  const matches: { path: string; snippet: string }[] = [];
  for (const path of files) {
    let content: string;
    try {
      content = readFileSync(path, 'utf8');
    } catch {
      continue;
    }
    if (content.toLowerCase().includes(needle)) {
      matches.push({ path, snippet: extractSnippet(content, needle) });
      if (matches.length >= maxPages) break;
    }
  }
  if (matches.length === 0) {
    return { kind: 'ok', text: `No matches found for "${question}".` };
  }
  const body = matches
    .map((m) => `- ${relative(root, m.path)}\n  ${m.snippet}`)
    .join('\n\n');
  return {
    kind: 'ok',
    text: `# kb_query: ${question}\n\n${matches.length} matching pages.\n\n${body}`,
  };
}

async function callKbSearch(args: Record<string, unknown>): Promise<ToolResult> {
  const term = typeof args.term === 'string' ? args.term : '';
  if (!term) return { kind: 'error', message: 'term is required' };
  const includeRaw = args.include_raw === true;
  const { root } = kbRootWithStatus();
  const dirs = includeRaw ? ['kb/wiki', 'kb/raw'] : ['kb/wiki'];
  const needle = term.toLowerCase();
  const hits: string[] = [];
  for (const d of dirs) {
    for (const file of mdFiles(join(root, d))) {
      let content: string;
      try {
        content = readFileSync(file, 'utf8');
      } catch {
        continue;
      }
      const rel = relative(root, file);
      const lines = content.split('\n');
      for (let i = 0; i < lines.length; i++) {
        if (lines[i]!.toLowerCase().includes(needle)) {
          hits.push(`${rel}:${i + 1}: ${lines[i]!.trim()}`);
          if (hits.length >= 200) break;
        }
      }
      if (hits.length >= 200) break;
    }
  }
  if (hits.length === 0) return { kind: 'ok', text: `No matches for "${term}".` };
  return { kind: 'ok', text: `# kb_search: ${term}\n\n${hits.join('\n')}` };
}

async function callKbListSources(args: Record<string, unknown>): Promise<ToolResult> {
  const { root } = kbRootWithStatus();
  const manifest = readManifest(root);
  if (!manifest) return { kind: 'error', message: `no KB found at ${root} — run \`kb init\`` };
  const project = typeof args.project === 'string' ? args.project : null;
  if (project && manifest.name !== project) {
    return {
      kind: 'ok',
      text: `No sources for project "${project}" (manifest name is "${manifest.name}").`,
    };
  }
  const payload = {
    project: manifest.name,
    count: manifest.sources?.length ?? 0,
    sources: manifest.sources ?? [],
  };
  return { kind: 'ok', text: JSON.stringify(payload, null, 2) };
}

async function callKbReadPage(args: Record<string, unknown>): Promise<ToolResult> {
  const sp = safePath(args.path);
  if (!sp.ok) return { kind: 'error', message: sp.reason };
  if (!existsSync(sp.absolute)) return { kind: 'error', message: `file not found: ${args.path}` };
  const st = statSync(sp.absolute);
  if (st.isDirectory()) return { kind: 'error', message: `path is a directory: ${args.path}` };
  const content = readFileSync(sp.absolute, 'utf8');
  const cap = 200 * 1024;
  if (Buffer.byteLength(content, 'utf8') > cap) {
    return {
      kind: 'ok',
      text:
        content.slice(0, cap) +
        `\n\n…(truncated at ${cap} bytes; full file is ${Buffer.byteLength(content, 'utf8')} bytes)`,
    };
  }
  return { kind: 'ok', text: content };
}

async function callKbLint(): Promise<ToolResult> {
  const { root, status } = kbRootWithStatus();
  if (status !== 'found') {
    return {
      kind: 'error',
      message: 'no KB found (looked up from cwd for kb/.kb-manifest.json). Run `kb init` first.',
    };
  }
  const result = await detectConflicts({ kbRoot: root });
  const head = `# kb_lint --conflicts\n\n${result.findings.length} contradiction(s) found.\n`;
  if (!result.reportPath) return { kind: 'ok', text: head };
  return {
    kind: 'ok',
    text: head + `\nReport: ${result.reportPath}\n\n` + readFileSync(result.reportPath, 'utf8'),
  };
}

async function callKbIngest(args: Record<string, unknown>): Promise<ToolResult> {
  const path = typeof args.path === 'string' ? args.path : '';
  if (!path) return { kind: 'error', message: 'path is required' };
  if (/^https?:\/\//.test(path)) {
    return {
      kind: 'ok',
      text: 'URL ingest is not implemented in the CLI. Use the Claude Code skill for URL sources.',
    };
  }
  const sp = safePath(path);
  if (!sp.ok) return { kind: 'error', message: sp.reason };
  const { root, status } = kbRootWithStatus();
  if (status !== 'found') {
    return { kind: 'error', message: `no KB found at ${root} — run \`kb init\` first` };
  }
  const results = await markdownAdapter.ingest(sp.absolute, { kbRoot: root });
  return {
    kind: 'ok',
    text: `Ingested ${results.length} source(s):\n${results.map((r) => `- ${r.source.slug}`).join('\n')}`,
  };
}

async function callKbCompile(args: Record<string, unknown>): Promise<ToolResult> {
  const dryRun = args.dry_run === true;
  const { root, status } = kbRootWithStatus();
  if (status !== 'found') {
    return { kind: 'error', message: `no KB found at ${root} — run \`kb init\` first` };
  }
  const manifest = readManifest(root);
  const sourceCount = manifest?.sources?.length ?? 0;
  if (dryRun) {
    return {
      kind: 'ok',
      text: `dry_run: would compile ${sourceCount} sources from ${root}. Pass dry_run=false to actually compile.`,
    };
  }
  // Full compile lives in @kb/inferrers/compile but requires LLM provider wiring.
  // Surface a structured next-step message rather than running an LLM call here.
  return {
    kind: 'ok',
    text:
      `kb_compile: ${sourceCount} sources in manifest. ` +
      `Programmatic compile requires an LLMProvider; invoke runCompile() from @kb/inferrers with a configured provider.`,
  };
}

async function callKbExport(args: Record<string, unknown>): Promise<ToolResult> {
  const format = args.format;
  const valid: ExportFormat[] = ['llms-txt', 'llms-full', 'jsonld', 'sitemap', 'all'];
  if (typeof format !== 'string' || !(valid as string[]).includes(format)) {
    return {
      kind: 'error',
      message: `unknown format: ${format} (expected: ${valid.join('|')})`,
    };
  }
  const { root, status } = kbRootWithStatus();
  if (status !== 'found') {
    return { kind: 'error', message: `no KB found at ${root} — run \`kb init\` first` };
  }
  const result = await runExport({ kbRoot: root, format: format as ExportFormat });
  return { kind: 'ok', text: `Wrote ${result.paths.length} artifact(s):\n${result.paths.join('\n')}` };
}

async function callKbDashboard(): Promise<ToolResult> {
  const { root } = kbRootWithStatus();
  const manifest = readManifest(root);
  if (!manifest) return { kind: 'error', message: `no KB found at ${root} — run \`kb init\` first` };
  const sources = manifest.sources ?? [];
  const total = sources.length;
  const generated = sources.filter((s) => s.generated === true).length;
  const concepts = mdFiles(join(root, 'kb/wiki/concepts')).length;
  const payload = {
    project: manifest.name,
    last_compiled: manifest.lastCompiled ?? null,
    sources: total,
    generated_sources: generated,
    generated_ratio: total > 0 ? Math.round((generated / total) * 100) / 100 : 0,
    concepts,
  };
  return { kind: 'ok', text: JSON.stringify(payload, null, 2) };
}

// ─── Helpers ───────────────────────────────────────────────────────────

interface ManifestShape {
  name: string;
  lastCompiled?: string | null;
  sources?: { generated?: boolean }[];
}

function readManifest(root: string): ManifestShape | null {
  const path = join(root, 'kb/.kb-manifest.json');
  if (!existsSync(path)) return null;
  try {
    return JSON.parse(readFileSync(path, 'utf8')) as ManifestShape;
  } catch {
    return null;
  }
}

function mdFiles(dir: string): string[] {
  if (!existsSync(dir)) return [];
  let entries: import('node:fs').Dirent[];
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return [];
  }
  const out: string[] = [];
  for (const e of entries) {
    const full = join(dir, e.name);
    if (e.isDirectory()) out.push(...mdFiles(full));
    else if (e.isFile() && full.endsWith('.md')) out.push(full);
  }
  return out;
}

function extractSnippet(content: string, needle: string): string {
  const idx = content.toLowerCase().indexOf(needle);
  if (idx < 0) return content.slice(0, 120).replace(/\s+/g, ' ');
  const start = Math.max(idx - 60, 0);
  const end = Math.min(idx + needle.length + 60, content.length);
  return content.slice(start, end).replace(/\s+/g, ' ').trim();
}

function toInt(v: unknown, fallback: number): number {
  if (typeof v === 'number' && Number.isFinite(v)) return Math.trunc(v);
  if (typeof v === 'string') {
    const n = parseInt(v, 10);
    return Number.isFinite(n) ? n : fallback;
  }
  return fallback;
}
