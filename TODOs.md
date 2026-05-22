# TODOs

Actionable next steps for the `knowledge-base` project. Ordered by readiness, not priority.

---

## 1. Land the TypeScript rewrite (`feat/typescript-rewrite`)

**Status:** branch is 14 commits ahead of `main`, ending in `15adfe4 chore: TS cutover — delete Elixir cli/, bump v0.3.0`.

The full surface has been re-implemented in TypeScript:

- Core: content-addressed chunking + manifest, debounced fs watcher, lifecycle sweep
- Store: SQLite FTS5 + `sqlite-vec` + RRF hybrid retrieval
- LLM: pluggable provider abstraction (heuristic / Ollama / OpenAI / Anthropic) + embeddings
- Adapters: markdown ingest, recursive directory ingest, session transcript ingest
- Inferrers: candidates approval workflow, cross-source contradiction detection, AI-consumable exports (llms.txt / jsonld / sitemap)
- MCP stdio server with 9 `kb_*` tools
- Full CLI command surface

**Next moves:**

- [ ] Open PR from `feat/typescript-rewrite` → `main`
- [ ] Run `/review` against `main` for a structural diff sweep
- [ ] `/ship` once review is clean
- [ ] After merge, bump the Homebrew formula's sha256 to point at the v0.3.0 tarball (mirror what `70efab5` did for 0.2.0)

---

## 2. Clean up `NOTES.md`

`NOTES.md` still describes `feat/contradiction-detection` as a P2 to-do, but the feature landed in `d97e9b6` (Merge feat/contradiction-detection). Either:

- [ ] Delete the file, or
- [ ] Repurpose it as a rolling notes file for the next planned feature

---

## 3. Issue #1 — Pre-work for streaming backlinks

The issue itself is deferred (YAGNI until KBs exceed ~5K pages), but the *trigger* is actionable now:

- [ ] Extend the `lint` scorecard to warn when total page count crosses a configurable threshold (default ~5K)
- [ ] Wire the warning to recommend the streaming backend migration described in the issue

This is small, self-contained, and means future-you gets paged automatically when the perf wall is in sight.

---

## 4. Housekeeping after the TS cutover

Once #1 merges:

- [ ] Update `README.md` install instructions if any path/binary names changed
- [ ] Verify the placeholder-guard CI still passes against the TS source
- [ ] Confirm `kb mcp` walk-up KB discovery still refuses on missing KB (the `8c4008a` behavior)
- [ ] Delete `cli/erl_crash.dump` if it survives the cutover

---

## Backlog (not yet scoped)

- Per-source confidence calibration tuning (4-factor + Ebbinghaus decay shipped in `88ba7f6` — collect feedback before retuning)
- Graph viewer enhancements beyond live SSE updates
- More inferrer types beyond contradictions (e.g. claim-strength, citation-recency)
