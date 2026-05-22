import { existsSync } from 'node:fs';
import { dirname, isAbsolute, join, resolve, sep } from 'node:path';
import { homedir } from 'node:os';

export type KbRootStatus = 'found' | 'not_found';

export function kbRoot(): string {
  return kbRootWithStatus().root;
}

export function kbRootWithStatus(cwd: string = process.cwd()): {
  root: string;
  status: KbRootStatus;
} {
  const envRoot = process.env.KB_ROOT;
  if (envRoot && envRoot.length > 0) {
    const expanded = resolve(envRoot);
    return { root: expanded, status: kbPresent(expanded) ? 'found' : 'not_found' };
  }
  const found = walkUpForManifest(cwd);
  if (found) return { root: found, status: 'found' };
  return { root: cwd, status: 'not_found' };
}

export function kbPresent(root: string): boolean {
  return existsSync(join(root, 'kb', '.kb-manifest.json'));
}

function walkUpForManifest(start: string): string | null {
  const home = homedir();
  let dir = resolve(start);
  for (;;) {
    if (kbPresent(dir)) return dir;
    if (dir === '/' || dir === '' || dir === home) return null;
    const parent = dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

export type SafePathResult =
  | { ok: true; absolute: string }
  | { ok: false; reason: string };

export function safePath(path: unknown, root: string = kbRoot()): SafePathResult {
  if (typeof path !== 'string') return { ok: false, reason: 'path must be a string' };
  if (path === '') return { ok: false, reason: 'path must not be empty' };
  if (path.includes('\0')) return { ok: false, reason: 'path contains null byte' };
  const abs = isAbsolute(path) ? resolve(path) : resolve(root, path);
  if (abs === root || abs.startsWith(root + sep)) {
    return { ok: true, absolute: abs };
  }
  return { ok: false, reason: `path escapes KB_ROOT (${root}): ${path}` };
}
