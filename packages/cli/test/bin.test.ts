import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const BIN = resolve(import.meta.dirname, '../src/bin.ts');

async function runBin(
  args: string[],
  cwd?: string,
  env?: Record<string, string>,
): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  const proc = Bun.spawn(['bun', BIN, ...args], {
    stdout: 'pipe',
    stderr: 'pipe',
    cwd: cwd ?? process.cwd(),
    env: { ...process.env, ...env },
  });
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const exitCode = await proc.exited;
  return { stdout, stderr, exitCode };
}

describe('kb cli — flat commands', () => {
  test('--version prints the version', async () => {
    const { stdout, exitCode } = await runBin(['--version']);
    expect(exitCode).toBe(0);
    expect(stdout.trim()).toBe('kb v0.3.0');
  });

  test('help is shown for no args', async () => {
    const { stdout, exitCode } = await runBin([]);
    expect(exitCode).toBe(0);
    expect(stdout).toContain('usage: kb');
  });

  test('unknown command exits 1', async () => {
    const { exitCode, stderr } = await runBin(['no-such-cmd']);
    expect(exitCode).toBe(1);
    expect(stderr).toContain('unknown command');
  });
});

describe('kb cli — init + ingest + lint + output', () => {
  let tmp: string;

  beforeEach(() => {
    tmp = mkdtempSync(join(tmpdir(), 'kb-cli-'));
  });

  afterEach(() => {
    rmSync(tmp, { recursive: true, force: true });
  });

  test('init creates the kb tree', async () => {
    const { exitCode, stdout } = await runBin(['init'], tmp);
    expect(exitCode).toBe(0);
    expect(stdout).toContain('Initialized KB');
    expect(existsSync(join(tmp, 'kb/.kb-manifest.json'))).toBe(true);
    expect(existsSync(join(tmp, 'kb/wiki/index.md'))).toBe(true);
    expect(existsSync(join(tmp, 'kb.config.json'))).toBe(true);
  });

  test('init is idempotent', async () => {
    await runBin(['init'], tmp);
    const { stdout, exitCode } = await runBin(['init'], tmp);
    expect(exitCode).toBe(0);
    expect(stdout).toContain('already exists');
  });

  test('ingest adds a source and updates the manifest', async () => {
    await runBin(['init'], tmp);
    const doc = join(tmp, 'note.md');
    writeFileSync(doc, '# Note\n\n## one\n\nbody.\n');
    const { exitCode, stdout } = await runBin(['ingest', doc], tmp);
    expect(exitCode).toBe(0);
    expect(stdout).toContain('ingested');
    const manifest = JSON.parse(readFileSync(join(tmp, 'kb/.kb-manifest.json'), 'utf8'));
    expect(manifest.sources).toHaveLength(1);
  });

  test('lint --conflicts emits a report', async () => {
    await runBin(['init'], tmp);
    writeFileSync(
      join(tmp, 'kb/wiki/sources/a.md'),
      '# a\n\n## Key Claims\n\n- attention is dense across tokens — c-aaaaaaaa\n',
    );
    writeFileSync(
      join(tmp, 'kb/wiki/sources/b.md'),
      '# b\n\n## Key Claims\n\n- attention is sparse across tokens — c-bbbbbbbb\n',
    );
    writeFileSync(
      join(tmp, 'kb/wiki/concepts/attention.md'),
      '# Attention\n\nSee [a](../sources/a.md), [b](../sources/b.md).\n',
    );
    const { exitCode, stdout } = await runBin(['lint', '--conflicts'], tmp);
    expect(exitCode).toBe(0);
    expect(stdout).toContain('1 contradiction');
  });

  test('output llms-txt writes the artifact', async () => {
    await runBin(['init'], tmp);
    writeFileSync(join(tmp, 'kb/wiki/concepts/x.md'), '# X\n\nbody.\n');
    const { exitCode, stdout } = await runBin(['output', 'llms-txt'], tmp);
    expect(exitCode).toBe(0);
    expect(stdout).toMatch(/wrote .*llms\.txt/);
  });

  test('lint without --conflicts runs the page-count scorecard', async () => {
    await runBin(['init'], tmp);
    const { exitCode, stdout } = await runBin(['lint'], tmp);
    expect(exitCode).toBe(0);
    expect(stdout).toContain('advisory threshold');
  });

  test('ingest with no KB exits 1', async () => {
    const { exitCode, stderr } = await runBin(['ingest', 'foo.md'], tmp);
    expect(exitCode).toBe(1);
    expect(stderr).toContain('no KB found');
  });
});

describe('kb cli — mcp', () => {
  test('mcp responds to initialize on stdin', async () => {
    const proc = Bun.spawn(['bun', BIN, 'mcp'], {
      stdin: 'pipe',
      stdout: 'pipe',
      stderr: 'pipe',
    });
    proc.stdin.write(
      JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize' }) + '\n',
    );
    await proc.stdin.end();
    const stdout = await new Response(proc.stdout).text();
    await proc.exited;
    const line = stdout.trim().split('\n')[0]!;
    const response = JSON.parse(line);
    expect(response.id).toBe(1);
    expect(response.result.protocolVersion).toBe('2024-11-05');
  });
});
