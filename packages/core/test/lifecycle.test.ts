import { describe, expect, test } from 'bun:test';
import { canTransition, LIFECYCLE_STATES } from '../src/lifecycle.ts';

describe('lifecycle', () => {
  test('lists the five states in order', () => {
    expect(LIFECYCLE_STATES).toEqual(['draft', 'reviewed', 'verified', 'stale', 'archived']);
  });

  test('draft can advance to reviewed', () => {
    expect(canTransition('draft', 'reviewed')).toBe(true);
  });

  test('reviewed can be verified', () => {
    expect(canTransition('reviewed', 'verified')).toBe(true);
  });

  test('verified can demote to reviewed on drift', () => {
    expect(canTransition('verified', 'reviewed')).toBe(true);
  });

  test('archived is terminal', () => {
    for (const s of LIFECYCLE_STATES) {
      expect(canTransition('archived', s)).toBe(false);
    }
  });

  test('any state can go stale or archived', () => {
    for (const s of ['draft', 'reviewed', 'verified'] as const) {
      expect(canTransition(s, 'stale')).toBe(true);
      expect(canTransition(s, 'archived')).toBe(true);
    }
  });

  test('cannot skip from draft to verified', () => {
    expect(canTransition('draft', 'verified')).toBe(false);
  });
});
