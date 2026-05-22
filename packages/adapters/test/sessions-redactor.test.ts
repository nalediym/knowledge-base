import { describe, expect, test } from 'bun:test';
import { redact } from '../src/sessions/redactor.ts';

describe('redactor', () => {
  test('strips sk- api keys', () => {
    const out = redact('key=sk-1234567890abcdefghij and tail', { username: null });
    expect(out).toContain('[REDACTED_API_KEY]');
    expect(out).not.toContain('sk-1234567890abcdefghij');
  });

  test('strips ghp_ tokens', () => {
    const tok = 'ghp_' + 'a'.repeat(36);
    expect(redact(tok, { username: null })).toContain('[REDACTED_GH_TOKEN]');
  });

  test('strips named credentials and emails', () => {
    const out = redact('api_key: hunter2 user@example.com', { username: null });
    expect(out).toContain('[REDACTED_CREDENTIAL]');
    expect(out).toContain('[REDACTED_EMAIL]');
  });

  test('replaces username at word boundaries but not inside word-char runs', () => {
    const out = redact('hello naledi here. also user_naledi_dev untouched.', {
      username: 'naledi',
    });
    expect(out).toContain('hello USER here');
    expect(out).toContain('user_naledi_dev');
  });

  test('applies extra patterns', () => {
    const out = redact('FOOBAR=xyz', { username: null, extraPatterns: ['FOOBAR=\\S+'] });
    expect(out).toContain('[REDACTED_CUSTOM]');
  });

  test('ignores invalid extra patterns', () => {
    const out = redact('plain text', { username: null, extraPatterns: ['(unclosed'] });
    expect(out).toBe('plain text');
  });
});
