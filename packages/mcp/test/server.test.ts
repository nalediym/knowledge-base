import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { handleLine, handleRequest, PROTOCOL_VERSION, TOOLS } from '../src/index.ts';
import { kbRootWithStatus, safePath } from '../src/path-guard.ts';
import { newManifest, writeManifest } from '@kb/core';

let tmp: string;
let savedRoot: string | undefined;

beforeEach(async () => {
  tmp = mkdtempSync(join(tmpdir(), 'kb-mcp-'));
  mkdirSync(join(tmp, 'kb/wiki/concepts'), { recursive: true });
  mkdirSync(join(tmp, 'kb/wiki/sources'), { recursive: true });
  mkdirSync(join(tmp, 'kb/raw'), { recursive: true });
  const m = newManifest('proj');
  await writeManifest(tmp, m);
  savedRoot = process.env.KB_ROOT;
  process.env.KB_ROOT = tmp;
});

afterEach(() => {
  if (savedRoot === undefined) delete process.env.KB_ROOT;
  else process.env.KB_ROOT = savedRoot;
  rmSync(tmp, { recursive: true, force: true });
});

describe('initialize / tools/list / ping', () => {
  test('initialize returns protocol version + serverInfo', async () => {
    const res = await handleRequest({ jsonrpc: '2.0', id: 1, method: 'initialize' });
    expect(res?.result).toMatchObject({
      protocolVersion: PROTOCOL_VERSION,
      serverInfo: { name: 'kb' },
    });
  });

  test('tools/list returns all 9 kb_* tools', async () => {
    const res = await handleRequest({ jsonrpc: '2.0', id: 1, method: 'tools/list' });
    const tools = (res!.result as { tools: { name: string }[] }).tools;
    expect(tools).toHaveLength(9);
    expect(tools.map((t) => t.name).sort()).toEqual(
      [
        'kb_compile',
        'kb_dashboard',
        'kb_export',
        'kb_ingest',
        'kb_lint',
        'kb_list_sources',
        'kb_query',
        'kb_read_page',
        'kb_search',
      ].sort(),
    );
  });

  test('notifications/initialized returns null (no response)', async () => {
    const res = await handleRequest({ jsonrpc: '2.0', method: 'notifications/initialized' });
    expect(res).toBeNull();
  });

  test('ping returns empty object', async () => {
    const res = await handleRequest({ jsonrpc: '2.0', id: 1, method: 'ping' });
    expect(res?.result).toEqual({});
  });

  test('unknown method returns -32601', async () => {
    const res = await handleRequest({ jsonrpc: '2.0', id: 1, method: 'no/such' });
    expect(res?.error?.code).toBe(-32601);
  });

  test('handleLine returns -32700 for malformed JSON', async () => {
    const res = await handleLine('not json{');
    expect(res?.error?.code).toBe(-32700);
  });
});

describe('safePath guard', () => {
  test('rejects empty path', () => {
    expect(safePath('', tmp)).toEqual({ ok: false, reason: 'path must not be empty' });
  });

  test('rejects ../ escapes', () => {
    const r = safePath('../etc/passwd', tmp);
    expect(r.ok).toBe(false);
  });

  test('rejects absolute paths outside root', () => {
    const r = safePath('/etc/passwd', tmp);
    expect(r.ok).toBe(false);
  });

  test('accepts paths inside root', () => {
    const r = safePath('kb/wiki/concepts/x.md', tmp);
    expect(r.ok).toBe(true);
  });
});

describe('kb_query tool', () => {
  test('finds keyword matches in wiki pages', async () => {
    writeFileSync(join(tmp, 'kb/wiki/concepts/x.md'), '# X\n\nattention is quadratic.\n');
    const res = await handleRequest({
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: { name: 'kb_query', arguments: { question: 'quadratic' } },
    });
    const out = (res!.result as { content: { text: string }[]; isError: boolean }).content[0]!.text;
    expect(out).toContain('concepts/x.md');
  });

  test('returns "no matches" when nothing found', async () => {
    writeFileSync(join(tmp, 'kb/wiki/concepts/x.md'), '# X\n\nhello.\n');
    const res = await handleRequest({
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: { name: 'kb_query', arguments: { question: 'nothing-matches' } },
    });
    const out = (res!.result as { content: { text: string }[] }).content[0]!.text;
    expect(out).toContain('No matches found');
  });
});

describe('kb_read_page tool', () => {
  test('reads files inside the root', async () => {
    writeFileSync(join(tmp, 'kb/wiki/concepts/x.md'), '# X\n\nbody.\n');
    const res = await handleRequest({
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: { name: 'kb_read_page', arguments: { path: 'kb/wiki/concepts/x.md' } },
    });
    const result = res!.result as { content: { text: string }[]; isError: boolean };
    expect(result.isError).toBe(false);
    expect(result.content[0]!.text).toContain('# X');
  });

  test('refuses path traversal', async () => {
    const res = await handleRequest({
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: { name: 'kb_read_page', arguments: { path: '../../etc/passwd' } },
    });
    const result = res!.result as { content: { text: string }[]; isError: boolean };
    expect(result.isError).toBe(true);
    expect(result.content[0]!.text).toMatch(/escapes KB_ROOT/);
  });
});

describe('kb_list_sources / kb_dashboard', () => {
  test('list returns manifest payload', async () => {
    const res = await handleRequest({
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: { name: 'kb_list_sources', arguments: {} },
    });
    const txt = (res!.result as { content: { text: string }[] }).content[0]!.text;
    const json = JSON.parse(txt);
    expect(json.project).toBe('proj');
    expect(json.count).toBe(0);
  });

  test('dashboard returns counts', async () => {
    writeFileSync(join(tmp, 'kb/wiki/concepts/x.md'), '# X\n');
    const res = await handleRequest({
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: { name: 'kb_dashboard', arguments: {} },
    });
    const txt = (res!.result as { content: { text: string }[] }).content[0]!.text;
    const json = JSON.parse(txt);
    expect(json.project).toBe('proj');
    expect(json.concepts).toBe(1);
  });
});

describe('kb_ingest tool', () => {
  test('URL paths return the skill-routing message', async () => {
    const res = await handleRequest({
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: { name: 'kb_ingest', arguments: { path: 'https://example.com/x' } },
    });
    const result = res!.result as { content: { text: string }[]; isError: boolean };
    expect(result.isError).toBe(false);
    expect(result.content[0]!.text).toMatch(/Claude Code skill/);
  });

  test('ingests a local markdown file under KB_ROOT', async () => {
    const src = join(tmp, 'doc.md');
    writeFileSync(src, '# Doc\n\n## one\n\nbody.\n');
    const res = await handleRequest({
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: { name: 'kb_ingest', arguments: { path: 'doc.md' } },
    });
    const result = res!.result as { content: { text: string }[]; isError: boolean };
    expect(result.isError).toBe(false);
    expect(result.content[0]!.text).toMatch(/Ingested 1 source/);
  });
});

describe('kb_export tool', () => {
  test('exports llms-txt under KB_ROOT', async () => {
    writeFileSync(join(tmp, 'kb/wiki/index.md'), '# Index\n\nbody.\n');
    const res = await handleRequest({
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: { name: 'kb_export', arguments: { format: 'llms-txt' } },
    });
    const result = res!.result as { content: { text: string }[]; isError: boolean };
    expect(result.isError).toBe(false);
    expect(result.content[0]!.text).toContain('llms.txt');
  });

  test('rejects unknown format', async () => {
    const res = await handleRequest({
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: { name: 'kb_export', arguments: { format: 'nope' } },
    });
    const result = res!.result as { content: { text: string }[]; isError: boolean };
    expect(result.isError).toBe(true);
  });
});

describe('kb_lint tool', () => {
  test('runs contradiction detection and embeds report', async () => {
    writeFileSync(
      join(tmp, 'kb/wiki/sources/a.md'),
      '# a\n\n## Key Claims\n\n- attention is dense across tokens — c-aaaaaaaa\n',
    );
    writeFileSync(
      join(tmp, 'kb/wiki/sources/b.md'),
      '# b\n\n## Key Claims\n\n- attention is sparse across tokens — c-bbbbbbbb\n',
    );
    writeFileSync(
      join(tmp, 'kb/wiki/concepts/attention.md'),
      '# Attention\n\nSee [a](../sources/a.md) and [b](../sources/b.md).\n',
    );
    const res = await handleRequest({
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: { name: 'kb_lint', arguments: {} },
    });
    const result = res!.result as { content: { text: string }[]; isError: boolean };
    expect(result.isError).toBe(false);
    expect(result.content[0]!.text).toContain('contradiction');
  });
});

describe('unknown tool', () => {
  test('returns -32602', async () => {
    const res = await handleRequest({
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: { name: 'kb_nonexistent', arguments: {} },
    });
    expect(res?.error?.code).toBe(-32602);
  });
});

describe('kbRootWithStatus', () => {
  test('honours $KB_ROOT', () => {
    const { root, status } = kbRootWithStatus();
    expect(root).toBe(tmp);
    expect(status).toBe('found');
  });
});

// keep TOOLS used
void TOOLS;
