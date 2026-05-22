import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  listCandidates,
  promoteAll,
  promoteOne,
  targetPath,
  writeConcept,
} from '../src/candidates.ts';

let tmp: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), 'kb-candidates-'));
  mkdirSync(join(tmp, 'kb/wiki/concepts'), { recursive: true });
  mkdirSync(join(tmp, 'kb/wiki/candidates'), { recursive: true });
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

describe('candidates workflow', () => {
  test('targetPath routes a new concept to candidates/', () => {
    const r = targetPath('jwt', { kbRoot: tmp });
    expect(r.kind).toBe('candidate');
    expect(r.path).toMatch(/kb\/wiki\/candidates\/jwt\.md$/);
  });

  test('targetPath routes an existing concept to concepts/ in-place', () => {
    writeFileSync(join(tmp, 'kb/wiki/concepts/jwt.md'), 'existing body');
    const r = targetPath('jwt', { kbRoot: tmp });
    expect(r.kind).toBe('existing');
    expect(r.path).toMatch(/kb\/wiki\/concepts\/jwt\.md$/);
  });

  test('writeConcept stages new concepts under candidates/', () => {
    const r = writeConcept('csrf', '# CSRF\n\nbody', { kbRoot: tmp });
    expect(r.kind).toBe('candidate');
    expect(readFileSync(r.path, 'utf8')).toBe('# CSRF\n\nbody');
  });

  test('writeConcept updates existing concepts in-place', () => {
    writeFileSync(join(tmp, 'kb/wiki/concepts/csrf.md'), 'old');
    const r = writeConcept('csrf', 'new', { kbRoot: tmp });
    expect(r.kind).toBe('existing');
    expect(readFileSync(r.path, 'utf8')).toBe('new');
  });

  test('promoteOne moves candidate → concept', () => {
    writeFileSync(join(tmp, 'kb/wiki/candidates/csrf.md'), 'csrf body');
    const r = promoteOne('csrf', { kbRoot: tmp });
    expect(r.ok).toBe(true);
    expect(existsSync(join(tmp, 'kb/wiki/concepts/csrf.md'))).toBe(true);
    expect(existsSync(join(tmp, 'kb/wiki/candidates/csrf.md'))).toBe(false);
  });

  test('promoteOne refuses to overwrite an existing concept without force', () => {
    writeFileSync(join(tmp, 'kb/wiki/candidates/csrf.md'), 'new');
    writeFileSync(join(tmp, 'kb/wiki/concepts/csrf.md'), 'old');
    const r = promoteOne('csrf', { kbRoot: tmp });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toBe('concept_exists');
    expect(readFileSync(join(tmp, 'kb/wiki/concepts/csrf.md'), 'utf8')).toBe('old');
  });

  test('promoteOne with force=true overwrites', () => {
    writeFileSync(join(tmp, 'kb/wiki/candidates/csrf.md'), 'new');
    writeFileSync(join(tmp, 'kb/wiki/concepts/csrf.md'), 'old');
    const r = promoteOne('csrf', { kbRoot: tmp, force: true });
    expect(r.ok).toBe(true);
    expect(readFileSync(join(tmp, 'kb/wiki/concepts/csrf.md'), 'utf8')).toBe('new');
  });

  test('promoteOne fails when the candidate is missing', () => {
    const r = promoteOne('does-not-exist', { kbRoot: tmp });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toBe('missing_candidate');
  });

  test('listCandidates returns the names (no extension) of every pending candidate', () => {
    writeFileSync(join(tmp, 'kb/wiki/candidates/alpha.md'), 'x');
    writeFileSync(join(tmp, 'kb/wiki/candidates/beta.md'), 'x');
    expect(listCandidates({ kbRoot: tmp }).sort()).toEqual(['alpha', 'beta']);
  });

  test('promoteAll promotes every candidate that does not collide', () => {
    writeFileSync(join(tmp, 'kb/wiki/candidates/alpha.md'), 'a');
    writeFileSync(join(tmp, 'kb/wiki/candidates/beta.md'), 'b');
    writeFileSync(join(tmp, 'kb/wiki/concepts/beta.md'), 'old beta');

    const r = promoteAll({ kbRoot: tmp });
    expect(r.promoted).toBe(1);
    expect(r.skipped).toBe(1);
    expect(existsSync(join(tmp, 'kb/wiki/concepts/alpha.md'))).toBe(true);
    expect(readFileSync(join(tmp, 'kb/wiki/concepts/beta.md'), 'utf8')).toBe('old beta');
  });
});
