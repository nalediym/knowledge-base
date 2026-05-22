import { readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

export interface WatcherOpts {
  paths: string[];
  pollMs?: number;
  debounceMs?: number;
  ingest: (path: string) => void | Promise<void>;
  onBatch?: (paths: string[]) => void;
  include?: (path: string) => boolean;
}

export interface Watcher {
  pollNow(): Promise<number>;
  flush(): Promise<void>;
  queue(): string[];
  start(): void;
  stop(): void;
}

export function createWatcher(opts: WatcherOpts): Watcher {
  const pollMs = opts.pollMs ?? 500;
  const debounceMs = opts.debounceMs ?? pollMs;
  const include = opts.include ?? (() => true);

  let baseline = scan(opts.paths, include);
  const queueSet = new Set<string>();
  let lastChange: number | null = null;
  let timer: ReturnType<typeof setInterval> | null = null;

  async function tick(): Promise<number> {
    const current = scan(opts.paths, include);
    const changed: string[] = [];
    for (const [path, mtime] of current) {
      if (baseline.get(path) !== mtime) changed.push(path);
    }
    baseline = current;
    if (changed.length > 0) {
      for (const c of changed) queueSet.add(c);
      lastChange = Date.now();
    }
    if (
      queueSet.size > 0 &&
      lastChange !== null &&
      Date.now() - lastChange >= debounceMs
    ) {
      await flush();
    }
    return changed.length;
  }

  async function flush(): Promise<void> {
    if (queueSet.size === 0) return;
    const paths = [...queueSet];
    queueSet.clear();
    lastChange = null;
    for (const p of paths) {
      try {
        await opts.ingest(p);
      } catch {
        // swallow individual ingest errors
      }
    }
    if (opts.onBatch) opts.onBatch(paths);
  }

  return {
    async pollNow() {
      return tick();
    },
    async flush() {
      await flush();
    },
    queue() {
      return [...queueSet];
    },
    start() {
      if (timer) return;
      timer = setInterval(() => {
        void tick();
      }, pollMs);
    },
    stop() {
      if (timer) {
        clearInterval(timer);
        timer = null;
      }
    },
  };
}

function scan(paths: string[], include: (path: string) => boolean): Map<string, number> {
  const out = new Map<string, number>();
  for (const dir of paths) {
    walk(dir, (path) => {
      if (!include(path)) return;
      out.set(path, fileMtime(path));
    });
  }
  return out;
}

function walk(dir: string, visit: (path: string) => void): void {
  let entries: import('node:fs').Dirent[];
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const e of entries) {
    const full = join(dir, e.name);
    if (e.isDirectory()) walk(full, visit);
    else if (e.isFile()) visit(full);
  }
}

function fileMtime(path: string): number {
  try {
    return statSync(path).mtimeMs;
  } catch {
    return 0;
  }
}
