#!/usr/bin/env bun
import { VERSION } from '@kb/core';

const args = Bun.argv.slice(2);

if (args[0] === '--version' || args[0] === '-v') {
  console.log(VERSION);
  process.exit(0);
}

console.log(`kb ${VERSION}`);
console.log('usage: kb <command> [args]');
process.exit(0);
