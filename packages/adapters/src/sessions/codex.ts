import { existsSync, readFileSync, readdirSync } from 'node:fs';
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

const ROOTS = [
  join(homedir(), '.codex', 'sessions'),
  join(homedir(), '.codex', 'projects'),
];

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

export const codexAdapter: SessionAdapter = {
  agentName: 'codex_cli',

  detect(): DetectResult {
    const present = ROOTS.filter((r) => existsSync(r));
    if (present.length === 0) return { kind: 'not_installed' };
    const files = new Set<string>();
    for (const r of present) for (const f of walkJsonl(r)) files.add(f);
    return { kind: 'ok', files: [...files].sort() };
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
      } catch {}
    }

    const meta = records.find((r) => r['type'] === 'session_meta') ?? {};
    const metaPayload = (meta['payload'] as Record<string, unknown> | undefined) ?? {};
    const sessionId =
      (metaPayload['id'] as string | undefined) ?? uuidFromPath(path);
    const cwd = (metaPayload['cwd'] as string | undefined) ?? '';
    const startedAt =
      (meta['timestamp'] as string | undefined) ?? findFirstTimestamp(records);
    const model = extractModel(records);
    const messages = records.flatMap(recordToMessages);

    return {
      ok: true,
      doc: {
        agent: 'codex_cli',
        project: projectSlug(cwd, path),
        sessionId,
        sourcePath: path,
        ...(startedAt !== undefined ? { startedAt } : {}),
        ...(model !== undefined ? { model } : {}),
        messages,
        metadata: { recordCount: records.length },
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

function findFirstTimestamp(records: Record<string, unknown>[]): string | undefined {
  for (const r of records) {
    if (typeof r['timestamp'] === 'string') return r['timestamp'] as string;
  }
  return undefined;
}

function extractModel(records: Record<string, unknown>[]): string | undefined {
  for (const r of records) {
    if (r['type'] === 'turn_context') {
      const payload = r['payload'] as { model?: unknown } | undefined;
      if (payload && typeof payload.model === 'string') return payload.model;
    }
  }
  return undefined;
}

function recordToMessages(r: Record<string, unknown>): SessionMessage[] {
  if (r['type'] !== 'response_item') return [];
  const payload = r['payload'] as Record<string, unknown> | undefined;
  if (!payload) return [];
  const role = String(payload['role'] ?? '');
  const itemType = String(payload['type'] ?? '');
  const content = payload['content'];
  const ts = typeof r['timestamp'] === 'string' ? (r['timestamp'] as string) : undefined;

  const tsField = ts !== undefined ? { timestamp: ts } : {};
  if (role === 'user' && itemType === 'message') {
    const text = codexContentText(content, 'input_text');
    return text ? [{ role: 'user', content: text, ...tsField }] : [];
  }
  if (role === 'assistant' && itemType === 'message') {
    const text = codexContentText(content, 'output_text');
    return text ? [{ role: 'assistant', content: text, ...tsField }] : [];
  }
  if (itemType === 'web_search_call') {
    const query = String(payload['query'] ?? '');
    return [{ role: 'assistant', content: `\`[tool: WebSearch]\` ${query}`, ...tsField }];
  }
  return [];
}

function codexContentText(blocks: unknown, expectedType: string): string {
  if (typeof blocks === 'string') return blocks.trim();
  if (!Array.isArray(blocks)) return '';
  return blocks
    .map((b) => {
      if (typeof b === 'string') return b;
      if (b && typeof b === 'object' && (b as { type?: string }).type === expectedType) {
        const t = (b as { text?: unknown }).text;
        if (typeof t === 'string') return t;
      }
      return '';
    })
    .filter((s) => s !== '')
    .join('\n')
    .trim();
}

function projectSlug(cwd: string, path: string): string {
  if (cwd) return slugify(basename(cwd));
  return slugify(basename(dirname(path)));
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
