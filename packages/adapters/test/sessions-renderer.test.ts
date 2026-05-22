import { describe, expect, test } from 'bun:test';
import { dateStamp, outputPath, render, sessionSlug } from '../src/sessions/renderer.ts';
import type { SessionDoc } from '../src/sessions/types.ts';

const doc: SessionDoc = {
  agent: 'claude_code',
  project: 'hypha',
  sessionId: 'abc12345-def0',
  sourcePath: '/x/y.jsonl',
  startedAt: '2026-05-21T10:00:00Z',
  model: 'claude-opus-4-7',
  messages: [
    { role: 'user', content: 'hi', timestamp: '2026-05-21T10:00:00Z' },
    { role: 'assistant', content: 'hello', timestamp: '2026-05-21T10:00:01Z' },
  ],
};

describe('renderer', () => {
  test('emits frontmatter + numbered turns + footer', () => {
    const md = render(doc);
    expect(md.startsWith('---\n')).toBe(true);
    expect(md).toContain('agent: "claude_code"');
    expect(md).toContain('project: "hypha"');
    expect(md).toContain('# Session: hypha / 2026-05-21');
    expect(md).toContain('## 1. user');
    expect(md).toContain('## 2. assistant');
    expect(md).toContain('**Turns:** 2');
  });

  test('outputPath uses project + date + slug', () => {
    const p = outputPath('kb/raw/sessions', doc);
    expect(p).toBe('kb/raw/sessions/hypha/2026-05-21-abc12345.md');
  });

  test('sessionSlug falls back to "session" when sessionId is empty', () => {
    expect(sessionSlug({ ...doc, sessionId: '' })).toBe('session');
  });

  test('dateStamp parses ISO and falls back to slice on bad input', () => {
    expect(dateStamp('2026-05-21T10:00:00Z')).toBe('2026-05-21');
    expect(dateStamp('garbagedate')).toBe('garbagedat');
  });
});
