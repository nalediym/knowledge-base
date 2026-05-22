import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import {
  type Chunk,
  chunkByHeading,
  type InferContext,
  type Inferrer,
  type InferResult,
} from '@kb/core';
import { contextualizeChunk, type EmbeddingProvider, type LLMProvider } from '@kb/llm';
import { openStore } from '@kb/store-sqlite';

export interface CompileConfig {
  kbRoot: string;
  llm: LLMProvider;
  embeddings: EmbeddingProvider;
  embeddingModel: string;
  dbPath: string;
  skipContextualize?: boolean;
}

export function compileInferrer(config: CompileConfig): Inferrer {
  return {
    name: 'compile',
    async run(_ctx: InferContext): Promise<InferResult> {
      const rawDir = join(config.kbRoot, 'kb/raw');
      const files = walkMarkdown(rawDir);
      const store = openStore(config.dbPath);
      const notes: string[] = [];

      try {
        let pagesWritten = 0;

        for (const file of files) {
          const content = readFileSync(file, 'utf8');
          const rel = relative(config.kbRoot, file);
          const title = extractTitle(content, rel);
          const mtime = Math.floor(statSync(file).mtimeMs);

          const chunks = chunksOrFallback(content);

          const indexedChunks: { id: string; content: string }[] = [];
          for (const chunk of chunks) {
            const indexed = config.skipContextualize
              ? chunk.content
              : await contextualizeChunk({
                  document: content,
                  chunk: chunk.content,
                  llm: config.llm,
                });
            indexedChunks.push({ id: chunk.id, content: indexed });
          }

          store.upsertPage({
            path: rel,
            title,
            mtime,
            chunks: indexedChunks,
          });

          const vectors = await config.embeddings.embedBatch(
            indexedChunks.map((c) => c.content),
            { model: config.embeddingModel },
          );

          vectors.forEach((vec, i) => {
            const chunk = indexedChunks[i];
            if (chunk) {
              store.upsertEmbedding(rel, chunk.id, config.embeddingModel, vec);
            }
          });

          pagesWritten += 1;
          notes.push(`indexed ${rel} (${chunks.length} chunks)`);
        }

        return { pagesWritten, notes };
      } finally {
        store.close();
      }
    },
  };
}

function chunksOrFallback(content: string): Chunk[] {
  const parsed = chunkByHeading(content);
  if (parsed.length > 0) return parsed;
  const trimmed = content.trim();
  if (!trimmed) return [];
  return [{ id: 'c-whole-doc', heading: '', content: trimmed, lineStart: 0 }];
}

function extractTitle(content: string, rel: string): string {
  const match = content.match(/^#\s+(.+)$/m);
  if (match?.[1]) return match[1].trim();
  return rel;
}

function walkMarkdown(dir: string): string[] {
  const out: string[] = [];
  let entries: Array<{ name: string; isDirectory(): boolean; isFile(): boolean }>;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const entry of entries) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...walkMarkdown(full));
    } else if (entry.isFile() && full.toLowerCase().endsWith('.md')) {
      out.push(full);
    }
  }
  return out;
}
