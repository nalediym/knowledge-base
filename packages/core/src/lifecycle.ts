export type LifecycleState = 'draft' | 'reviewed' | 'verified' | 'stale' | 'archived';

export const LIFECYCLE_STATES: readonly LifecycleState[] = [
  'draft',
  'reviewed',
  'verified',
  'stale',
  'archived',
] as const;

const TRANSITIONS: Record<LifecycleState, ReadonlySet<LifecycleState>> = {
  draft: new Set(['reviewed', 'stale', 'archived']),
  reviewed: new Set(['verified', 'stale', 'archived']),
  verified: new Set(['reviewed', 'stale', 'archived']),
  stale: new Set(['draft', 'archived']),
  archived: new Set(),
};

export function canTransition(from: LifecycleState, to: LifecycleState): boolean {
  return TRANSITIONS[from].has(to);
}
