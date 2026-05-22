import { describe, expect, test } from 'bun:test';
import { VERSION } from '../src/index.ts';

describe('@kb/core', () => {
  test('exports a version string', () => {
    expect(VERSION).toBe('0.3.0');
  });
});
