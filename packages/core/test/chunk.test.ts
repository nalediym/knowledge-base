import { describe, expect, test } from 'bun:test';
import { chunkByHeading } from '../src/chunk.ts';

describe('chunkByHeading', () => {
  test('splits a two-section markdown into two chunks with distinct content-addressed IDs', () => {
    const md = '## Alpha\n\nfirst section.\n\n## Beta\n\nsecond section.\n';
    const chunks = chunkByHeading(md);

    expect(chunks).toHaveLength(2);
    expect(chunks[0]!.id).toMatch(/^c-[0-9a-f]{8}$/);
    expect(chunks[1]!.id).toMatch(/^c-[0-9a-f]{8}$/);
    expect(chunks[0]!.id).not.toBe(chunks[1]!.id);
  });

  test('produces the same id for the same content (stability)', () => {
    const md = '## Alpha\n\nbody\n';
    const a = chunkByHeading(md);
    const b = chunkByHeading(md);
    expect(a[0]!.id).toBe(b[0]!.id);
  });

  test('produces a different id when content changes', () => {
    const before = chunkByHeading('## Alpha\n\noriginal body\n');
    const after = chunkByHeading('## Alpha\n\nedited body\n');
    expect(before[0]!.id).not.toBe(after[0]!.id);
  });

  test('extracts the heading from the first markdown header line', () => {
    const md = '## My Section Heading\n\nbody.\n';
    const [chunk] = chunkByHeading(md);
    expect(chunk!.heading).toBe('My Section Heading');
  });

  test('falls back to the first 60 chars when no header is present', () => {
    const md = 'just some prose, no header at all, but long enough to exercise the slice fallback path.';
    const [chunk] = chunkByHeading(md);
    expect(chunk!.heading).toBe(md.slice(0, 60));
  });

  test('skips empty and whitespace-only sections', () => {
    const md = '\n\n   \n\n## Real\n\nbody.\n';
    const chunks = chunkByHeading(md);
    expect(chunks).toHaveLength(1);
    expect(chunks[0]!.heading).toBe('Real');
  });
});
