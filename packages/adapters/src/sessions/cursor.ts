import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import type { DetectResult, ParseResult, SessionAdapter, SessionDoc } from './types.ts';

const STORE = join(
  homedir(),
  'Library/Application Support/Cursor/User/workspaceStorage',
);

export const cursorAdapter: SessionAdapter = {
  agentName: 'cursor',

  detect(): DetectResult {
    return existsSync(STORE) ? { kind: 'ok', files: [] } : { kind: 'not_installed' };
  },

  parse(_path: string): ParseResult {
    return { ok: false, reason: 'not_implemented' };
  },

  redact(doc: SessionDoc): SessionDoc {
    return doc;
  },
};
