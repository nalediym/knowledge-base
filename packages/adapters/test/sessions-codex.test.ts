import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { codexAdapter } from '../src/sessions/codex.ts';

let tmp: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), 'kb-codex-'));
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

describe('codex adapter', () => {
  test('parses session_meta + user/assistant response_items', () => {
    const file = join(tmp, 'rollout.jsonl');
    writeFileSync(
      file,
      [
        {
          type: 'session_meta',
          timestamp: '2026-05-21T08:00:00Z',
          payload: { id: 'cdx-1', cwd: '/Users/foo/proj' },
        },
        {
          type: 'turn_context',
          payload: { model: 'gpt-5' },
        },
        {
          type: 'response_item',
          timestamp: '2026-05-21T08:00:01Z',
          payload: {
            role: 'user',
            type: 'message',
            content: [{ type: 'input_text', text: 'hello codex' }],
          },
        },
        {
          type: 'response_item',
          timestamp: '2026-05-21T08:00:02Z',
          payload: {
            role: 'assistant',
            type: 'message',
            content: [{ type: 'output_text', text: 'hi back' }],
          },
        },
        {
          type: 'response_item',
          timestamp: '2026-05-21T08:00:03Z',
          payload: { type: 'web_search_call', query: 'best ide' },
        },
      ]
        .map((r) => JSON.stringify(r))
        .join('\n'),
    );

    const parsed = codexAdapter.parse(file);
    if (!parsed.ok) throw new Error('parse failed');
    expect(parsed.doc.sessionId).toBe('cdx-1');
    expect(parsed.doc.project).toBe('proj');
    expect(parsed.doc.model).toBe('gpt-5');
    expect(parsed.doc.startedAt).toBe('2026-05-21T08:00:00Z');
    expect(parsed.doc.messages).toHaveLength(3);
    expect(parsed.doc.messages[0]!.role).toBe('user');
    expect(parsed.doc.messages[2]!.content).toContain('[tool: WebSearch]');
  });
});
