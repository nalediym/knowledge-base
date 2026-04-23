# feat/contradiction-detection — P2

**Priority:** P2
**Branch:** `feat/contradiction-detection`
**Effort:** 1–2 days
**Goal:** `kb lint --conflicts` runs an LLM pass comparing claims across sources within each concept page and emits a contradictions report with chunk IDs on both sides.

## Why

SwarmVault surfaces contradiction edges in graph reports; Pratiyush has an LLM-powered lint rule. This turns KB from a passive store into an active truth-checker — high-signal feature for research use.

## Primary reference

- `~/.deep-research/sessions/kb-sota-2026/repos/swarmvault/` — contradiction edges in graph report
- `~/.deep-research/sessions/kb-sota-2026/repos/llm-wiki/llmwiki/lint/` — LLM-powered lint rule implementation

## Elixir implementation sketch

- Reuse Phase 3 compile's claim-extraction output (already available per SKILL.md)
- `kb lint --conflicts` iterates concept pages; for each, sends the extracted claims across sources to the LLM
- Provider-agnostic: heuristic / Ollama / OpenAI / Anthropic — route via `kb.config.json: llm.provider`
- Output: `kb/output/contradictions-YYYY-MM-DD.md`

## Output format

```markdown
# Contradictions — 2026-04-23

## concept: transformers.md

- Claim A: "Attention complexity is O(n²)"
  - Source: papers/vaswani-2017.md#c-a3f2b8e1
- Claim B: "Attention can be O(n) with sparse patterns"
  - Source: blog/flash-attention.md#c-92db71a4
- Resolution: not a true contradiction — scope differs (dense vs. sparse). Consider annotating.
```

## Acceptance criteria

- [ ] `kb lint --conflicts` iterates every concept page and runs an LLM pass per page
- [ ] Only checks pages in `reviewed` or `verified` lifecycle (when #10 is present; fall back to "all non-draft" otherwise)
- [ ] Output lands at `kb/output/contradictions-YYYY-MM-DD.md` with chunk IDs on both sides
- [ ] Works with heuristic provider (no API key) via keyword-overlap fallback — flags sentences with opposing keywords
- [ ] Config: `kb lint --conflicts --provider ollama` routes to Ollama when available
- [ ] Fixture test: concept page with planted contradiction → detected in output
- [ ] Unit test: no false positives on a page with agreeing sources

## Depends on

- **Before:** Phase 3 compile's claim extraction (already present in KB)
- **Pairs with:** #10 lifecycle (only scan reviewed+ pages), #11 hybrid-retrieval (efficient cross-page reads)
