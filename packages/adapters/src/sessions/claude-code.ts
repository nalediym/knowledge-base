import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { basename, dirname, extname, join } from 'node:path';
import { homedir } from 'node:os';
import { redact } from './redactor.ts';
import type {
  DetectResult,
  ParseResult,
  SessionAdapter,
  SessionDoc,
  SessionMessage,
  RedactOpts,
} from './types.ts';

const STORE = join(homedir(), '.claude', 'projects');

function walkJsonl(dir: string): string[] {
  const out: string[] = [];
  let entries: import('node:fs').Dirent[];
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    const full = join(dir, e.name);
    if (e.isDirectory()) {
      out.push(...walkJsonl(full));
    } else if (e.isFile() && full.endsWith('.jsonl')) {
      out.push(full);
    }
  }
  return out;
}

export const claudeCodeAdapter: SessionAdapter = {
  agentName: 'claude_code',

  detect(): DetectResult {
    if (!existsSync(STORE)) return { kind: 'not_installed' };
    return { kind: 'ok', files: walkJsonl(STORE).sort() };
  },

  parse(path: string): ParseResult {
    let raw: string;
    try {
      raw = readFileSync(path, 'utf8');
    } catch (e) {
      return { ok: false, reason: String(e) };
    }
    const records: Record<string, unknown>[] = [];
    for (const line of raw.split('\n')) {
      if (!line.trim()) continue;
      try {
        const parsed = JSON.parse(line);
        if (parsed && typeof parsed === 'object') records.push(parsed);
      } catch {
        // skip malformed lines
      }
    }

    const sessionId =
      (findFirst(records, 'sessionId') as string | undefined) ?? uuidFromPath(path);
    const cwd = (findFirst(records, 'cwd') as string | undefined) ?? '';
    const startedAt = findFirst(records, 'timestamp') as string | undefined;
    const model = findModel(records);
    const messages = records.flatMap(recordToMessages);

    return {
      ok: true,
      doc: {
        agent: 'claude_code',
        project: projectSlugFromPath(path, cwd),
        sessionId,
        sourcePath: path,
        startedAt,
        model,
        messages,
        metadata: {
          subagent: isSubagent(path),
          recordCount: records.length,
        },
      },
    };
  },

  redact(doc: SessionDoc, opts: RedactOpts = {}): SessionDoc {
    return {
      ...doc,
      messages: doc.messages.map((m) => ({ ...m, content: redact(m.content, opts) })),
    };
  },
};

function findFirst(records: Record<string, unknown>[], key: string): unknown {
  for (const r of records) {
    if (r[key] != null) return r[key];
  }
  return undefined;
}

function findModel(records: Record<string, unknown>[]): string | undefined {
  for (const r of records) {
    const msg = r['message'];
    if (msg && typeof msg === 'object' && 'model' in msg) {
      const m = (msg as { model?: unknown }).model;
      if (typeof m === 'string') return m;
    }
  }
  return undefined;
}

function recordToMessages(r: Record<string, unknown>): SessionMessage[] {
  const type = r['type'];
  const msg = r['message'];
  if (type !== 'user' && type !== 'assistant') return [];
  if (!msg || typeof msg !== 'object') return [];
  const message = msg as { content?: unknown; model?: unknown };
  const text = extractText(message.content);
  if (!text) return [];
  return [
    {
      role: type as 'user' | 'assistant',
      content: text,
      timestamp: typeof r['timestamp'] === 'string' ? (r['timestamp'] as string) : undefined,
      model: typeof message.model === 'string' ? message.model : undefined,
    },
  ];
}

function extractText(content: unknown): string {
  if (typeof content === 'string') return content.trim();
  if (Array.isArray(content)) {
    return content.map(blockToText).filter((s) => s !== '').join('\n\n').trim();
  }
  return '';
}

function blockToText(block: unknown): string {
  if (!block || typeof block !== 'object') return '';
  const b = block as Record<string, unknown>;
  const type = b.type;
  if (type === 'text' && typeof b.text === 'string') return b.text;
  if (type === 'thinking') return '';
  if (type === 'tool_use' && typeof b.name === 'string') {
    try {
      return `\`[tool: ${b.name}]\` \`${JSON.stringify(b.input ?? {})}\``;
    } catch {
      return `\`[tool: ${b.name}]\``;
    }
  }
  if (type === 'tool_result') {
    if (typeof b.content === 'string') return '```tool-result\n' + b.content + '\n```';
    if (Array.isArray(b.content)) return extractText(b.content);
  }
  if (typeof b.text === 'string') return b.text;
  return '';
}

function projectSlugFromPath(path: string, cwd: string): string {
  if (cwd) return slugify(basename(cwd));
  return slugify(decodeProjectDir(basename(dirname(path))));
}

function decodeProjectDir(name: string): string {
  if (name.startsWith('-')) {
    const parts = name.slice(1).split('-');
    return parts[parts.length - 1] ?? '';
  }
  return name;
}

function slugify(s: string | null | undefined): string {
  if (!s) return 'unknown-project';
  const slug = s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  return slug || 'unknown-project';
}

function uuidFromPath(path: string): string {
  const base = basename(path);
  return base.slice(0, base.length - extname(base).length);
}

function isSubagent(path: string): boolean {
  return path.includes('subagents/') || basename(path).startsWith('agent-');
}

// keep statSync import live for tree-shaking-resistant typing
void statSync;
