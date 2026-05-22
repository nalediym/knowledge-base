import { readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

export const DEFAULT_PAGE_THRESHOLD = 5000;
export const STREAMING_BACKLINKS_CEILING = 10000;

export type PageCountStatus = 'ok' | 'warn';

export interface PageCountResult {
  status: PageCountStatus;
  pageCount: number;
  threshold: number;
  ceiling: number;
  message: string;
}

export interface PageCountOpts {
  threshold?: number;
  ceiling?: number;
}

// Pure: classify a page count against the threshold/ceiling and produce
// the user-facing message. No I/O. See countWikiPages for the disk walk.
export function pageCountCheck(
  pageCount: number,
  opts: PageCountOpts = {},
): PageCountResult {
  const threshold = opts.threshold ?? DEFAULT_PAGE_THRESHOLD;
  const ceiling = opts.ceiling ?? STREAMING_BACKLINKS_CEILING;
  if (pageCount < threshold) {
    return {
      status: 'ok',
      pageCount,
      threshold,
      ceiling,
      message: `Page count ${pageCount} is under the ${threshold}-page advisory threshold.`,
    };
  }
  return {
    status: 'warn',
    pageCount,
    threshold,
    ceiling,
    message:
      `Page count ${pageCount} >= ${threshold} (advisory threshold). ` +
      `The in-memory backlink pass will become a bottleneck past ~${ceiling} pages. ` +
      `Plan the streaming-backlinks migration (issue #1) before hitting that wall.`,
  };
}

// Walk kb/concepts and kb/raw under kbRoot and count markdown files.
// kb/candidates and kb/output are excluded — candidates aren't promoted,
// output is generated artifacts.
export function countWikiPages(kbRoot: string): number {
  let total = 0;
  for (const sub of ['kb/concepts', 'kb/raw']) {
    total += walkMd(join(kbRoot, sub));
  }
  return total;
}

function walkMd(dir: string): number {
  let count = 0;
  let entries: import('node:fs').Dirent[];
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return 0;
  }
  for (const e of entries) {
    const full = join(dir, e.name);
    if (e.isDirectory()) {
      count += walkMd(full);
    } else if (e.isFile() && full.endsWith('.md')) {
      count += 1;
    } else if (e.isSymbolicLink()) {
      try {
        const s = statSync(full);
        if (s.isFile() && full.endsWith('.md')) count += 1;
      } catch {
        // dangling symlink — skip
      }
    }
  }
  return count;
}
