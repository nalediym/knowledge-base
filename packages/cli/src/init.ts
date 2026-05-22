import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { newManifest, writeManifest } from '@kb/core';

const INDEX_TEMPLATE = `# Knowledge Base Index

> Auto-maintained by \`kb compile\`. Do not edit manually.
> Sources: 0 | Concepts: 0 | Words: 0
`;

const CONFIG_TEMPLATE = `{
  "compile": { "concept_threshold": 2, "incremental": true },
  "provenance": { "chunk_strategy": "heading" },
  "sources": { "include": ["**/*.md", "**/*.txt"] },
  "images": { "download": true, "max_size_mb": 10 },
  "impute": { "enabled": false, "max_searches": 5 },
  "clipper": { "enabled": false, "watch_dir": null, "auto_ingest": false }
}
`;

export interface InitOpts {
  path?: string;
  name?: string;
}

export interface InitResult {
  kbRoot: string;
  created: boolean;
}

export async function initKb(opts: InitOpts = {}): Promise<InitResult> {
  const root = resolve(opts.path ?? '.');
  const manifestPath = join(root, 'kb/.kb-manifest.json');
  if (existsSync(manifestPath)) {
    return { kbRoot: root, created: false };
  }
  for (const sub of [
    'kb/raw',
    'kb/raw/media',
    'kb/raw/generated',
    'kb/raw/sessions',
    'kb/wiki/concepts',
    'kb/wiki/sources',
    'kb/wiki/candidates',
    'kb/output',
  ]) {
    mkdirSync(join(root, sub), { recursive: true });
  }
  const indexPath = join(root, 'kb/wiki/index.md');
  if (!existsSync(indexPath)) writeFileSync(indexPath, INDEX_TEMPLATE);
  const configPath = join(root, 'kb.config.json');
  if (!existsSync(configPath)) writeFileSync(configPath, CONFIG_TEMPLATE);
  await writeManifest(root, newManifest(opts.name ?? root.split('/').pop() ?? 'kb'));
  return { kbRoot: root, created: true };
}
