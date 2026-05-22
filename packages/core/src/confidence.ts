export type QualityLabel =
  | 'official'
  | 'documentation'
  | 'peer_reviewed'
  | 'paper'
  | 'blog'
  | 'tutorial'
  | 'forum'
  | 'session_transcript'
  | 'llm_generated'
  | 'unknown';

const QUALITY_MAP: Record<string, number> = {
  official: 1.0,
  documentation: 1.0,
  peer_reviewed: 0.9,
  paper: 0.9,
  blog: 0.7,
  tutorial: 0.7,
  forum: 0.5,
  session_transcript: 0.5,
  llm_generated: 0.3,
  unknown: 0.4,
};

const LEGACY_MAP: Record<string, number> = {
  high: 0.85,
  medium: 0.55,
  low: 0.25,
};

const DEFAULT_WEIGHTS = {
  sources: 0.25,
  quality: 0.25,
  recency: 0.25,
  crossrefs: 0.25,
};

const DEFAULT_TAU: Record<string, number> = {
  code: 90,
  concept: 365,
  news: 30,
  default: 180,
};

const LOG_NORM = Math.log(11);

export interface ConfidenceInput {
  sources?: number;
  sourceQuality?: ReadonlyArray<number | string>;
  ageDays?: number;
  backlinks?: number;
  contentType?: string;
}

export interface ConfidenceConfig {
  weights?: Partial<typeof DEFAULT_WEIGHTS>;
  decayTauDays?: Record<string, number>;
}

export function qualityValue(q: number | string): number {
  if (typeof q === 'number') return clamp(q);
  const k = q.trim().toLowerCase();
  return QUALITY_MAP[k] ?? 0.4;
}

function avgQuality(list: ReadonlyArray<number | string> | undefined): number {
  if (!list || list.length === 0) return 0.4;
  const sum = list.reduce<number>((acc, q) => acc + qualityValue(q), 0);
  return sum / list.length;
}

export function score(input: ConfidenceInput, config: ConfidenceConfig = {}): number {
  const weights = { ...DEFAULT_WEIGHTS, ...(config.weights ?? {}) };
  const taus = { ...DEFAULT_TAU, ...(config.decayTauDays ?? {}) };
  const tau = taus[input.contentType ?? 'default'] ?? taus.default ?? 180;

  const sources = Math.max(input.sources ?? 0, 0);
  const ageDays = Math.max(input.ageDays ?? 0, 0);
  const backlinks = Math.max(input.backlinks ?? 0, 0);

  const fSources = Math.log(sources + 1) / LOG_NORM;
  const fQuality = avgQuality(input.sourceQuality);
  const fRecency = Math.exp(-ageDays / tau);
  const fCross = Math.log(backlinks + 1) / LOG_NORM;

  const raw =
    weights.sources * fSources +
    weights.quality * fQuality +
    weights.recency * fRecency +
    weights.crossrefs * fCross;

  return round2(clamp(raw));
}

export function shimLegacy(value: unknown): number | null {
  if (typeof value !== 'string') return null;
  const k = value.trim().toLowerCase();
  return LEGACY_MAP[k] ?? null;
}

export function bucket(s: number): 'high' | 'medium' | 'low' {
  if (s >= 0.7) return 'high';
  if (s >= 0.4) return 'medium';
  return 'low';
}

function clamp(x: number): number {
  if (x < 0) return 0;
  if (x > 1) return 1;
  return x;
}

function round2(x: number): number {
  return Math.round(x * 100) / 100;
}
