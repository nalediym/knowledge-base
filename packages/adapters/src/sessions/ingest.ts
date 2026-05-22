import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import {
  addSource,
  readManifest,
  writeManifest,
  type Manifest,
  type SourceEntry,
} from '@kb/core';
import { claudeCodeAdapter } from './claude-code.ts';
import { codexAdapter } from './codex.ts';
import { cursorAdapter } from './cursor.ts';
import { render, outputPath } from './renderer.ts';
import type { RedactOpts, SessionAdapter, SessionDoc } from './types.ts';

export const ALL_ADAPTERS: SessionAdapter[] = [
  claudeCodeAdapter,
  codexAdapter,
  cursorAdapter,
];

const AGENT_ALIASES: Record<string, SessionAdapter> = {
  claude: claudeCodeAdapter,
  claude_code: claudeCodeAdapter,
  codex: codexAdapter,
  codex_cli: codexAdapter,
  cursor: cursorAdapter,
};

export interface IngestSessionsOpts {
  kbRoot: string;
  agent?: string;
  outputBase?: string;
  dryRun?: boolean;
  adapters?: SessionAdapter[];
  redactOpts?: RedactOpts;
}

export interface SessionIngestSummary {
  agent: string;
  outPath: string;
  turns: number;
  sessionId: string;
  project: string;
}

export interface IngestResult {
  summaries: SessionIngestSummary[];
  byAgent: { agent: string; sessions: number }[];
}

export async function ingestSessions(opts: IngestSessionsOpts): Promise<IngestResult> {
  const { kbRoot, dryRun = false, redactOpts = {} } = opts;
  const outputBase = opts.outputBase ?? join(kbRoot, 'kb/raw/sessions');
  const adapters = filterAdapters(opts.adapters ?? ALL_ADAPTERS, opts.agent);

  const installed = adapters
    .map((a) => ({ adapter: a, detect: a.detect() }))
    .filter((x) => x.detect.kind === 'ok') as {
    adapter: SessionAdapter;
    detect: { kind: 'ok'; files: string[] };
  }[];

  const summaries: SessionIngestSummary[] = [];
  const byAgent: { agent: string; sessions: number }[] = [];

  for (const { adapter, detect } of installed) {
    let count = 0;
    for (const path of detect.files) {
      const parsed = adapter.parse(path);
      if (!parsed.ok) continue;
      const redacted = adapter.redact(parsed.doc, redactOpts);
      const rendered = render(redacted);
      const out = outputPath(outputBase, redacted);
      if (!dryRun) {
        mkdirSync(dirname(out), { recursive: true });
        writeFileSync(out, rendered);
      }
      summaries.push({
        agent: adapter.agentName,
        outPath: out,
        turns: redacted.messages.length,
        sessionId: redacted.sessionId,
        project: redacted.project,
      });
      count++;
    }
    byAgent.push({ agent: adapter.agentName, sessions: count });
  }

  if (!dryRun && summaries.length > 0) {
    await updateManifest(kbRoot, summaries);
  }

  return { summaries, byAgent };
}

function filterAdapters(adapters: SessionAdapter[], agent: string | undefined): SessionAdapter[] {
  if (!agent || agent === 'all') return adapters;
  const alias = AGENT_ALIASES[agent.toLowerCase()];
  const wantedName = alias?.agentName ?? agent.toLowerCase();
  return adapters.filter((a) => a.agentName === wantedName);
}

async function updateManifest(
  kbRoot: string,
  summaries: SessionIngestSummary[],
): Promise<void> {
  let manifest = await readManifest(kbRoot);
  if (!manifest) return;
  for (const s of summaries) {
    const rel = relative(join(kbRoot, 'kb/raw'), s.outPath);
    const slug = rel.replace(/\//g, '--');
    const content = existsSync(s.outPath) ? readFileSync(s.outPath, 'utf8') : '';
    const hash = createHash('sha256').update(content).digest('hex');
    const entry: SourceEntry = {
      slug,
      path: s.outPath,
      hash,
      ingestedAt: new Date().toISOString(),
      chunks: s.turns,
    };
    manifest = addSource(manifest, entry);
  }
  await writeManifest(kbRoot, manifest as Manifest);
}

export type { SessionAdapter, SessionDoc } from './types.ts';
