import { describe, expect, test } from 'bun:test';
import { sweep } from '../src/lifecycle-sweep.ts';

const NOW = new Date('2026-05-21T00:00:00Z');

function daysAgo(n: number): Date {
  return new Date(NOW.getTime() - n * 24 * 60 * 60 * 1000);
}

describe('lifecycle sweep', () => {
  test('verified page whose stamp still matches body stays verified', () => {
    const result = sweep({
      current: 'verified',
      lastSeen: daysAgo(10),
      bodyHash: 'aaa',
      reviewedStamp: 'aaa',
      now: NOW,
    });
    expect(result).toBe('verified');
  });

  test('verified page whose stamp diverges from body demotes to reviewed (drift)', () => {
    const result = sweep({
      current: 'verified',
      lastSeen: daysAgo(10),
      bodyHash: 'NEW-HASH',
      reviewedStamp: 'OLD-STAMP',
      now: NOW,
    });
    expect(result).toBe('reviewed');
  });

  test('draft page untouched for over 90 days goes stale', () => {
    const result = sweep({
      current: 'draft',
      lastSeen: daysAgo(120),
      bodyHash: 'x',
      now: NOW,
    });
    expect(result).toBe('stale');
  });

  test('reviewed page untouched for over 90 days goes stale', () => {
    const result = sweep({
      current: 'reviewed',
      lastSeen: daysAgo(120),
      bodyHash: 'x',
      now: NOW,
    });
    expect(result).toBe('stale');
  });

  test('stale_after_days is configurable', () => {
    const result = sweep({
      current: 'draft',
      lastSeen: daysAgo(40),
      bodyHash: 'x',
      staleAfterDays: 30,
      now: NOW,
    });
    expect(result).toBe('stale');
  });

  test('archived pages are not touched by the sweep', () => {
    const result = sweep({
      current: 'archived',
      lastSeen: daysAgo(1000),
      bodyHash: 'x',
      now: NOW,
    });
    expect(result).toBe('archived');
  });

  test('missing lastSeen defaults to never-touched (stale immediately past threshold)', () => {
    const result = sweep({
      current: 'draft',
      lastSeen: null,
      bodyHash: 'x',
      now: NOW,
    });
    expect(result).toBe('stale');
  });
});
