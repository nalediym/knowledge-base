import type { LifecycleState } from './lifecycle.ts';

const DEFAULT_STALE_AFTER_DAYS = 90;
const MS_PER_DAY = 24 * 60 * 60 * 1000;

export interface SweepInput {
  current: LifecycleState;
  lastSeen: Date | null;
  bodyHash: string;
  reviewedStamp?: string;
  staleAfterDays?: number;
  now?: Date;
}

export function sweep(input: SweepInput): LifecycleState {
  const { current, lastSeen, bodyHash, reviewedStamp } = input;
  const staleAfter = input.staleAfterDays ?? DEFAULT_STALE_AFTER_DAYS;
  const now = input.now ?? new Date();

  if (current === 'archived') return 'archived';

  if (current === 'verified' && reviewedStamp && reviewedStamp !== bodyHash) {
    return 'reviewed';
  }

  const ageDays = lastSeen
    ? (now.getTime() - lastSeen.getTime()) / MS_PER_DAY
    : Number.POSITIVE_INFINITY;

  if (ageDays > staleAfter && (current === 'draft' || current === 'reviewed' || current === 'verified')) {
    return 'stale';
  }

  return current;
}
