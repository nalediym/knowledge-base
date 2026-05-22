import { join } from 'node:path';
import type { SessionDoc, SessionMessage } from './types.ts';

export function render(doc: SessionDoc): string {
  return buildFrontmatter(doc) + '\n' + buildBody(doc);
}

function buildFrontmatter(doc: SessionDoc): string {
  const fields: [string, string][] = [
    ['source_type', 'session'],
    ['agent', doc.agent],
    ['project', doc.project],
    ['session_id', doc.sessionId],
    ['started_at', doc.startedAt ?? ''],
    ['model', doc.model ?? ''],
    ['source_path', doc.sourcePath],
  ];
  const lines = fields.map(([k, v]) => `${k}: ${yamlString(v)}`).join('\n');
  return `---\n${lines}\n---\n`;
}

function buildBody(doc: SessionDoc): string {
  const title = `# Session: ${doc.project} / ${dateStamp(doc.startedAt)}\n\n`;
  const turns = doc.messages.map(renderTurn).join('\n\n');
  const footer =
    `\n\n---\n> **Agent:** ${doc.agent} · **Session:** \`${doc.sessionId}\` · ` +
    `**Turns:** ${doc.messages.length}\n`;
  return title + turns + footer;
}

function renderTurn(msg: SessionMessage, idx: number): string {
  const ts = msg.timestamp ? ` _(${msg.timestamp})_` : '';
  return `## ${idx + 1}. ${msg.role}${ts}\n\n${msg.content}`;
}

export function outputPath(base: string, doc: SessionDoc): string {
  const filename = `${dateStamp(doc.startedAt)}-${sessionSlug(doc)}.md`;
  return join(base, doc.project, filename);
}

export function sessionSlug(doc: SessionDoc): string {
  if (!doc.sessionId) return 'session';
  const cleaned = doc.sessionId.toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 8);
  return cleaned || 'session';
}

export function dateStamp(ts?: string | null): string {
  if (!ts) return new Date().toISOString().slice(0, 10);
  const d = new Date(ts);
  if (!isNaN(d.getTime())) return d.toISOString().slice(0, 10);
  return ts.slice(0, 10);
}

function yamlString(v: string): string {
  return `"${v.replace(/"/g, '\\"')}"`;
}
