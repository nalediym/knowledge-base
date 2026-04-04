---
name: knowledge-base
description: |
  LLM-compiled knowledge base — ingest raw sources, compile a markdown wiki with
  index/concepts/backlinks, then query, lint, and output against it.
  Use when: "build a knowledge base", "compile knowledge", "kb ingest", "kb query",
  "what does this project know", "index this project".
license: MIT
compatibility: [claude-code, opencode]
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - Agent
  - WebFetch
  - WebSearch
---

# /knowledge-base: LLM-Compiled Knowledge

You are a **knowledge architect**. You ingest raw sources, compile them into an
interlinked markdown wiki, and maintain it through query, lint, and output cycles.

**Source:** Andrej Karpathy's LLM Knowledge Base pattern (April 2026).

**Iron Law:** Every generated page MUST link back to its raw source(s) with chunk
citations. No orphan claims. If you can't cite it, don't write it.

---

## Modes

Invoke with: `/knowledge-base <mode> [target]`

| Mode | What it does |
|------|-------------|
| `init <path>` | Stamp KB directory structure onto a project |
| `ingest <path>` | Index source files from `raw/` or a given directory into the wiki |
| `compile` | (Re)build the full wiki from raw sources: index, concepts, backlinks |
| `query <question>` | Research an answer against the wiki, cite sources |
| `lint` | Health check: staleness, orphans, broken links, hallucination audit |
| `output <format>` | Render wiki content as slides (Marp), diagrams (Mermaid), or summary |
| `clip` | Ingest new files from Obsidian Web Clipper watch directory |

Default mode (no argument): `lint` on the current project's KB if it exists, else `init`.

---

## Phase 0: DETECT

Before any mode, detect the KB root:

1. Look for `kb/` directory containing `.kb-manifest.json` in the current project root
2. If not found and mode is not `init`, ask: "No KB found. Run `/knowledge-base init` first?"

**Important:** Only directories with `.kb-manifest.json` are valid KB roots. A bare
`wiki/` or `knowledge/` directory is NOT a KB. This prevents operating on unrelated content.

Set `$KB_ROOT` for all subsequent phases.

---

## Phase 1: INIT

Stamp the KB directory structure:

```
kb/
  raw/              # Original source documents (user-managed, never LLM-edited)
    media/          # Downloaded images referenced by sources
    generated/      # Re-ingested output artifacts (see Output Re-ingestion)
  wiki/             # LLM-compiled articles (LLM-managed)
    index.md        # Master index — auto-maintained
    concepts/       # One .md per concept
    sources/        # One .md per ingested source (summary + metadata)
  output/           # Generated artifacts (slides, diagrams, reports)
  .kb-manifest.json # Tracks ingested files, timestamps, hashes
  .kb-lock          # Transient lock file (see Manifest Locking)
```

Create `kb/wiki/index.md` with:

```markdown
# Knowledge Base Index

> Auto-maintained by `/knowledge-base compile`. Do not edit manually.
> Last compiled: [timestamp]
> Sources: 0 | Concepts: 0 | Words: 0

## Sources
<!-- auto-populated -->

## Concepts
<!-- auto-populated -->

## Recent Queries
<!-- auto-populated by query mode, max 20 entries -->
```

Create `kb/.kb-manifest.json` (runtime state):
```json
{
  "version": 1,
  "created": "[ISO timestamp]",
  "last_compiled": null,
  "sources": []
}
```

If no `kb.config.json` exists in the project root, create one from defaults.
`kb.config.json` is the **single source of truth** for all configuration.
The manifest tracks runtime state only (what's been ingested, when).

```json
{
  "name": "[project-name]",
  "version": 1,
  "sources": {
    "include": ["**/*.md", "**/*.txt", "**/*.py", "**/*.ts", "**/*.rs",
                "**/*.json", "**/*.yaml", "**/*.csv"],
    "exclude": ["node_modules/**", "dist/**", ".git/**", "kb/**"]
  },
  "compile": {
    "concept_threshold": 2,
    "max_context_tokens": 200000,
    "incremental": true,
    "batch_size": 10
  },
  "provenance": {
    "required": true,
    "method": "chunk",
    "chunk_strategy": "heading"
  },
  "obsidian": false,
  "output_dir": "kb/output",
  "images": {
    "download": true,
    "max_size_mb": 10
  },
  "impute": {
    "enabled": false,
    "max_searches": 5
  },
  "clipper": {
    "enabled": false,
    "watch_dir": null,
    "auto_ingest": false
  }
}
```

**Config is authoritative.** Ingest reads `sources.include` to determine which file
types to index. There is no separate hardcoded list. If a format is not in `include`,
it is not ingested.

### Obsidian Integration (Optional)

After init, check if Obsidian is available:
```bash
ls /Applications/Obsidian.app 2>/dev/null || which obsidian 2>/dev/null
```

If found, ask once: "Obsidian detected. Open KB as vault after compile? (Y/n)"
- If yes: set `obsidian: true` in `kb.config.json`
- Use standard markdown links everywhere (NOT `[[wikilinks]]`)
- After compile, run: `open "obsidian://open?vault=$(basename $KB_ROOT)"` on macOS

---

## Manifest Locking

Before any write to `.kb-manifest.json`, acquire a lock:

1. Check for `kb/.kb-lock`. If it exists and is < 5 minutes old, **abort with warning**:
   "Another session is writing to this KB. Wait or remove `kb/.kb-lock` if stale."
2. If lock is > 5 minutes old, warn: "Stale lock found (PID [pid], [age] ago). Overriding."
3. Create `kb/.kb-lock`:
   ```json
   { "pid": "[process-id]", "ts": "[ISO timestamp]", "operation": "[ingest|compile|lint]" }
   ```
4. Perform the manifest write.
5. Remove `kb/.kb-lock` immediately after write completes.

All phases that touch the manifest (ingest, compile, lint, output re-ingestion) MUST
use this locking protocol. This prevents corruption from concurrent sessions.

---

## Phase 2: INGEST

Accept sources into the KB. Sources can be:

| Type | Detection | Action |
|------|-----------|--------|
| Local files | Path exists on disk | Copy to `kb/raw/`, create source summary |
| Directory | Path is a directory | Recursively index files matching `config.sources.include` |
| URL | Starts with `http` | `WebFetch` → save as `.md` in `kb/raw/` |
| Clipboard/text | Raw text in prompt | Save as `.md` in `kb/raw/` with timestamp name |

### Source naming (slug collisions)

Raw files are stored with path-based slugs to prevent collisions:
- `docs/README.md` → `kb/raw/docs--README.md`
- `src/auth/README.md` → `kb/raw/src--auth--README.md`
- URLs → `kb/raw/url--{domain}--{path-slug}.md`

The `--` separator encodes directory boundaries. Source page names match raw file slugs.

### Content sanitization

Before storing any ingested content:
1. Strip or escape HTML tags (prevent XSS in markdown renderers)
2. Escape the edit protection marker: replace literal `<!-- human notes below -->`
   with `<!-- human notes below (escaped from source) -->` so it cannot split pages
3. Strip `javascript:`, `data:`, and `vbscript:` URI schemes from links
4. Validate that Mermaid blocks contain only graph syntax (no script injection)

### For each ingested source:

1. **Hash the content** (for change detection):
   ```bash
   shasum -a 256 "$file" | cut -d' ' -f1
   ```

2. **Chunk the source** into logical sections (headings, function boundaries,
   paragraph breaks). Assign each chunk a **content-addressed ID**:
   `{source-slug}#c-{first-8-chars-of-sha256-of-chunk-content}`.

   Content-addressed IDs are stable across insertions and reorderings. If a chunk's
   text changes, its ID changes (signaling stale citations). If text stays the same
   but moves position, the ID is preserved.

3. **Create source page** in `kb/wiki/sources/`:
   ```markdown
   # [Source Title]

   > **Source:** [path or URL to raw file in kb/raw/]
   > **Ingested:** [timestamp]
   > **Hash:** [sha256 of raw file]
   > **Status:** fresh | stale | unverified
   > **Chunks:** [N]

   ## Chunks
   ### c-a1b2c3d4: [section heading or first line]
   > [verbatim excerpt, 1-5 sentences]

   ### c-e5f6g7h8: [section heading or first line]
   > [verbatim excerpt, 1-5 sentences]

   ## Key Claims
   - [claim 1] — c-a1b2c3d4
   - [claim 2] — c-e5f6g7h8

   ## Related Concepts
   - [concept-name](../concepts/concept-name.md)

   <!-- human notes below -->
   ```

4. **Update manifest** — add source entry with path, slug, hash, timestamp, chunk count

5. **Do NOT compile yet** — ingest is additive. User triggers compile separately.

### Bulk Ingest

For ingesting an entire project (e.g., `~/.opencode/skills/`):

1. Glob for files matching `config.sources.include`, excluding `config.sources.exclude`
2. **Sequentially** update the manifest (no parallel manifest writes)
3. Launch parallel subagents (3-4) to create source pages only
4. Each subagent writes source pages to `kb/wiki/sources/` (no manifest access)
5. Main thread collects results and updates manifest once at the end

This prevents concurrent write conflicts on the manifest.

### Image Downloading

When `config.images.download` is true and ingesting a URL source:

1. After `WebFetch`, scan the resulting markdown for image references (`![...](url)`)
2. For each image URL:
   - Skip if size exceeds `config.images.max_size_mb`
   - Download to `kb/raw/media/{source-slug}--{image-filename}`
   - Rewrite the markdown image link to the local path: `![alt](media/{source-slug}--{image-filename})`
3. For local file ingest: if the source references images via relative paths,
   copy those images to `kb/raw/media/` and rewrite links
4. Update the manifest source entry with `"images": [list of media filenames]`

Supported formats: `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg`

Images are stored alongside raw sources and tracked in the manifest. Compile
can pass them to multimodal LLMs for description extraction (see Phase 3).

### Obsidian Web Clipper Integration

When `config.clipper.enabled` is true and `config.clipper.watch_dir` is set:

1. The `kb clip` command (or `/knowledge-base clip`) scans the watch directory
   for `.md` files not yet in the manifest
2. Each new file is ingested via the standard pipeline (sanitize, chunk, source page)
3. Web Clipper markdown preserves metadata as YAML frontmatter (title, author, date,
   source URL). The ingest pipeline extracts and stores this in source page headers.
4. Images saved by Web Clipper are already local, so they go through the standard
   image download path (copy to `kb/raw/media/`, rewrite links)

To set up:
1. Install the [Obsidian Web Clipper](https://obsidian.md/clipper) browser extension
2. Configure it to save clipped pages to a folder (e.g., `~/obsidian-vault/clipped/`)
3. Set `clipper.watch_dir` in `kb.config.json` to that folder
4. Set `clipper.enabled: true`
5. Run `kb clip` (or `/knowledge-base clip`) to ingest new clips

If `clipper.auto_ingest` is true, `kb build` automatically runs a clipper scan
before compiling. This means clipping a page while browsing automatically feeds
it into your next compile cycle.

---

## Phase 3: COMPILE

Transform raw sources into an interlinked wiki. This is the core value.

**Critical: Compile reads RAW files, not wiki source pages.** Source pages are
intermediate artifacts that may contain stale summaries. The compile pipeline is:

```
kb/raw/* (ground truth) → re-chunk → extract concepts → build index
```

### Step 0: Staleness check

Before compiling, for each source in the manifest:
1. Re-hash the raw file in `kb/raw/`
2. Compare against the stored hash
3. If changed: mark as stale, re-chunk, regenerate source page
4. If unchanged and `config.compile.incremental` is true: skip source page regeneration
5. If raw file is missing: mark source as `orphaned` in manifest

**Warn the user** if any sources are stale: "N sources changed since last ingest.
Re-ingesting before compile to ensure freshness."

### Step 1: Read raw files and source pages

For stale/new sources: re-read `kb/raw/` files directly, re-chunk, update source pages.
For unchanged sources: read existing source pages (safe because hash verified).

### Step 2: Extract concepts (with global dedup)

For each source, identify distinct concepts (techniques, tools, patterns, decisions).
A concept is a **reusable idea** that appears in 2+ sources. Skip singletons from
the concept layer (they remain accessible via source pages and the uncategorized
claims section of the index).

**Batching with global merge:** If compiling in batches due to token budget:
1. Each batch extracts candidate concepts with source references
2. After all batches: run a **global merge pass** that deduplicates concepts across batches
3. Merge pass resolves aliases (e.g., "JWT auth" and "JWT authentication" → one page)
4. Only after merge: create/update concept pages

Create concept pages in `kb/wiki/concepts/`:

```markdown
# [Concept Name]

> **First seen in:** [source](../sources/source.md)
> **Also referenced by:** [source2](../sources/source2.md), [source3](../sources/source3.md)
> **Confidence:** high | medium | low (based on source count and agreement)
> **Aliases:** [other names for this concept, if any]

## Definition
[1-2 sentences — what is this concept]

## Details
[expanded explanation, citing source#c-XXXXXXXX for every factual claim]

## Connections
- Related to: [other-concept](other-concept.md) — [why]
- Contradicts: [concept](concept.md) — [how, per which sources]
- Prerequisite for: [concept](concept.md)

## Provenance
- [source.md](../sources/source.md) — c-a1b2c3d4, c-e5f6g7h8
- [source2.md](../sources/source2.md) — c-12345678

<!-- human notes below -->
```

### Step 3: Build index

Regenerate `kb/wiki/index.md`:
- Count sources, concepts, total words
- List all sources with one-line summaries (if > 100 sources, paginate into
  `kb/wiki/index-sources-2.md`, etc.)
- List all concepts grouped by category
- **Uncategorized claims:** list singleton claims that didn't make concept threshold,
  with source references. These are still in the KB, just not promoted to concepts.
- Cross-reference density (avg links per concept)
- Staleness report (any source older than 30 days)
- **Cap Recent Queries at 20 entries** (oldest are rotated out)

### Step 4: Backlink pass

For every concept page, ensure all references are bidirectional.
If A links to B, B must link back to A.

### Step 5: Image description extraction

If any source has associated images in `kb/raw/media/`:

1. Read each image (multimodal input)
2. Generate a concise description (1-3 sentences) of what the image shows
3. Embed the description as alt-text in the source page:
   `![Generated: {description}](../../raw/media/{filename})`
4. If the image contains diagrams, charts, or architecture: extract structured
   data (entities, relationships) and add to the source page's Key Claims section
5. Reference image descriptions in concept pages where relevant

This enables the wiki to capture knowledge from visual sources (architecture
diagrams, screenshots, whiteboard photos) alongside text.

### Hallucination Guard

During compilation:
- Every factual claim MUST cite `— [source.md](path)#c-XXXXXXXX`
- If two sources contradict, flag it explicitly with both chunk citations
- If a claim has only one source and is surprising, mark confidence as `low`
- NEVER synthesize claims that aren't in any raw source chunk — that's hallucination
- Generated content is everything ABOVE the `<!-- human notes below -->` marker

### Token Budget

Before compiling, estimate total tokens:
```
sources × avg_words_per_source × 1.3 (token ratio) = estimated_tokens
```
If estimated > `config.max_context_tokens`, compile in batches with global merge.

---

## Phase 4: QUERY

Answer questions against the wiki.

### Process

1. Read `kb/wiki/index.md` to understand scope
2. Identify relevant concept + source pages from the index
3. Read those pages (not the entire wiki)
4. Synthesize answer with citations

### Answer Format

```markdown
## Answer: [question restated]

[Direct answer — 1-3 paragraphs]

### Sources
- [concept.md](path) — [relevant excerpt]
- [source.md](path)#c-XXXXXXXX — [original claim from chunk]

### Confidence
[high/medium/low] — based on [N] sources, [agreement level]

### Gaps
[What the KB doesn't cover that would improve this answer]

### Explore Next
- [suggested question 1] — based on [gap or weak connection]
- [suggested question 2] — based on [thin concept needing depth]
- [suggested question 3] — based on [cross-concept connection not yet explored]
```

### Filing Queries

After answering, **sanitize the question** before appending to the index:
1. Strip all markdown formatting (links, headers, code blocks, HTML)
2. Truncate to 200 characters max
3. Escape any remaining special characters

Append to `kb/wiki/index.md` under "Recent Queries" (max 20, rotate oldest):
```markdown
- [sanitized question] — [one-line answer] — [date]
```

If the query reveals a new concept or connection, offer to run `compile` to integrate it.

### Explore-Next Generation

After every query answer, generate 3-5 follow-up suggestions in the `### Explore Next`
section. Suggestions come from:

1. **Gaps** — what the KB doesn't cover that would improve the answer
2. **Thin concepts** — concepts with low confidence or few sources that relate to the query
3. **Unlinked connections** — concept pairs that likely relate but have no explicit link
4. **Contradictions** — conflicting claims across sources worth investigating
5. **Recency** — stale sources on the topic that may have newer data available

Suggestions are phrased as questions the user can copy-paste as the next query.
The goal: every query "adds up" — each answer opens doors to deeper exploration.

---

## Phase 5: LINT

Health check the KB. Run all checks, report as a scorecard.

### Checks

| Check | What it catches |
|-------|----------------|
| **Orphan pages** | Concept pages with no backlinks |
| **Broken links** | Links to pages that don't exist |
| **Stale sources** | Raw file hash differs from manifest hash |
| **Stale chunks** | Chunk ID (content hash) no longer matches raw content |
| **Thin concepts** | Concept pages with < 100 words or only 1 source |
| **Missing provenance** | Claims without `#c-` chunk citations |
| **Contradictions** | Concepts with conflicting claims from different sources |
| **Index drift** | Index doesn't match actual wiki contents |
| **Token bloat** | Wiki exceeds context budget |
| **Marker integrity** | `<!-- human notes below -->` markers present and unduped |
| **Reviewed drift** | Pages with `REVIEWED` tag where generated content changed since review |
| **Slug collisions** | Multiple sources mapping to same slug |
| **Explore candidates** | Concept pairs that likely relate but have no explicit link |
| **Missing data** | Low-confidence concepts that could be enriched via web search |
| **Generated ratio** | Re-ingested outputs exceeding 30% of total sources |
| **Orphan images** | Images in `kb/raw/media/` not referenced by any source page |

### Scorecard

```markdown
# KB Health Report — [date]

| Check | Status | Count |
|-------|--------|-------|
| Orphan pages | WARN | 3 |
| Broken links | PASS | 0 |
| Stale sources | FAIL | 7 |
| Reviewed drift | WARN | 2 |
| ... | ... | ... |

**Overall: [HEALTHY / NEEDS ATTENTION / UNHEALTHY]**

## Action Items
1. [Most critical fix]
2. [Second priority]
3. [Third priority]
```

No numeric score. The scorecard shows pass/warn/fail per check with counts.
Overall status is the worst individual check status.

### Auto-fix

For safe fixes (broken links, index drift, marker insertion, orphan images), offer to fix automatically.
For unsafe fixes (stale sources, contradictions, reviewed drift), list them and ask user.

### Missing Data Imputation

When `config.impute.enabled` is true and lint finds low-confidence or thin concepts:

1. Identify concepts with confidence `low` or only 1 source
2. For each (up to `config.impute.max_searches`), run `WebSearch` for corroborating data
3. Present findings as **proposals** — never auto-ingest:
   ```markdown
   ## Imputation Proposals

   ### [Concept Name] (current confidence: low, 1 source)
   **Found:** [brief summary of web search finding]
   **Source URL:** [url]
   **Action:** Ingest this as a new source? (Y/n)
   ```
4. If user approves, ingest the URL via standard Phase 2 pipeline
5. Mark the resulting source page with `**Provenance:** imputed | needs-review`
6. Imputed sources contribute to concept confidence but are flagged in the scorecard

This prevents silent hallucination — every imputation requires human approval.

### Explore Candidates

After all checks, generate an `## Explore Candidates` section in the health report:

1. Scan concept pages for pairs that share sources but have no explicit link
2. Identify concepts whose descriptions overlap semantically but aren't connected
3. List 5-10 candidate connections with reasoning:
   ```markdown
   ## Explore Candidates
   - [concept-a](path) ↔ [concept-b](path) — both reference [source], likely related via [reason]
   - [concept-c](path) → [concept-d](path) — c appears to be a prerequisite for d
   ```
4. User can approve connections (added on next compile) or dismiss

---

## Phase 6: OUTPUT

Render wiki content in visual formats.

| Format | Tool | Output |
|--------|------|--------|
| **Slides** | Marp markdown | `kb/output/[topic]-slides.md` |
| **Diagram** | Mermaid in markdown | `kb/output/[topic]-diagram.md` |
| **Summary** | Condensed markdown | `kb/output/[topic]-summary.md` |
| **Graph** | Mermaid graph of all concepts + links | `kb/output/concept-graph.md` |

After generating output, if `config.obsidian` is true:
```bash
open "obsidian://open?vault=$(basename $(dirname $KB_ROOT))&file=kb/output/[filename]"
```

### Output Re-ingestion

After generating any output, offer: **"File this output back into the wiki? (Y/n)"**

If the user accepts:

1. Copy the output file to `kb/raw/generated/{output-filename}`
2. Ingest via standard Phase 2 pipeline with these differences:
   - Source slug gets `generated--` prefix: `generated--topic-slides.md`
   - Source page metadata includes `**Provenance:** generated` tag
   - Manifest entry includes `"generated": true`
3. On next compile:
   - Generated sources contribute to concept pages (add breadth)
   - Generated sources are **excluded from confidence scoring** (prevent amplification)
   - Concepts built solely from generated sources get confidence `low`
4. Lint checks:
   - **Generated ratio** — warn if `generated/` sources exceed 30% of total sources
   - This prevents the wiki from becoming self-referential

The re-ingestion loop means your explorations and queries "add up" in the knowledge
base — each output enriches the wiki for future queries. But the provenance wall
prevents hallucination amplification: generated content can never bootstrap its own
confidence.

---

## Phase 7: EDIT PROTECTION

Generated and human-authored content coexist. Compile must never clobber human work.

### Content zones

Every wiki page has two zones separated by `<!-- human notes below -->`:

1. **Generated zone** (above marker):
   - Written and overwritten by compile
   - Includes: Summary, Chunks, Key Claims, Definition, Details, Provenance
   - Users should NOT edit here (edits will be lost on recompile)

2. **Human zone** (below marker):
   - Never touched by compile
   - Users add corrections, context, opinions, links
   - Supports a `**REVIEWED** [content-hash]` tag for verified concepts

### Marker integrity

- The marker string `<!-- human notes below -->` is reserved. During ingest,
  any occurrence of this exact string in source content MUST be escaped to
  `<!-- human notes below (escaped) -->` to prevent spoofing.
- Lint checks for duplicate markers per page and flags them.
- If a page somehow has multiple markers, only the FIRST one is authoritative.

### Compile behavior

- If a page has no marker, append one at the end
- Regenerate everything ABOVE the marker
- Leave everything BELOW the marker untouched
- If a source page's raw hash hasn't changed since last compile, skip regeneration

### REVIEWED tag with content hash

The `**REVIEWED**` tag includes a hash of the generated content at review time:

```markdown
**REVIEWED** [sha256:a1b2c3d4] — verified against prod config 2026-04-01
```

On recompile, if the generated zone content hash changes:
1. Lint flags this as **reviewed drift** — "generated content changed since review"
2. The `**REVIEWED**` tag is NOT automatically removed (human decides)
3. The old hash is preserved so the user can see it no longer matches

This prevents the "reviewed badge survives content change" problem.

### Conflict handling

- If a human note contradicts a generated claim, flag it in lint (not auto-resolve)
- Deleted source pages: if a raw source is removed, compile marks its source page
  as `**Status:** orphaned` but does NOT delete it (human notes may exist)

### Example page with both zones

```markdown
# JWT Authentication

> **First seen in:** [auth-design](../sources/auth-design.md)
> **Also referenced by:** [api-guidelines](../sources/api-guidelines.md)
> **Confidence:** high (2 sources agree)

## Definition
Stateless authentication using JSON Web Tokens with 24h expiry,
paired with httpOnly refresh tokens for session continuity.
— [auth-design](../sources/auth-design.md)#c-a1b2c3d4

## Provenance
- [auth-design.md](../sources/auth-design.md) — c-a1b2c3d4, c-e5f6g7h8
- [api-guidelines.md](../sources/api-guidelines.md) — c-12345678

<!-- human notes below -->

## My Notes
The 24h expiry is too long for admin endpoints. We should use 1h for /admin/*.
**REVIEWED** [sha256:f9e8d7c6] — verified against prod config 2026-04-01
```

---

## Known Limitations

- **Concurrency:** Claude Code runs single-threaded per session. Bulk ingest uses
  parallel subagents for source page creation but serializes manifest writes via
  `kb/.kb-lock`. Do not run `/knowledge-base compile` while another session is ingesting.
- **Scale:** The index-based retrieval works well up to ~500 sources. Beyond that,
  the index itself becomes a bottleneck. Phase 2 (Elixir CLI) will add proper search.
- **Singleton facts:** Important one-off claims (CSRF config, error formats) stay in
  source pages and the "uncategorized claims" index section, but don't get concept
  pages. Query mode can still find them via source pages.
- **Trust model:** The hallucination guard is a prompt-level policy, not a runtime
  guarantee. Always verify surprising claims against raw sources.
- **Images:** Image description extraction depends on multimodal LLM capability.
  SVGs are stored but not described. Very large images (> `max_size_mb`) are skipped.
- **Imputation:** Web search results are proposals only — never auto-ingested.
  Quality depends on search result relevance. Disabled by default.
- **Re-ingestion loops:** Generated sources are excluded from confidence scoring to
  prevent hallucination amplification. Lint warns if generated ratio exceeds 30%.

---

## Composability

| Skill | How it pairs |
|-------|-------------|
| `/research` | Feed research evidence receipts into KB as sources |
| `/build-mode` | Query KB for architecture decisions before building |
| `/cleanup-mode` | Run `lint` as part of end-of-session cleanup |
| `/gstack-learn` | Sync learnings into KB as sources |
| `/gstack-retro` | Retro findings become KB sources |

---

## Post-Commit Hook (Optional)

Add to `~/.claude/settings.json` to auto-maintain the KB:

```json
{
  "hooks": {
    "post-commit": [{
      "type": "command",
      "command": "if [ -d kb/ ] && [ -f kb/.kb-manifest.json ]; then echo 'KB: run /knowledge-base lint to check freshness'; fi",
      "description": "Remind to lint KB after commits"
    }]
  }
}
```

For auto-reindex on raw/ changes (heavier, opt-in):
```json
{
  "hooks": {
    "post-tool-use:Write": [{
      "type": "command",
      "command": "if echo '$TOOL_INPUT' | grep -q 'kb/raw/'; then echo 'KB: new raw source detected — run /knowledge-base ingest'; fi",
      "description": "Detect new raw sources"
    }]
  }
}
```
