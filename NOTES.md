# feat/ai-consumable-exports — P1

**Priority:** P1 (low-effort, high-signal — makes KB instantly friendly to OTHER agents)
**Branch:** `feat/ai-consumable-exports`
**Effort:** ~half day

## Why

Pratiyush's KB gets hits from agents (not just humans) because it emits `/llms.txt` per llmstxt.org, `/graph.jsonld`, and per-page `.txt`/`.json` siblings. Any AI agent that encounters the site can consume it without scraping HTML.

## References

- Spec: https://llmstxt.org
- `~/.deep-research/sessions/kb-sota-2026/repos/llm-wiki/llmwiki/build.py` (Pratiyush)
- `~/.deep-research/sessions/kb-sota-2026/repos/llm-wiki/site/` in the live demo — see the actual outputs

## What to generate

| File | Spec | Purpose |
|------|------|---------|
| `kb/output/llms.txt` | llmstxt.org | Short index: title + one-line purpose + top-level links |
| `kb/output/llms-full.txt` | llmstxt.org | Flattened plain text, ~5MB cap. Paste into any LLM context |
| `kb/output/graph.jsonld` | schema.org JSON-LD | Typed Entity/Concept/Source graph |
| `kb/output/sitemap.xml` | sitemaps.org | Include `<lastmod>` on each URL |
| `kb/output/ai-readme.md` | — | AI-specific navigation instructions |
| `kb/wiki/*.txt` (sibling) | — | Plain text of each page |
| `kb/wiki/*.json` (sibling) | — | Structured metadata + body per page |

## Acceptance criteria

- [ ] `kb output llms-txt` writes `kb/output/llms.txt` per llmstxt.org spec
- [ ] `kb output llms-full` writes `kb/output/llms-full.txt` (5MB cap; truncate oldest)
- [ ] `kb output jsonld` writes `kb/output/graph.jsonld` with `@context: "https://schema.org"`, nodes typed as `Thing` | `Article` | `CreativeWork`
- [ ] `kb output sitemap` writes `kb/output/sitemap.xml` with `<lastmod>` from manifest timestamps
- [ ] `kb compile --ai-siblings` emits `.txt` and `.json` alongside each `.md` in `kb/wiki/`
- [ ] All outputs pass a basic linter (llms.txt validates; XML is well-formed)
- [ ] `kb output all` emits everything

## Nice-to-haves (follow-on)

- `<!-- kb:metadata -->` HTML comment in each generated page (parseable without fetching sibling `.json`) — Pratiyush does this as `<!-- llmwiki:metadata -->`
- RSS feed of newest sources (Pratiyush emits `/rss.xml`)

## Depends on

- Before: nothing
- Composes with: #1 MCP server (`kb_export` tool should return these formats)
