import { existsSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  addSource,
  createWatcher,
  newManifest,
  readManifest,
  VERSION,
  writeManifest,
  type Manifest,
} from '@kb/core';
import { ingestSessions, markdownAdapter } from '@kb/adapters';
import { detectConflicts, runExport, type ExportFormat } from '@kb/inferrers';
import { handleLine, kbRootWithStatus, runStdio } from '@kb/mcp';
import { initKb } from './init.ts';

export interface RunResult {
  exitCode: number;
}

const USAGE = `kb v${VERSION}

usage: kb <command> [args]

commands:
  init [path]              Create kb/ directory + manifest
  add <path>               Ingest a file or directory of markdown
  ingest <path>            Same as add
  ingest --sessions        Ingest agent session transcripts
                            [--agent claude|codex|all] [--dry-run]
  lint [--conflicts]       Run cross-source contradiction detection
  output <format>          Render: llms-txt | llms-full | jsonld | sitemap | all
  watch                    Debounced poll of kb/raw → ingest
  mcp                      Start the MCP stdio server
  version                  Print version
  help                     Show this message
`;

export async function run(argv: string[]): Promise<RunResult> {
  const [command, ...rest] = argv;

  switch (command) {
    case undefined:
    case 'help':
    case '--help':
    case '-h':
      process.stdout.write(USAGE);
      return { exitCode: 0 };

    case 'version':
    case '--version':
    case '-v':
      process.stdout.write(`kb v${VERSION}\n`);
      return { exitCode: 0 };

    case 'init':
      return await cmdInit(rest);

    case 'add':
    case 'ingest':
      return await cmdIngest(rest);

    case 'lint':
    case 'check':
      return await cmdLint(rest);

    case 'output':
      return await cmdOutput(rest);

    case 'watch':
      return await cmdWatch();

    case 'mcp':
      await runStdio();
      return { exitCode: 0 };

    default:
      process.stderr.write(`unknown command: ${command}\n\n${USAGE}`);
      return { exitCode: 1 };
  }
}

// ─── commands ──────────────────────────────────────────────────────────

async function cmdInit(args: string[]): Promise<RunResult> {
  const path = args.find((a) => !a.startsWith('-')) ?? '.';
  const result = await initKb({ path });
  if (result.created) process.stdout.write(`Initialized KB at ${result.kbRoot}\n`);
  else process.stdout.write(`KB already exists at ${result.kbRoot}\n`);
  return { exitCode: 0 };
}

async function cmdIngest(args: string[]): Promise<RunResult> {
  if (args.includes('--sessions')) return await cmdIngestSessions(args);

  const { root, status } = kbRootWithStatus();
  if (status !== 'found') {
    process.stderr.write(`no KB found at ${root} — run \`kb init\` first\n`);
    return { exitCode: 1 };
  }
  const targets = args.filter((a) => !a.startsWith('-'));
  if (targets.length === 0) {
    process.stderr.write('usage: kb ingest <path> [<path> ...]\n');
    return { exitCode: 1 };
  }
  let manifest = (await readManifest(root)) ?? newManifest('kb');
  let total = 0;
  for (const target of targets) {
    const abs = resolve(target);
    if (!existsSync(abs)) {
      process.stderr.write(`skip (not found): ${target}\n`);
      continue;
    }
    if (!markdownAdapter.canHandle(abs)) {
      process.stderr.write(`skip (no adapter): ${target}\n`);
      continue;
    }
    const results = await markdownAdapter.ingest(abs, { kbRoot: root });
    for (const r of results) manifest = addSource(manifest, r.source);
    total += results.length;
    process.stdout.write(`ingested ${results.length} file(s) from ${target}\n`);
  }
  await writeManifest(root, manifest as Manifest);
  process.stdout.write(`done. ${total} source(s) total.\n`);
  return { exitCode: 0 };
}

async function cmdIngestSessions(args: string[]): Promise<RunResult> {
  const { root, status } = kbRootWithStatus();
  if (status !== 'found') {
    process.stderr.write(`no KB found at ${root} — run \`kb init\` first\n`);
    return { exitCode: 1 };
  }
  const agent = takeFlag(args, '--agent') ?? takeFlag(args, '-a') ?? 'all';
  const dryRun = args.includes('--dry-run');
  const result = await ingestSessions({ kbRoot: root, agent, dryRun });
  for (const a of result.byAgent) {
    process.stdout.write(`  [${a.agent}] ${a.sessions} session(s)\n`);
  }
  process.stdout.write(
    `Ingested ${result.summaries.length} session transcript(s)${dryRun ? ' (dry-run)' : ''}.\n`,
  );
  return { exitCode: 0 };
}

async function cmdLint(args: string[]): Promise<RunResult> {
  const { root, status } = kbRootWithStatus();
  if (status !== 'found') {
    process.stderr.write(`no KB found at ${root} — run \`kb init\` first\n`);
    return { exitCode: 1 };
  }
  if (!args.includes('--conflicts')) {
    process.stderr.write('kb lint: only --conflicts is implemented in the TS port (v0.3).\n');
    return { exitCode: 1 };
  }
  const result = await detectConflicts({ kbRoot: root });
  process.stdout.write(
    `kb lint --conflicts: ${result.findings.length} contradiction(s) found.\n`,
  );
  if (result.reportPath) process.stdout.write(`Report: ${result.reportPath}\n`);
  return { exitCode: 0 };
}

async function cmdOutput(args: string[]): Promise<RunResult> {
  const { root, status } = kbRootWithStatus();
  if (status !== 'found') {
    process.stderr.write(`no KB found at ${root} — run \`kb init\` first\n`);
    return { exitCode: 1 };
  }
  const format = (args[0] ?? '') as ExportFormat;
  const valid: ExportFormat[] = ['llms-txt', 'llms-full', 'jsonld', 'sitemap', 'all'];
  if (!(valid as string[]).includes(format)) {
    process.stderr.write(`usage: kb output <${valid.join('|')}>\n`);
    return { exitCode: 1 };
  }
  const result = await runExport({ kbRoot: root, format });
  for (const p of result.paths) process.stdout.write(`wrote ${p}\n`);
  return { exitCode: 0 };
}

async function cmdWatch(): Promise<RunResult> {
  const { root, status } = kbRootWithStatus();
  if (status !== 'found') {
    process.stderr.write(`no KB found at ${root} — run \`kb init\` first\n`);
    return { exitCode: 1 };
  }
  const watchDirs = [`${root}/kb/raw`];
  process.stdout.write(
    `kb watch\n  poll:     500ms\n  debounce: 500ms\n  path:     ${watchDirs[0]}\n  Ctrl-C to stop.\n`,
  );
  let manifest = (await readManifest(root)) ?? newManifest('kb');
  const w = createWatcher({
    paths: watchDirs,
    pollMs: 500,
    debounceMs: 500,
    include: (p) => p.endsWith('.md'),
    ingest: async (path) => {
      if (!markdownAdapter.canHandle(path)) return;
      const results = await markdownAdapter.ingest(path, { kbRoot: root });
      for (const r of results) manifest = addSource(manifest, r.source);
      await writeManifest(root, manifest as Manifest);
      process.stdout.write(`==> ingested ${path}\n`);
    },
  });
  w.start();
  await new Promise<void>((resolve) => {
    const stop = () => {
      w.stop();
      resolve();
    };
    process.on('SIGINT', stop);
    process.on('SIGTERM', stop);
  });
  return { exitCode: 0 };
}

// ─── helpers ───────────────────────────────────────────────────────────

function takeFlag(args: string[], flag: string): string | undefined {
  const idx = args.indexOf(flag);
  if (idx === -1) return undefined;
  return args[idx + 1];
}

// re-exports for programmatic callers
export { initKb } from './init.ts';
export { handleLine };
// keep imports referenced
void statSync;
void writeFileSync;
void readFileSync;
