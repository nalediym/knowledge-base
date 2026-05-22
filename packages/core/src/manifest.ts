import { existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export interface SourceEntry {
  slug: string;
  path: string;
  hash: string;
  ingestedAt: string;
  chunks: number;
  generated?: boolean;
  images?: string[];
}

export interface Manifest {
  version: 1;
  name: string;
  created: string;
  lastCompiled: string | null;
  sources: SourceEntry[];
}

export type WriteResult =
  | { ok: true }
  | { ok: false; reason: 'locked'; holder: LockInfo };

interface LockInfo {
  pid: string;
  ts: string;
  operation: string;
}

const MANIFEST_FILE = '.kb-manifest.json';
const LOCK_FILE = '.kb-lock';
const LOCK_STALE_SECONDS = 300;

export function newManifest(name: string): Manifest {
  return {
    version: 1,
    name,
    created: new Date().toISOString(),
    lastCompiled: null,
    sources: [],
  };
}

export function addSource(manifest: Manifest, entry: SourceEntry): Manifest {
  const idx = manifest.sources.findIndex((s) => s.slug === entry.slug);
  const sources =
    idx === -1
      ? [...manifest.sources, entry]
      : manifest.sources.map((s, i) => (i === idx ? entry : s));
  return { ...manifest, sources };
}

function kbDir(kbRoot: string): string {
  const dir = join(kbRoot, 'kb');
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  return dir;
}

function manifestPath(kbRoot: string): string {
  return join(kbDir(kbRoot), MANIFEST_FILE);
}

function lockPath(kbRoot: string): string {
  return join(kbDir(kbRoot), LOCK_FILE);
}

export async function readManifest(kbRoot: string): Promise<Manifest | null> {
  const p = manifestPath(kbRoot);
  if (!existsSync(p)) return null;
  const raw = readFileSync(p, 'utf8');
  return JSON.parse(raw) as Manifest;
}

export async function writeManifest(
  kbRoot: string,
  manifest: Manifest,
): Promise<WriteResult> {
  const acquired = acquireLock(kbRoot, 'write');
  if (!acquired.ok) return acquired;

  try {
    const p = manifestPath(kbRoot);
    writeFileSync(p, `${JSON.stringify(manifest, null, 2)}\n`);
    return { ok: true };
  } finally {
    releaseLock(kbRoot);
  }
}

function acquireLock(
  kbRoot: string,
  operation: string,
): { ok: true } | { ok: false; reason: 'locked'; holder: LockInfo } {
  const lp = lockPath(kbRoot);
  if (existsSync(lp)) {
    try {
      const holder = JSON.parse(readFileSync(lp, 'utf8')) as LockInfo;
      const ageSec = (Date.now() - new Date(holder.ts).getTime()) / 1000;
      if (Number.isFinite(ageSec) && ageSec <= LOCK_STALE_SECONDS) {
        return { ok: false, reason: 'locked', holder };
      }
    } catch {
      // Corrupt lock file — treat as stale.
    }
  }
  writeLock(kbRoot, operation);
  return { ok: true };
}

function writeLock(kbRoot: string, operation: string): void {
  const lock: LockInfo = {
    pid: String(process.pid),
    ts: new Date().toISOString(),
    operation,
  };
  writeFileSync(lockPath(kbRoot), JSON.stringify(lock));
}

function releaseLock(kbRoot: string): void {
  const lp = lockPath(kbRoot);
  if (existsSync(lp)) unlinkSync(lp);
}
