import type { SourceEntry } from './manifest.ts';

export interface IngestContext {
  kbRoot: string;
}

export interface IngestResult {
  source: SourceEntry;
  rawPath: string;
  content: string;
}

export interface Adapter {
  readonly name: string;
  canHandle(target: string): boolean;
  ingest(target: string, ctx: IngestContext): Promise<IngestResult[]>;
}

export interface InferContext {
  kbRoot: string;
}

export interface InferResult {
  pagesWritten: number;
  notes: string[];
}

export interface Inferrer {
  readonly name: string;
  run(ctx: InferContext): Promise<InferResult>;
}
