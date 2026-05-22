import {
  existsSync,
  mkdirSync,
  readdirSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { dirname, join } from 'node:path';

const CANDIDATES_REL = 'kb/wiki/candidates';
const CONCEPTS_REL = 'kb/wiki/concepts';

export interface CandidatesContext {
  kbRoot: string;
}

export type PageKind = 'candidate' | 'existing';

export interface TargetPath {
  kind: PageKind;
  path: string;
}

export interface PromoteOk {
  ok: true;
  from: string;
  to: string;
}

export interface PromoteErr {
  ok: false;
  reason: 'missing_candidate' | 'concept_exists';
  path: string;
}

export type PromoteResult = PromoteOk | PromoteErr;

export interface PromoteAllResult {
  promoted: number;
  skipped: number;
  failed: number;
}

export function targetPath(name: string, ctx: CandidatesContext): TargetPath {
  const concept = join(ctx.kbRoot, CONCEPTS_REL, `${name}.md`);
  if (existsSync(concept)) {
    return { kind: 'existing', path: concept };
  }
  return { kind: 'candidate', path: join(ctx.kbRoot, CANDIDATES_REL, `${name}.md`) };
}

export function writeConcept(
  name: string,
  content: string,
  ctx: CandidatesContext,
): TargetPath {
  const t = targetPath(name, ctx);
  mkdirSync(dirname(t.path), { recursive: true });
  writeFileSync(t.path, content);
  return t;
}

export function listCandidates(ctx: CandidatesContext): string[] {
  const dir = join(ctx.kbRoot, CANDIDATES_REL);
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter((f) => f.endsWith('.md'))
    .map((f) => f.replace(/\.md$/, ''))
    .sort();
}

export function promoteOne(
  name: string,
  ctx: CandidatesContext & { force?: boolean },
): PromoteResult {
  const candidate = join(ctx.kbRoot, CANDIDATES_REL, `${name}.md`);
  const concept = join(ctx.kbRoot, CONCEPTS_REL, `${name}.md`);

  if (!existsSync(candidate)) {
    return { ok: false, reason: 'missing_candidate', path: candidate };
  }
  if (existsSync(concept) && !ctx.force) {
    return { ok: false, reason: 'concept_exists', path: concept };
  }

  mkdirSync(dirname(concept), { recursive: true });
  if (existsSync(concept)) unlinkSync(concept);
  renameSync(candidate, concept);

  return { ok: true, from: candidate, to: concept };
}

export function promoteAll(
  ctx: CandidatesContext & { force?: boolean },
): PromoteAllResult {
  let promoted = 0;
  let skipped = 0;
  let failed = 0;
  for (const name of listCandidates(ctx)) {
    const r = promoteOne(name, ctx);
    if (r.ok) promoted += 1;
    else if (r.reason === 'concept_exists') skipped += 1;
    else failed += 1;
  }
  return { promoted, skipped, failed };
}
