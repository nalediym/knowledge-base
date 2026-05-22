import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { newManifest, writeManifest } from '@kb/core';
import { ingestSessions } from '../src/sessions/ingest.ts';
import type { SessionAdapter } from '../src/sessions/types.ts';

let tmp: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), 'kb-sess-ingest-'));
  mkdirSync(join(tmp, 'kb'), { recursive: true });
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

const fakeAdapter: SessionAdapter = {
  agentName: 'fake',
  detect() {
    return { kind: 'ok', files: ['/virtual/1.jsonl', '/virtual/2.jsonl'] };
  },
  parse(path) {
    return {
      ok: true,
      doc: {
        agent: 'fake',
        project: 'demo',
        sessionId: path.includes('1') ? 'aaa11111' : 'bbb22222',
        sourcePath: path,
        startedAt: '2026-05-21T00:00:00Z',
        messages: [{ role: 'user', content: 'hello', timestamp: '2026-05-21T00:00:00Z' }],
      },
    };
  },
  redact(doc) {
    return doc;
  },
};

describe('ingestSessions', () => {
  test('renders one file per session and updates the manifest', async () => {
    await writeManifest(tmp, newManifest('test-kb'));

    const result = await ingestSessions({
      kbRoot: tmp,
      adapters: [fakeAdapter],
    });

    expect(result.summaries).toHaveLength(2);
    const out1 = join(tmp, 'kb/raw/sessions/demo/2026-05-21-aaa11111.md');
    const out2 = join(tmp, 'kb/raw/sessions/demo/2026-05-21-bbb22222.md');
    expect(existsSync(out1)).toBe(true);
    expect(existsSync(out2)).toBe(true);
    expect(readFileSync(out1, 'utf8')).toContain('# Session: demo / 2026-05-21');

    const manifest = JSON.parse(readFileSync(join(tmp, 'kb/.kb-manifest.json'), 'utf8'));
    expect(manifest.sources).toHaveLength(2);
    expect(manifest.sources[0].slug).toContain('demo');
  });

  test('dryRun does not write anything', async () => {
    await writeManifest(tmp, newManifest('test-kb'));
    const result = await ingestSessions({
      kbRoot: tmp,
      adapters: [fakeAdapter],
      dryRun: true,
    });
    expect(result.summaries).toHaveLength(2);
    expect(existsSync(join(tmp, 'kb/raw/sessions/demo'))).toBe(false);
  });

  test('agent filter narrows adapter list', async () => {
    await writeManifest(tmp, newManifest('test-kb'));
    const result = await ingestSessions({
      kbRoot: tmp,
      agent: 'claude_code',
      adapters: [fakeAdapter], // none alias to claude_code
    });
    expect(result.summaries).toHaveLength(0);
  });
});

// Silence unused warning
void writeFileSync;
