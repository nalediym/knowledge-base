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
| `init <path>` | Stamp KB directory structure. Auto-detects Obsidian vaults (walks up for `.obsidian/`). |
| `ingest <path>` | Index source files from `raw/` or a given directory into the wiki |
| `ingest --sessions` | Mine agent transcripts (`~/.claude/projects/*`, `~/.codex/sessions/*`) into `kb/raw/sessions/` with secret redaction |
| `compile` | (Re)build the wiki; new concepts land in `candidates/` for review. Options: `--approve`, `--ai-siblings` |
| `approve [name]` | Promote `candidates/<name>.md` → `concepts/<name>.md` (`--all`, `--force`) |
| `review <page>` · `verify <page>` · `archive <page>` | Lifecycle transitions (draft → reviewed → verified → stale → archived) |
| `query <question>` | Hybrid retrieval (SQLite FTS5 + optional Ollama embeddings via RRF). Falls back to grep if no index. |
| `index [--embeddings]` | Build `kb/.index/search.sqlite` for fast hybrid queries |
| `lint` / `lint --conflicts` | Health checks; `--conflicts` runs LLM contradiction detection across source claims |
| `output <format>` | Render as slides (Marp), diagrams (Mermaid), llms.txt, JSON-LD, sitemap, or graph |
| `graph serve` | Launch interactive graph viewer (Plug+SSE live updates) on localhost |
| `watch [--hook]` | Debounced poll of raw/session dirs; `--hook` installs a Claude Code SessionStart hook |
| `schedule --platform {macos\|linux\|windows}` | Emit launchd/systemd/task.xml scaffolds |
| `mcp` | Launch MCP stdio server exposing 9 `kb_*` tools (see Phase 8) |
| `obsidian:daily <msg>` · `obsidian:base <query>` · `obsidian:status` | Obsidian Official CLI bridges |
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
  },
  "ingest": {
    "sessions": {
      "agents": ["claude", "codex"]
    },
    "redaction": {
      "extra_patterns": []
    }
  },
  "watch": {
    "paths": ["kb/raw", "~/.claude/projects"],
    "debounce_ms": 500,
    "auto_compile": true,
    "auto_commit": false
  },
  "schedule": {
    "cadence": "daily",
    "time": "04:30",
    "platform": "auto"
  },
  "candidates": {
    "overflow_threshold": 20
  },
  "confidence": {
    "weights": {
      "sources": 0.25,
      "quality": 0.25,
      "recency": 0.25,
      "crossrefs": 0.25
    },
    "decay_tau_days": {
      "code": 90,
      "concept": 365,
      "news": 30,
      "default": 180
    }
  },
  "lifecycle": {
    "stale_after_days": 90,
    "drift_action": "demote"
  },
  "in_vault": false,
  "vault_path": null,
  "obsidian_cli": false
}
```

**Config is authoritative.** Ingest reads `sources.include` to determine which file
types to index. There is no separate hardcoded list. If a format is not in `include`,
it is not ingested.

### Obsidian Integration (Optional)

**Vault auto-detection.** On `init`, walk up from cwd looking for `.obsidian/`. If found, ask once: "Place `kb/` inside this vault at `<vault>/kb/`? (Y/n)". If yes, write `kb/` there and set `in_vault: true, vault_path: "<vault>"`. `kb init --yes` accepts defaults; `kb init --no-vault` skips detection.

**Obsidian Official CLI** (v1.12.0+, on PATH as `obsidian`). On `init`, if the CLI is present AND the desktop app responds, flip `obsidian_cli: true`. After every compile, append a daily-note entry via `obsidian daily:append "KB: compiled N pages"`. Errors are swallowed — compile never fails on optional integration.

Bridge commands exposed:
- `kb obsidian:daily <message>` → wraps `obsidian daily:append`
- `kb obsidian:base <query>` → wraps `obsidian base:query` (Obsidian Bases)
- `kb obsidian:status` → show binary path + reachability

Fallback when CLI missing: `open "obsidian://open?vault=$(basename $KB_ROOT)"` (macOS URL scheme).

Use standard markdown links everywhere (NOT `[[wikilinks]]`) — compatibility with non-Obsidian readers is a feature.

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

---

## Phase 2.5: SESSION TRANSCRIPT INGESTION

`kb ingest --sessions` mines agent transcripts and turns them into regular wiki sources. Runs silently — no prompt required.

**Supported agents** (stub returns `:not_installed` when the path is missing):
- Claude Code — `~/.claude/projects/*/*.jsonl`
- Codex CLI — `~/.codex/sessions/**/*.jsonl`, `~/.codex/projects/**/*.jsonl`
- Gemini CLI, Cursor workspaceStorage, Copilot Chat/CLI — stubbed (framework in place)

**Redaction is non-optional.** Before writing any transcript:
- `sk-[A-Za-z0-9]{20,}` → `[REDACTED_API_KEY]`
- `ghp_[A-Za-z0-9]{36}` → `[REDACTED_GH_TOKEN]`
- Named credentials (`api_key`, `token`, `bearer`, `password`, `secret`) → `[REDACTED_CREDENTIAL]`
- Email addresses → `[REDACTED_EMAIL]`
- Literal `$USER` (from environment) → `USER`
- Plus any regex in `ingest.redaction.extra_patterns`

**Output:** `kb/raw/sessions/<project-slug>/YYYY-MM-DD-<first-8-of-session-id>.md` with frontmatter `source_type: session, agent, project, session_id, model`.

Session sources flow through the normal compile pipeline — they become wiki pages under `sources/` and participate in concept extraction, backlinks, confidence, and lifecycle.

---

## Phase 3.5: CANDIDATES / APPROVAL

Compile no longer writes new concepts directly to `kb/wiki/concepts/`. New concepts land in `kb/wiki/candidates/` for human review. Existing concepts are updated in place.

- `kb compile --approve` — prints per-candidate diff against any existing concept (marked `NEW` when none), then stages.
- `kb approve <name>` — move `candidates/<name>.md` → `concepts/<name>.md`. Refuses if target exists (`--force` overrides).
- `kb approve --all` — bulk-promote; skips collisions.
- Lint warns when `candidates/` > `candidates.overflow_threshold` (default 20) — inbox overflow signal.

**Why:** prevents LLM-extracted concepts from silently overwriting human-edited ones. The moat is the `<!-- human notes below -->` marker + REVIEWED `[sha256:]` tag; candidates/ is its staging lane.

---

## Phase 5.5: LIFECYCLE + CONFIDENCE

Every wiki page carries `lifecycle` and `confidence` frontmatter. Both evolve over time — compile sweeps both on every run.

### Lifecycle (5-state machine)

```
draft ──kb review──→ reviewed ──kb verify──→ verified
                      │                          │
                      │           (hash drift) ──┘
                      │                          ↓
                      └──(90d unvisited)────→ stale ──kb archive──→ archived
```

- `kb review <page>` — draft → reviewed
- `kb verify <page>` — reviewed → verified; stamps `REVIEWED [sha256:<body-hash>]`
- `kb archive <page>` — any → archived
- Compile auto-demotes pages older than `lifecycle.stale_after_days` (default 90) to `stale`.
- Drift: if a `verified` page's body hashes differently than its `REVIEWED` stamp, demote to `reviewed` (or lint-warn, per `lifecycle.drift_action`).
- Pages without `lifecycle:` frontmatter are treated as `draft` and backfilled on first compile.

### Confidence (4-factor with Ebbinghaus decay)

Replaces the old `confidence: high|medium|low` string with numeric `0.0–1.0`:

```
confidence = w_s · log(sources + 1)
           + w_q · avg(source_quality)
           + w_r · exp(-age_days / τ)
           + w_x · log(backlinks + 1)
```

Weights and τ per content-type are config-driven (see `kb.config.json`). Legacy string values shim to 0.85/0.55/0.25 on first compile. `kb query` surfaces the score in answer metadata. `kb lint` flags concepts with confidence < 0.3.

### Contradictions (`kb lint --conflicts`)

Runs per concept page: compare extracted claims across its referenced sources. Flags disagreements.

- Providers: `heuristic` (no-network default — keyword overlap + negation detection + antonym pairs + numeric disagreement), `ollama`, `openai`, `anthropic`. Configure via `--provider`.
- Only scans pages in `reviewed` or `verified` lifecycle.
- Output: `kb/output/contradictions-YYYY-MM-DD.md` with chunk IDs on both sides of each flagged claim.

---

## Phase 4.5: HYBRID RETRIEVAL

`kb query` uses a SQLite FTS5 index + optional Ollama embeddings, merged via reciprocal-rank fusion. Build it first:

```bash
kb index                # FTS5 only — runs locally, no network
kb index --embeddings   # adds Ollama embeddings (nomic-embed-text) when 11434 is reachable
kb index --include-raw  # also index kb/raw/ (default: wiki only)
```

Incremental via mtime — only changed files are reprocessed. Falls back to grep when `kb/.index/search.sqlite` is missing, so fresh vaults work before first index.

RRF formula: `score = Σ 1 / (k + rank_i)` with `k = 60`. Per-page hits from FTS and semantic tables are merged — each contributes independently. Query output marks the source (`[fts 0.0163 ...]` vs `[semantic ...]`).

**Escript caveat:** the `exqlite` NIF isn't bundled into a bare escript. When running `./kb query` as an escript, FTS falls back to grep with a one-line notice. For full hybrid retrieval, invoke via `mix run -e 'Kb.CLI.main(["query", "..."])'` or use the MCP server (which runs under Mix).

---

## Phase 6.5: AI-CONSUMABLE EXPORTS

For public-facing KBs or agent-consumer interop:

| Command | Writes | Purpose |
|---|---|---|
| `kb output llms-txt` | `kb/output/llms.txt` | llmstxt.org-spec index (H1 title, blockquote summary, H2 sections) |
| `kb output llms-full` | `kb/output/llms-full.txt` | Flattened all pages, 5 MB cap |
| `kb output jsonld` | `kb/output/graph.jsonld` | schema.org graph (`DefinedTerm` / `CreativeWork` / `CollectionPage`) |
| `kb output sitemap` | `kb/output/sitemap.xml` | `<loc>` + `<lastmod>` from mtime |
| `kb output all` | all four | — |
| `kb build --ai-siblings` | `.txt` + `.json` next to every wiki `.md` | Per-page AI artifacts |

The `.json` siblings include `{path, title, category, frontmatter, summary, lastmod, body, chunks}` — one-shot consumable by other agents.

---

## Phase 7.5: GRAPH VIEWER

`kb graph serve [--port 4000] [--no-open]` starts a local Plug+Cowboy server at `http://localhost:4000` with an interactive source↔concept graph. SVG + hand-rolled force layout, no CDN dependencies.

- Node coloring by type (source=blue, concept=green, candidate=yellow, stale=gray).
- Hover → chunk-citation tooltip.
- Click → open file via `open`/`xdg-open`.
- Live updates: SSE stream at `/events` pushes deltas when `kb watch` or compile publishes to the `kb:graph` PubSub topic.

Useful for exploring big KBs and demoing the moat (chunk citations visible on hover).

---

## Phase 8: MCP SERVER

`kb mcp` launches a Model Context Protocol stdio server exposing the KB to any MCP-capable client (Claude Code, Claude Desktop, Cursor, Cline, Codex, Continue). JSON-RPC 2.0 over stdio, stderr for logs.

### Tools (9)

| Tool | Args | Returns |
|---|---|---|
| `kb_query` | `question`, `max_pages?` | Answer + page refs + chunk citations |
| `kb_search` | `term`, `include_raw?` | Matching pages with snippets |
| `kb_list_sources` | `project?` | All ingested sources + metadata |
| `kb_read_page` | `path` (path-traversal guarded) | Page content + frontmatter |
| `kb_lint` | — | Health scorecard JSON |
| `kb_ingest` | `path` | Ingest result (file count, slug map) |
| `kb_compile` | `dry_run?` | Compile summary |
| `kb_export` | `format` (llms-txt, jsonld, marp, mermaid) | Rendered artifact or path |
| `kb_dashboard` | — | Counts by type / lifecycle / confidence |

### Registration

**Claude Code** (`~/.claude/settings.json` for global, or a project-local `.mcp.json` for per-project):

```json
{
  "mcpServers": {
    "kb": {
      "command": "/opt/homebrew/bin/kb",
      "args": ["mcp"]
    }
  }
}
```

**Claude Desktop** (`claude_desktop_config.json`): same shape.

### KB discovery (2026 convention)

**Do NOT use `${workspaceFolder}` in the `env` block.** Client support for that variable is inconsistent across MCP clients (VS Code issue #251263; open as of April 2026). Per the 2026 MCP best-practices guide, use absolute paths only.

Instead, `kb mcp` discovers the KB on every tool call:

1. If `$KB_ROOT` is set AND contains `kb/.kb-manifest.json` → use it.
2. Else walk up from the server's process `cwd` looking for `kb/.kb-manifest.json`. Stops at `$HOME` or the filesystem root.
3. Else: tool calls fail with a structured error (`"no KB found ..."`) — the server **never** silently operates on a synthesized default.

This matches the Obsidian-MCP ecosystem convention (cwd-walk-up or explicit path, no variable expansion) as of April 2026.

**Per-project scoping.** For multi-KB workflows, drop a project-local `.mcp.json`:

```json
{
  "mcpServers": {
    "kb": {
      "command": "/opt/homebrew/bin/kb",
      "args": ["mcp"],
      "env": { "KB_ROOT": "/absolute/path/to/this/project" }
    }
  }
}
```

Absolute path — no shell expansion, no client-specific variables.

**Path-traversal guard.** All `path` arguments reject `..`, null bytes, and absolute paths outside the discovered root.

### Why this matters

Without the MCP server, Claude has to invoke `/knowledge-base` as a skill and re-read SKILL.md every session. With `kb mcp`, the 9 tools are available as first-class MCP calls — faster, stateless, composable with other MCP servers (Obsidian, GitHub, filesystem), and queryable from non-Anthropic clients.

---

## Phase 9: WATCH + SCHEDULE

For auto-ingest of new raw sources and agent transcripts:

- `kb watch [--poll-ms 500]` — GenServer that polls `kb/raw/` + session dirs with debounce. On settle, calls `kb ingest` per changed file.
- `kb watch --hook` — installs a Claude Code SessionStart hook in `~/.claude/settings.json` that runs `kb ingest --sessions` at session start. Idempotent; backs up the file once before modifying.
- `kb schedule --platform macos` — emits a `launchd.plist` scaffold.
- `kb schedule --platform linux` — emits a `systemd.service` + `.timer` pair.
- `kb schedule --platform windows` — emits a Task Scheduler `task.xml` + install command.

Time window from `schedule.time` in `kb.config.json` (default `04:30`).

Watch is the "set and forget" story for keeping KB fresh: new agent sessions → redacted → wiki. No manual re-ingest.
