# feat/lifecycle-state-machine — P2

**Priority:** P2
**Branch:** `feat/lifecycle-state-machine`
**Effort:** 1 day
**Goal:** add a 5-state lifecycle (`draft → reviewed → verified → stale → archived`) to every wiki page, with 90-day auto-stale and drift-demotion that composes with the existing `REVIEWED [sha256:]` tag.

## Why

KB already has `REVIEWED [sha256:]` for verified content but no state model for the rest. Pratiyush's 5-state model is the standard — lets lint, compile, and dashboards reason about page health.

## Primary reference

- `~/.deep-research/sessions/kb-sota-2026/repos/llm-wiki/llmwiki/lifecycle.py` — 5-state machine + 90-day auto-stale
- `~/.deep-research/sessions/kb-sota-2026/repos/llm-wiki/docs/lifecycle.md` — state transition diagram

## State machine

```
draft ──kb review──→ reviewed ──kb verify──→ verified
  │                    │                        │
  │                    │                        ├─(hash drift)──→ reviewed
  │                    │                        │
  └─(90d unvisited)────┴────────────────────────┴──→ stale ──kb archive──→ archived
```

## Elixir implementation sketch

- Frontmatter: `lifecycle: draft|reviewed|verified|stale|archived`
- `kb review <page>` — draft → reviewed
- `kb verify <page>` — reviewed → verified; stamps `REVIEWED [sha256:<hash>]`
- `kb archive <page>` — any → archived
- On `kb compile`: pages where `last_seen > 90d` auto-demote to `stale` (configurable via `kb.config.json: lifecycle.stale_after_days`)
- Drift detection: if `REVIEWED [sha256:X]` exists and current hash ≠ X, demote verified → reviewed (or lint-warn — config choice)

## Acceptance criteria

- [ ] Every wiki page frontmatter has `lifecycle: <state>`; new pages default to `draft`
- [ ] `kb review`, `kb verify`, `kb archive` transition correctly and reject illegal transitions
- [ ] Compile auto-stale threshold is config-driven; test with fixture of 91-day-old page
- [ ] `kb lint` surfaces stale count per project
- [ ] Composes with existing `REVIEWED [sha256:]` — hash mismatch triggers verified → reviewed
- [ ] Backwards-compat: pages without `lifecycle:` are treated as `draft` on first compile

## Depends on

- **Before:** ideally #7 candidates-approval (shared frontmatter namespace) — but can ship independently and merge cleanly
- **Used by:** #13 contradiction-detection (contradictions should only flag `reviewed`+ pages)
