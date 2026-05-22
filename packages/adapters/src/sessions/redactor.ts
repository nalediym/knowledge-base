import type { RedactOpts } from './types.ts';

const API_KEY_RE = /sk-[A-Za-z0-9]{20,}/g;
const GH_TOKEN_RE = /ghp_[A-Za-z0-9]{36}/g;
const NAMED_CRED_RE =
  /(api[_-]?key|secret|token|bearer|password)["'\s:=]+(?!\[REDACTED_)[^\s"']+/gi;
const EMAIL_RE = /[\w.+\-]+@[\w\-]+\.[\w.\-]+/g;

export function redact(content: string, opts: RedactOpts = {}): string {
  const username =
    opts.username === undefined ? process.env.USER ?? null : opts.username;
  let out = content
    .replace(API_KEY_RE, '[REDACTED_API_KEY]')
    .replace(GH_TOKEN_RE, '[REDACTED_GH_TOKEN]')
    .replace(NAMED_CRED_RE, '[REDACTED_CREDENTIAL]')
    .replace(EMAIL_RE, '[REDACTED_EMAIL]');

  if (username) {
    const escaped = username.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    out = out.replace(new RegExp(`\\b${escaped}\\b`, 'g'), 'USER');
  }

  for (const pattern of opts.extraPatterns ?? []) {
    try {
      out = out.replace(new RegExp(pattern, 'g'), '[REDACTED_CUSTOM]');
    } catch {
      // skip invalid regex
    }
  }

  return out;
}
