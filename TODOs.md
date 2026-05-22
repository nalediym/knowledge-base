# TODOs

Next actionable steps for the `knowledge-base` project. This file is the single
source of truth — kept in sync with merged work.

> **Maintenance.** This file is kept current automatically by the
> `sync-todos` GitHub Action (see `.github/workflows/sync-todos.yml`).
> Every merged PR is appended to **Recently Shipped**. To also remove an
> open item, add a line to the PR body:
>
> ```
> Closes-TODO: <substring of the ### heading>
> ```
>
> e.g. `Closes-TODO: Homebrew tap` removes the matching `### A.` section.

---

## Open

### B. Backlog (not yet scoped)

- Per-source confidence calibration tuning (4-factor + Ebbinghaus decay shipped
  in `88ba7f6` — collect real-world feedback before retuning)
- Graph viewer enhancements beyond live SSE updates
- More inferrer types beyond contradictions (claim-strength, citation-recency)
- Streaming-backlinks migration (issue #1) — gated by the page-count scorecard;
  do nothing until a real KB trips the warning

---

## Recently Shipped

> Trimmed when stale. Last refreshed 2026-05-22.

- **PR #9** — docs(readme): document brew tap oven-sh/bun prereq
- **PR #8** — fix(brew): qualify bun dep so brew can auto-tap oven-sh/bun
- **PR #6** — `kb lint` page-count scorecard. Closes the "trigger to act"
  path from issue #1.
- **PR #5** — Post-TS-cutover cleanup. Dropped `NOTES.md` (stale) and the
  Elixir escript/exqlite caveat from `SKILL.md`.
- **PR #4** — Homebrew formula `sha256` bumped to the real v0.3.0 tarball
  hash (`b797fd76…df03`).
- **PR #3** — TypeScript rewrite landed. Deletes the Elixir `cli/` tree,
  ships v0.3.0 with 7 packages (`core`, `store-sqlite`, `llm`, `adapters`,
  `inferrers`, `mcp`, `cli`).
- **PR #2** — This file (`TODOs.md`) introduced as the project's rolling
  next-up list.
