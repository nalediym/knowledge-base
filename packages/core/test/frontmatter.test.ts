import { describe, expect, test } from 'bun:test';
import { parseFrontmatter, stringifyFrontmatter } from '../src/frontmatter.ts';

describe('frontmatter', () => {
  test('extracts a single string field', () => {
    const md = '---\nlifecycle: verified\n---\n\nbody\n';
    const { data, body } = parseFrontmatter(md);
    expect(data.lifecycle).toBe('verified');
    expect(body).toBe('body\n');
  });

  test('extracts mixed string and numeric fields', () => {
    const md = '---\nlifecycle: reviewed\nconfidence: 0.85\nlast_seen: 2026-04-23T12:34:56Z\n---\n\nbody.\n';
    const { data } = parseFrontmatter(md);
    expect(data.lifecycle).toBe('reviewed');
    expect(data.confidence).toBe(0.85);
    expect(data.last_seen).toBe('2026-04-23T12:34:56Z');
  });

  test('returns empty data and unchanged body when no frontmatter is present', () => {
    const md = '# Hello\n\nbody.\n';
    const { data, body } = parseFrontmatter(md);
    expect(data).toEqual({});
    expect(body).toBe(md);
  });

  test('round-trips through stringify + parse', () => {
    const original = '---\nlifecycle: verified\nconfidence: 0.7\n---\n\nbody body body\n';
    const { data, body } = parseFrontmatter(original);
    expect(stringifyFrontmatter(data, body)).toBe(original);
  });

  test('stringify with empty data omits the frontmatter block', () => {
    expect(stringifyFrontmatter({}, 'body\n')).toBe('body\n');
  });
});
