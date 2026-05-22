#!/usr/bin/env bun
import { run } from './index.ts';

const result = await run(Bun.argv.slice(2));
process.exit(result.exitCode);
