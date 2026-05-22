import { describe, expect, test } from 'bun:test';
import { resolve } from 'node:path';

const BIN = resolve(import.meta.dirname, '../src/bin.ts');

async function runBin(args: string[]): Promise<{ stdout: string; exitCode: number }> {
  const proc = Bun.spawn(['bun', BIN, ...args], { stdout: 'pipe', stderr: 'pipe' });
  const stdout = await new Response(proc.stdout).text();
  const exitCode = await proc.exited;
  return { stdout, exitCode };
}

describe('kb cli', () => {
  test('--version prints the version and exits 0', async () => {
    const { stdout, exitCode } = await runBin(['--version']);
    expect(exitCode).toBe(0);
    expect(stdout.trim()).toBe('0.3.0-dev');
  });
});
