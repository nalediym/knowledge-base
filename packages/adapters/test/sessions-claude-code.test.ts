import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { claudeCodeAdapter } from '../src/sessions/claude-code.ts';

let tmp: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), 'kb-cc-'));
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

function writeJsonl(path: string, records: unknown[]) {
  const full = join(tmp, path);
  mkdirSync(join(tmp, path.split('/').slice(0, -1).join('/') || '.'), { recursive: true });
  writeFileSync(full, records.map((r) => JSON.stringify(r)).join('\n') + '\n');
  return full;
}

describe('claude-code adapter', () => {
  test('parses user + assistant text records', () => {
    const file = writeJsonl('session.jsonl', [
      {
        type: 'user',
        sessionId: 'abc-123',
        cwd: '/Users/foo/bar/hypha',
        timestamp: '2026-05-21T10:00:00Z',
        message: { role: 'user', content: 'hello' },
      },
      {
        type: 'assistant',
        timestamp: '2026-05-21T10:00:01Z',
        message: {
          role: 'assistant',
          model: 'claude-opus-4-7',
          content: [
            { type: 'text', text: 'hi' },
            { type: 'thinking', text: 'should not leak' },
          ],
        },
      },
    ]);

    const parsed = claudeCodeAdapter.parse(file);
    expect(parsed.ok).toBe(true);
    if (!parsed.ok) throw new Error('parse failed');
    expect(parsed.doc.project).toBe('hypha');
    expect(parsed.doc.sessionId).toBe('abc-123');
    expect(parsed.doc.model).toBe('claude-opus-4-7');
    expect(parsed.doc.messages).toHaveLength(2);
    expect(parsed.doc.messages[0]!.content).toBe('hello');
    expect(parsed.doc.messages[1]!.content).toBe('hi');
  });

  test('renders tool_use blocks and skips malformed lines', () => {
    const full = join(tmp, 's.jsonl');
    writeFileSync(
      full,
      [
        '{not valid json',
        JSON.stringify({
          type: 'assistant',
          timestamp: '2026-05-21T10:00:00Z',
          message: {
            content: [{ type: 'tool_use', name: 'Bash', input: { command: 'ls' } }],
          },
        }),
      ].join('\n'),
    );

    const parsed = claudeCodeAdapter.parse(full);
    expect(parsed.ok).toBe(true);
    if (!parsed.ok) throw new Error('parse failed');
    expect(parsed.doc.messages[0]!.content).toContain('[tool: Bash]');
    expect(parsed.doc.messages[0]!.content).toContain('ls');
  });

  test('redact runs the redactor over each message', () => {
    const file = writeJsonl('s.jsonl', [
      {
        type: 'user',
        sessionId: 's1',
        cwd: '/x/proj',
        timestamp: '2026-05-21T10:00:00Z',
        message: { role: 'user', content: 'key=sk-abcdefghijklmnopqrstuv' },
      },
    ]);
    const parsed = claudeCodeAdapter.parse(file);
    if (!parsed.ok) throw new Error('parse failed');
    const r = claudeCodeAdapter.redact(parsed.doc, { username: null });
    expect(r.messages[0]!.content).toContain('[REDACTED_API_KEY]');
  });
});
