import { mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, relative } from 'node:path';
import { createHash } from 'node:crypto';
import {
  type Adapter,
  type IngestContext,
  type IngestResult,
  type Chunk,
  chunkByHeading,
} from '@kb/core';

function pathToSlug(path: string): string {
  return path.replace(/^\.\//, '').replace(/\//g, '--');
}

function sha256Hex(content: string): string {
  return createHash('sha256').update(content).digest('hex');
}

function writeSourcePage(args: {
  kbRoot: string;
  originalPath: string;
  slug: string;
  hash: string;
  chunks: Chunk[];
}): void {
  const { kbRoot, originalPath, slug, hash, chunks } = args;
  const today = new Date().toISOString().slice(0, 10);

  const chunkSections = chunks
    .map(
      (c) => `### ${c.id}: ${c.heading}\n> ${c.content.slice(0, 300).replace(/\n+/g, ' ')}\n`,
    )
    .join('\n');

  const body = `# ${basename(originalPath)}

> **Source:** ${originalPath}
> **Ingested:** ${today}
> **Hash:** ${hash}
> **Status:** fresh
> **Chunks:** ${chunks.length}

## Chunks
${chunkSections}

## Key Claims
<!-- populated by compile -->

## Related Concepts
<!-- populated by compile -->

<!-- human notes below -->
`;

  const dest = join(kbRoot, 'kb/wiki/sources', `${slug.replace(/\.md$/, '')}.md`);
  mkdirSync(dirname(dest), { recursive: true });
  writeFileSync(dest, body);
}

async function ingestFile(absPath: string, ctx: IngestContext): Promise<IngestResult> {
  const content = readFileSync(absPath, 'utf8');
  const rel = relative(ctx.kbRoot, absPath);
  const slug = pathToSlug(rel);
  const hash = sha256Hex(content);
  const chunks = chunkByHeading(content);

  const rawDest = join(ctx.kbRoot, 'kb/raw', slug);
  mkdirSync(dirname(rawDest), { recursive: true });
  writeFileSync(rawDest, content);

  writeSourcePage({
    kbRoot: ctx.kbRoot,
    originalPath: rel,
    slug,
    hash,
    chunks,
  });

  return {
    source: {
      slug,
      path: rel,
      hash,
      ingestedAt: new Date().toISOString(),
      chunks: chunks.length,
    },
    rawPath: rawDest,
    content,
  };
}

export const markdownAdapter: Adapter = {
  name: 'markdown',

  canHandle(target) {
    try {
      const st = statSync(target);
      if (st.isFile()) return target.toLowerCase().endsWith('.md');
      if (st.isDirectory()) return true;
      return false;
    } catch {
      return false;
    }
  },

  async ingest(target, ctx) {
    const st = statSync(target);
    if (st.isFile()) {
      return [await ingestFile(target, ctx)];
    }
    throw new Error(`directory ingest not implemented yet: ${target}`);
  },
};
