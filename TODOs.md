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

### C. Reposition KB as a context manager for AI agents (umbrella)

KB is no longer "just a wiki." The new framing is a **state-of-the-art
context manager** for AI agents and code sessions, applying current
context-engineering techniques. Everything below hangs off this.

- [ ] Rewrite the SKILL.md / README pitch around context engineering (current
      framing buries the lede: "LLM-compiled knowledge base" → should lead
      with the agent/session value)
- [ ] Define the surface: which MCP tools, which CLI commands, which
      session hooks. Today KB has `kb_*` MCP tools + session ingest; that
      becomes one face of a bigger system.

### D. Migrate hypha capabilities into knowledge-base

`nalediym/hypha` is paused and its features fold in here. The hypha repo
stays online (unarchived) until each piece migrates. Order is rough —
adapters first because they unblock everything else.

- [ ] **Adapters** — fold `gmail-mbox`, `google-drive-folder`,
      `google-calendar-ics`, `google-takeout`, `notion-export`, `dogsheep`
      from `hypha/packages/adapters/*` into `kb/packages/adapters/`
- [ ] **Identity resolver** — Fellegi-Sunter probabilistic record linkage
      from `hypha/packages/inferrers/identity-resolver` → KB inferrer
- [ ] **DLP scanner** — merge with KB's existing `redactor.ts`; hypha's
      pattern set is more thorough
- [ ] **Bitemporal graph** — "what did we know when" semantics from hypha's
      `store-sqlite`; evaluate vs. KB's current confidence + lifecycle
- [ ] **memify inferrer** — review and port if it survives the
      context-manager pitch
- [ ] Update hypha's README banner once each piece lands, with a link to
      the corresponding KB commit/PR

### E. Backlog (not yet scoped)

- Per-source confidence calibration tuning (4-factor + Ebbinghaus decay shipped
  in `88ba7f6` — collect real-world feedback before retuning)
- Graph viewer enhancements beyond live SSE updates
- More inferrer types beyond contradictions (claim-strength, citation-recency)
- Streaming-backlinks migration (issue #1) — gated by the page-count scorecard;
  do nothing until a real KB trips the warning
- Context-engineering primitives the rewrite probably needs: token-budget
  manager, retrieval ranker tuned for agent prompts, eviction/refresh policies,
  attention-aware summarization, scratchpad/working-memory layer

---

## Recently Shipped

> Trimmed when stale. Last refreshed 2026-05-22.

- **PR #15** — docs(readme): reposition KB as a context manager for AI agents (honest scope)
- **PR #10** — docs(todos): capture KB reposition + hypha migration plan
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
