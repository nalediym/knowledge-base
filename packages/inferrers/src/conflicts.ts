import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import type { LLMProvider } from '@kb/llm';

export interface Claim {
  text: string;
  source: string;
  sourcePath: string;
  chunkId: string;
}

export interface Finding {
  concept: string;
  claimA: Claim;
  claimB: Claim;
  note?: string;
}

export interface ClaimComparator {
  compare(a: Claim, b: Claim): Promise<'agree' | 'disagree' | 'unknown'>;
}

export interface ConflictsOpts {
  kbRoot: string;
  comparator?: ClaimComparator;
  date?: Date;
  outputDir?: string;
}

export interface ConflictsResult {
  findings: Finding[];
  reportPath: string | null;
}

export async function detectConflicts(opts: ConflictsOpts): Promise<ConflictsResult> {
  const kbRoot = opts.kbRoot;
  const comparator = opts.comparator ?? heuristicComparator;
  const conceptsDir = join(kbRoot, 'kb/wiki/concepts');
  const date = opts.date ?? new Date();
  const outputDir = opts.outputDir ?? join(kbRoot, 'kb/output');

  if (!existsSync(conceptsDir)) {
    return { findings: [], reportPath: null };
  }

  const conceptFiles = readdirSync(conceptsDir)
    .filter((f) => f.endsWith('.md'))
    .map((f) => join(conceptsDir, f));

  const findings: Finding[] = [];
  for (const path of conceptFiles) {
    if (!shouldScan(path)) continue;
    findings.push(...(await scanConcept(path, kbRoot, comparator)));
  }

  mkdirSync(outputDir, { recursive: true });
  const reportPath = join(outputDir, `contradictions-${isoDate(date)}.md`);
  writeFileSync(reportPath, renderReport(findings, date));
  return { findings, reportPath };
}

export function shouldScan(path: string): boolean {
  if (!existsSync(path)) return false;
  const content = readFileSync(path, 'utf8');
  const lc = lifecycle(content);
  return lc !== 'draft';
}

export function lifecycle(content: string): 'reviewed' | 'verified' | 'draft' | 'none' {
  const fm = extractFrontmatter(content);
  let value: string | null = null;
  if (fm) {
    for (const line of fm.split('\n')) {
      const m = /^\s*lifecycle\s*:\s*([A-Za-z_-]+)/.exec(line);
      if (m) {
        value = m[1]!.toLowerCase();
        break;
      }
    }
  } else {
    const m = /\blifecycle\s*:\s*([A-Za-z_-]+)/.exec(content);
    if (m) value = m[1]!.toLowerCase();
  }
  if (value === 'reviewed' || value === 'verified' || value === 'draft') return value;
  return 'none';
}

function extractFrontmatter(content: string): string | null {
  const m = /^---\s*\n([\s\S]*?)\n---\s*\n/.exec(content);
  return m ? m[1]! : null;
}

async function scanConcept(
  conceptPath: string,
  kbRoot: string,
  comparator: ClaimComparator,
): Promise<Finding[]> {
  const conceptName = basename(conceptPath, '.md');
  const sources = findReferencedSources(conceptPath, kbRoot).filter(shouldScan);
  const claims = sources.flatMap(extractClaims);
  const findings: Finding[] = [];
  for (const [a, b] of crossSourcePairs(claims)) {
    const verdict = await comparator.compare(a, b);
    if (verdict === 'disagree') {
      findings.push({ concept: conceptName, claimA: a, claimB: b });
    }
  }
  return findings;
}

export function findReferencedSources(conceptPath: string, kbRoot: string): string[] {
  const sourcesDir = join(kbRoot, 'kb/wiki/sources');
  const content = readFileSync(conceptPath, 'utf8');
  const re = /\]\(\.*\/?sources\/([a-zA-Z0-9_\-.]+)\.md/g;
  const seen = new Set<string>();
  let m: RegExpExecArray | null;
  while ((m = re.exec(content)) !== null) {
    seen.add(join(sourcesDir, m[1]! + '.md'));
  }
  return [...seen].filter(existsSync);
}

export function extractClaims(sourcePath: string): Claim[] {
  const sourceName = basename(sourcePath, '.md');
  const content = readFileSync(sourcePath, 'utf8');
  const section = extractSection(content, 'Key Claims');
  if (!section) return [];

  const out: Claim[] = [];
  for (const rawLine of section.split('\n')) {
    const line = rawLine.trim();
    if (!line.startsWith('-')) continue;
    const claim = parseBullet(line, sourceName, sourcePath);
    if (claim) out.push(claim);
  }
  return out;
}

function extractSection(content: string, heading: string): string | null {
  const re = new RegExp(`(?:^|\\n)##\\s+${heading}\\s*\\n([\\s\\S]*?)(?=\\n##\\s|$)`);
  const m = re.exec(content);
  return m ? m[1]! : null;
}

function parseBullet(line: string, source: string, sourcePath: string): Claim | null {
  const rest = line.replace(/^-\s*/, '').trim();
  let parts: string[];
  if (rest.includes('—')) parts = splitOnce(rest, '—');
  else if (rest.includes(' -- ')) parts = splitOnce(rest, ' -- ');
  else return null;
  const [text, tail] = parts;
  if (!tail) return null;
  const idMatch = /(c-[a-f0-9]{6,})/i.exec(tail);
  if (!idMatch) return null;
  return {
    text: text!.trim(),
    source,
    sourcePath,
    chunkId: idMatch[1]!,
  };
}

function splitOnce(s: string, sep: string): [string, string] {
  const i = s.indexOf(sep);
  return [s.slice(0, i), s.slice(i + sep.length)];
}

export function crossSourcePairs(claims: Claim[]): [Claim, Claim][] {
  const out: [Claim, Claim][] = [];
  for (let i = 0; i < claims.length; i++) {
    for (let j = i + 1; j < claims.length; j++) {
      const a = claims[i]!;
      const b = claims[j]!;
      if (a.source === b.source) continue;
      out.push(a.source <= b.source ? [a, b] : [b, a]);
    }
  }
  return out;
}

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export function renderReport(findings: Finding[], date: Date): string {
  const header = `# Contradictions — ${isoDate(date)}\n\n`;
  if (findings.length === 0) {
    return header + 'No contradictions found across scanned concept pages.\n';
  }
  const grouped = new Map<string, Finding[]>();
  for (const f of findings) {
    const list = grouped.get(f.concept) ?? [];
    list.push(f);
    grouped.set(f.concept, list);
  }
  const sections = [...grouped.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([concept, entries]) => {
      const head = `## concept: ${concept}.md\n\n`;
      return head + entries.map(renderFinding).join('\n');
    });
  return header + sections.join('\n') + '\n';
}

function renderFinding(f: Finding): string {
  const base =
    `- Claim A: "${f.claimA.text}"\n` +
    `  - Source: ${f.claimA.source}.md#${f.claimA.chunkId}\n` +
    `- Claim B: "${f.claimB.text}"\n` +
    `  - Source: ${f.claimB.source}.md#${f.claimB.chunkId}\n`;
  return f.note ? base + `- Resolution: ${f.note}\n` : base;
}

// ─── Heuristic claim comparator ────────────────────────────────────────

const STOPWORDS = new Set([
  'a', 'an', 'the', 'is', 'are', 'was', 'were', 'be', 'been', 'being', 'am',
  'do', 'does', 'did', 'done', 'doing',
  'of', 'in', 'on', 'at', 'to', 'for', 'with', 'by', 'from', 'into', 'onto',
  'that', 'this', 'these', 'those', 'it', 'its', 'they', 'them', 'their',
  'there', 'here', 'as', 'if', 'then', 'than', 'so', 'but', 'or', 'and',
  'not', 'no', 'have', 'has', 'had', 'having',
  'can', 'cannot', 'could', 'should', 'would', 'may', 'might', 'must', 'will',
  'i', 'you', 'he', 'she', 'we', 'us', 'our', 'your', 'my', 'me', 'him', 'her',
  'about', 'over', 'under', 'between', 'across', 'through', 'during',
  'some', 'any', 'all', 'each', 'every', 'many', 'few', 'more', 'most', 'less', 'least',
]);

const ANTONYMS: [string, string][] = [
  ['increase', 'decrease'],
  ['increases', 'decreases'],
  ['rises', 'falls'],
  ['rise', 'fall'],
  ['faster', 'slower'],
  ['fast', 'slow'],
  ['hot', 'cold'],
  ['high', 'low'],
  ['large', 'small'],
  ['big', 'small'],
  ['more', 'less'],
  ['always', 'never'],
  ['safe', 'unsafe'],
  ['secure', 'insecure'],
  ['stateful', 'stateless'],
  ['synchronous', 'asynchronous'],
  ['dense', 'sparse'],
  ['linear', 'quadratic'],
  ['allowed', 'forbidden'],
  ['allowed', 'disallowed'],
  ['enabled', 'disabled'],
  ['possible', 'impossible'],
  ['true', 'false'],
  ['yes', 'no'],
  ['up', 'down'],
];

const NEG_MARKERS = [
  'not', 'no', 'never', 'cannot', "can't", "won't", "don't", "doesn't",
  "didn't", "isn't", "aren't", "wasn't", "weren't", "shouldn't", "wouldn't",
  "couldn't",
];

export const heuristicComparator: ClaimComparator = {
  async compare(a, b) {
    const ta = normalize(a.text);
    const tb = normalize(b.text);
    const toksA = new Set(tokens(ta));
    const toksB = new Set(tokens(tb));
    const overlap = new Set([...toksA].filter((t) => toksB.has(t)));

    if (overlap.size < 2) return 'unknown';
    if (antonymConflict(ta, tb)) return 'disagree';
    if (negationAsymmetry(ta, tb)) return 'disagree';
    if (numericConflict(ta, tb, overlap)) return 'disagree';
    return 'agree';
  },
};

function normalize(text: string): string {
  return text.toLowerCase().replace(/[^a-z0-9\s.\-']/g, ' ');
}

function tokens(text: string): string[] {
  return text
    .split(/\s+/)
    .filter((t) => t && !STOPWORDS.has(t) && t.length >= 3);
}

function wordPresent(text: string, word: string): boolean {
  const escaped = word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`(^|[^a-z0-9'])${escaped}([^a-z0-9']|$)`, 'i').test(text);
}

function antonymConflict(a: string, b: string): boolean {
  return ANTONYMS.some(
    ([x, y]) =>
      (wordPresent(a, x) && wordPresent(b, y)) ||
      (wordPresent(a, y) && wordPresent(b, x)),
  );
}

function negationAsymmetry(a: string, b: string): boolean {
  const hasA = NEG_MARKERS.some((w) => wordPresent(a, w));
  const hasB = NEG_MARKERS.some((w) => wordPresent(b, w));
  return hasA !== hasB;
}

function numericConflict(a: string, b: string, overlap: Set<string>): boolean {
  const nearA = numbersNearWords(a, overlap);
  const nearB = numbersNearWords(b, overlap);
  for (const [word, numA] of nearA) {
    const match = nearB.find(([w]) => w === word);
    if (match && match[1] !== numA) return true;
  }
  return false;
}

function numbersNearWords(text: string, shared: Set<string>): [string, string][] {
  const re = /(\d+(?:\.\d+)?)\s*[a-z%]*\s+([a-z\-]+)/g;
  const out: [string, string][] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    const word = m[2]!;
    if (shared.has(word)) out.push([word, m[1]!]);
  }
  return out;
}

// ─── LLM-backed comparator ─────────────────────────────────────────────

export function llmComparator(provider: LLMProvider): ClaimComparator {
  return {
    async compare(a, b) {
      const prompt = `You are an analyst checking whether two factual claims from different sources contradict each other.

Claim A (from ${a.source}): "${a.text}"
Claim B (from ${b.source}): "${b.text}"

Reply with exactly one word: AGREE, DISAGREE, or UNKNOWN.`;
      const text = await provider.complete(prompt, { maxTokens: 8 });
      const verdict = text.trim().toUpperCase().split(/\s|\.|,/)[0] ?? '';
      if (verdict.startsWith('DISAGREE')) return 'disagree';
      if (verdict.startsWith('AGREE')) return 'agree';
      return 'unknown';
    },
  };
}
