import { describe, expect, test } from 'bun:test';
import { bucket, score, shimLegacy } from '../src/confidence.ts';

describe('confidence.score', () => {
  test('returns a value in [0, 1]', () => {
    const s = score({ sources: 1, sourceQuality: ['blog'], ageDays: 30, backlinks: 1 });
    expect(s).toBeGreaterThanOrEqual(0);
    expect(s).toBeLessThanOrEqual(1);
  });

  test('more sources raises confidence (monotone)', () => {
    const lo = score({ sources: 1, sourceQuality: ['blog'], ageDays: 0, backlinks: 0 });
    const hi = score({ sources: 5, sourceQuality: ['blog'], ageDays: 0, backlinks: 0 });
    expect(hi).toBeGreaterThan(lo);
  });

  test('older content decays confidence (recency factor)', () => {
    const fresh = score({ sources: 1, sourceQuality: ['blog'], ageDays: 0, backlinks: 0 });
    const stale = score({ sources: 1, sourceQuality: ['blog'], ageDays: 365, backlinks: 0 });
    expect(fresh).toBeGreaterThan(stale);
  });

  test('content_type changes the decay tau (news decays faster than concept)', () => {
    const news = score({ sources: 1, ageDays: 60, contentType: 'news' });
    const concept = score({ sources: 1, ageDays: 60, contentType: 'concept' });
    expect(concept).toBeGreaterThan(news);
  });

  test('official-quality sources beat blog-quality at the same source count', () => {
    const blog = score({ sources: 1, sourceQuality: ['blog'] });
    const official = score({ sources: 1, sourceQuality: ['official'] });
    expect(official).toBeGreaterThan(blog);
  });

  test('config weights override defaults', () => {
    const default_ = score({ sources: 5, sourceQuality: ['blog'], ageDays: 0, backlinks: 0 });
    const sourcesOnly = score(
      { sources: 5, sourceQuality: ['blog'], ageDays: 0, backlinks: 0 },
      { weights: { sources: 1.0, quality: 0, recency: 0, crossrefs: 0 } },
    );
    expect(sourcesOnly).not.toBe(default_);
  });

  test('shimLegacy maps legacy strings to floats', () => {
    expect(shimLegacy('high')).toBe(0.85);
    expect(shimLegacy('medium')).toBe(0.55);
    expect(shimLegacy('low')).toBe(0.25);
    expect(shimLegacy('garbage')).toBeNull();
  });

  test('bucket() classifies into high/medium/low thresholds', () => {
    expect(bucket(0.9)).toBe('high');
    expect(bucket(0.5)).toBe('medium');
    expect(bucket(0.1)).toBe('low');
  });
});
