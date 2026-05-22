export interface SessionMessage {
  role: 'user' | 'assistant' | 'tool' | 'system';
  content: string;
  timestamp?: string;
  model?: string;
}

export interface SessionDoc {
  agent: string;
  project: string;
  sessionId: string;
  sourcePath: string;
  startedAt?: string;
  model?: string;
  messages: SessionMessage[];
  metadata?: Record<string, unknown>;
}

export type DetectResult =
  | { kind: 'ok'; files: string[] }
  | { kind: 'not_installed' };

export type ParseResult =
  | { ok: true; doc: SessionDoc }
  | { ok: false; reason: string };

export interface SessionAdapter {
  readonly agentName: string;
  detect(): DetectResult;
  parse(path: string): ParseResult;
  redact(doc: SessionDoc, opts?: RedactOpts): SessionDoc;
}

export interface RedactOpts {
  extraPatterns?: string[];
  username?: string | null;
}
