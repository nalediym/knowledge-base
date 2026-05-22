#!/usr/bin/env node
// sync-todos.mjs — invoked by .github/workflows/sync-todos.yml on PR merge.
//
// Reads the merged PR's number/title/body from env and edits TODOs.md:
//   1. Prepends an entry to "## Recently Shipped".
//   2. If the PR body has `Closes-TODO: <substring>` lines, removes any
//      matching `### …` section from "## Open".
//   3. Trims "## Recently Shipped" to the most recent MAX_SHIPPED entries.
//   4. Updates the "Last refreshed YYYY-MM-DD" stamp.
//
// Skips silently if TODOs.md is missing, env vars are empty, or the PR is
// itself a sync-bot PR (defensive — the workflow pushes direct, no PR).

import { existsSync, readFileSync, writeFileSync } from 'node:fs';

const FILE = 'TODOs.md';
const MAX_SHIPPED = 10;

const prNumber = process.env.PR_NUMBER;
const prTitle = (process.env.PR_TITLE ?? '').replace(/[\r\n]+/g, ' ').trim();
const prBody = process.env.PR_BODY ?? '';

if (!existsSync(FILE)) {
  console.log(`${FILE} not present — nothing to sync.`);
  process.exit(0);
}
if (!prNumber || !prTitle) {
  console.log('PR_NUMBER/PR_TITLE missing — skipping.');
  process.exit(0);
}
if (/^chore: sync TODOs\.md/i.test(prTitle)) {
  console.log('Bot PR — skipping.');
  process.exit(0);
}

let md = readFileSync(FILE, 'utf8');
const original = md;

const closes = [
  ...prBody.matchAll(/^\s*Closes-TODO:\s*(.+?)\s*$/gim),
].map((m) => m[1]);
for (const slug of closes) {
  md = removeSectionBySlug(md, slug);
}

md = prependShipped(md, `- **PR #${prNumber}** — ${prTitle}`);
md = trimShipped(md, MAX_SHIPPED);
md = stampRefreshed(md);

if (md === original) {
  console.log('No changes.');
  process.exit(0);
}

writeFileSync(FILE, md);
console.log(`Updated ${FILE} for PR #${prNumber}.`);

// ---------- helpers ----------

function removeSectionBySlug(text, slug) {
  const escaped = slug.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(
    `\\n### [^\\n]*${escaped}[^\\n]*\\n[\\s\\S]*?(?=\\n### |\\n## |$)`,
    'i',
  );
  return text.replace(re, '');
}

function prependShipped(text, entry) {
  const header = '## Recently Shipped';
  const idx = text.indexOf(header);
  if (idx === -1) {
    return `${text.trimEnd()}\n\n---\n\n${header}\n\n${entry}\n`;
  }
  const before = text.slice(0, idx + header.length);
  const after = text.slice(idx + header.length);
  // After the header, skip the blockquote/intro lines until the first bullet
  // or the next section. Insert the new entry on its own line above the
  // existing list.
  const lines = after.split('\n');
  let insertAt = 0;
  for (let i = 1; i < lines.length; i++) {
    const l = lines[i];
    if (l.startsWith('- ')) {
      insertAt = i;
      break;
    }
    if (l.startsWith('## ')) {
      insertAt = i;
      break;
    }
    if (i === lines.length - 1) insertAt = i + 1;
  }
  const head = lines.slice(0, insertAt).join('\n');
  const tail = lines.slice(insertAt).join('\n');
  // Ensure single blank line between intro and the new entry.
  return `${before}${head}\n${entry}\n${tail}`.replace(/\n{3,}/g, '\n\n');
}

function trimShipped(text, max) {
  const header = '## Recently Shipped';
  const start = text.indexOf(header);
  if (start === -1) return text;
  const tail = text.slice(start);
  const nextSection = tail.search(/\n## /);
  const sectionEnd = nextSection === -1 ? text.length : start + nextSection;
  const section = text.slice(start, sectionEnd);
  const lines = section.split('\n');
  let kept = 0;
  const out = [];
  for (const line of lines) {
    if (line.startsWith('- **PR #')) {
      kept += 1;
      if (kept > max) continue;
    }
    out.push(line);
  }
  return text.slice(0, start) + out.join('\n') + text.slice(sectionEnd);
}

function stampRefreshed(text) {
  const today = new Date().toISOString().slice(0, 10);
  if (/Last refreshed \d{4}-\d{2}-\d{2}/.test(text)) {
    return text.replace(/Last refreshed \d{4}-\d{2}-\d{2}/, `Last refreshed ${today}`);
  }
  return text;
}
