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

**Iron Law:** Every generated page MUST link back to its raw source(s). No orphan claims.
If you can't cite it, don't write it.

---

## Modes

Invoke with: `/knowledge-base <mode> [target]`

| Mode | What it does |
|------|-------------|
| `init <path>` | Stamp KB directory structure onto a project |
| `ingest <path>` | Index source files from `raw/` or a given directory into the wiki |
| `compile` | (Re)build the full wiki: index, concepts, backlinks, cross-links |
| `query <question>` | Research an answer against the wiki, cite sources |
| `lint` | Health check: staleness, orphans, broken links, hallucination audit |
| `output <format>` | Render wiki content as slides (Marp), diagrams (Mermaid), or summary |

Default mode (no argument): `lint` on the current project's KB if it exists, else `init`.

---

## Phase 0: DETECT

Before any mode, detect the KB root:

1. Look for `kb/` directory in the current project root
2. If not found, look for `wiki/` or `knowledge/` directory
3. If not found and mode is not `init`, ask: "No KB found. Run `/knowledge-base init` first?"

Set `$KB_ROOT` for all subsequent phases.

---

## Phase 1: INIT

Stamp the KB directory structure:

```
kb/
  raw/              # Original source documents (user-managed, never LLM-edited)
  wiki/             # LLM-compiled articles (LLM-managed)
    index.md        # Master index — auto-maintained
    concepts/       # One .md per concept
    sources/        # One .md per ingested source (summary + metadata)
  output/           # Generated artifacts (slides, diagrams, reports)
  .kb-manifest.json # Tracks ingested files, timestamps, hashes
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
<!-- auto-populated by query mode -->
```

Create `kb/.kb-manifest.json` (runtime state, tracks what's been ingested):
```json
{
  "version": 1,
  "created": "[ISO timestamp]",
  "last_compiled": null,
  "sources": []
}
```

If no `kb.config.json` exists in the project root, create one from defaults:
```json
{
  "name": "[project-name]",
  "version": 1,
  "sources": {
    "include": ["**/*.md", "**/*.txt"],
    "exclude": ["node_modules/**", "dist/**", ".git/**", "kb/**"],
    "formats": ["md", "txt", "py", "ts", "rs", "json", "yaml", "csv"]
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
  "output_dir": "kb/output"
}
```

See `example/` directory in the repo for a complete before/after demonstration.

### Obsidian Integration (Optional)

After init, check if Obsidian is available:
```bash
ls /Applications/Obsidian.app 2>/dev/null || which obsidian 2>/dev/null
```

If found, ask once: "Obsidian detected. Open KB as vault after compile? (Y/n)"
- If yes: set `config.obsidian: true` in manifest
- Use standard markdown links everywhere (NOT `[[wikilinks]]`)
- After compile, run: `open "obsidian://open?vault=$(basename $KB_ROOT)"` on macOS

---

## Phase 2: INGEST

Accept sources into the KB. Sources can be:

| Type | Detection | Action |
|------|-----------|--------|
| Local files | Path exists on disk | Copy to `kb/raw/`, create source summary |
| Directory | Path is a directory | Recursively index `.md`, `.txt`, `.py`, `.ts`, `.rs`, `.json` |
| URL | Starts with `http` | `WebFetch` → save as `.md` in `kb/raw/` |
| Clipboard/text | Raw text in prompt | Save as `.md` in `kb/raw/` with timestamp name |

For each ingested source:

1. **Hash the content** (for change detection):
   ```bash
   shasum -a 256 "$file" | cut -d' ' -f1
   ```

2. **Chunk the source** into logical sections (headings, function boundaries,
   paragraph breaks). Assign each chunk a stable ID: `{source-slug}#chunk-{N}`.
   Chunk IDs are sequential within a source and survive minor edits. Store chunks
   in the source page for traceability.

3. **Create source page** in `kb/wiki/sources/`:
   ```markdown
   # [Source Title]

   > **Source:** [path or URL]
   > **Ingested:** [timestamp]
   > **Hash:** [sha256]
   > **Status:** fresh | stale | unverified
   > **Chunks:** [N]

   ## Summary
   [2-3 paragraph summary of what this source contains]

   ## Chunks
   ### chunk-1: [section heading or first line]
   > [verbatim excerpt, 1-5 sentences]

   ### chunk-2: [section heading or first line]
   > [verbatim excerpt, 1-5 sentences]

   ## Key Claims
   - [claim 1] — chunk-1
   - [claim 2] — chunk-3

   ## Related Concepts
   - [concept-name](../concepts/concept-name.md)
   ```

3. **Update manifest** — add source entry with path, hash, timestamp

4. **Do NOT compile yet** — ingest is additive. User triggers compile separately.

### Bulk Ingest

For ingesting an entire project (e.g., `~/.opencode/skills/`):

1. Glob for relevant files (SKILL.md, README.md, CLAUDE.md, etc.)
2. Launch parallel subagents (3-4) to summarize batches
3. Each subagent creates source pages
4. Main thread updates manifest

---

## Phase 3: COMPILE

Transform raw source pages into an interlinked wiki. This is the core value.

### Step 1: Read all source pages
```
Glob: kb/wiki/sources/*.md
```

### Step 2: Extract concepts

For each source, identify distinct concepts (techniques, tools, patterns, decisions).
A concept is a **reusable idea** that appears in 2+ sources. Skip singletons.

Create concept pages in `kb/wiki/concepts/`:

```markdown
# [Concept Name]

> **First seen in:** [source](../sources/source.md)
> **Also referenced by:** [source2](../sources/source2.md), [source3](../sources/source3.md)
> **Confidence:** high | medium | low (based on source count and agreement)

## Definition
[1-2 sentences — what is this concept]

## Details
[expanded explanation, citing source#chunk-N for every factual claim]

## Connections
- Related to: [other-concept](other-concept.md) — [why]
- Contradicts: [concept](concept.md) — [how, per which sources]
- Prerequisite for: [concept](concept.md)

## Provenance
- [source.md](../sources/source.md) — chunk-1, chunk-3
- [source2.md](../sources/source2.md) — chunk-7
```

### Step 3: Build index

Regenerate `kb/wiki/index.md`:
- Count sources, concepts, total words
- List all sources with one-line summaries
- List all concepts grouped by category
- Cross-reference density (avg links per concept)
- Staleness report (any source older than 30 days)

### Step 4: Backlink pass

For every concept page, ensure all references are bidirectional.
If A links to B, B must link back to A.

### Hallucination Guard

During compilation:
- Every factual claim MUST cite `— [source.md](path)#chunk-N`
- If two sources contradict, flag it explicitly with both chunk citations
- If a claim has only one source and is surprising, mark confidence as `low`
- NEVER synthesize claims that aren't in any source chunk — that's hallucination
- Generated content MUST be clearly marked (see Phase 7: Edit Protection)

### Token Budget

Before compiling, estimate total tokens:
```
sources × avg_words_per_source × 1.3 (token ratio) = estimated_tokens
```
If estimated > `config.max_context_tokens`, compile in batches and warn user.

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
- [source.md](path)#chunk-N — [original claim from chunk]

### Confidence
[high/medium/low] — based on [N] sources, [agreement level]

### Gaps
[What the KB doesn't cover that would improve this answer]
```

### Filing Queries

After answering, append to `kb/wiki/index.md` under "Recent Queries":
```markdown
- **[question]** — [one-line answer] — [date]
```

If the query reveals a new concept or connection, offer to run `compile` to integrate it.

---

## Phase 5: LINT

Health check the KB. Run all checks, report as a scorecard.

### Checks

| Check | What it catches |
|-------|----------------|
| **Orphan pages** | Concept pages with no backlinks |
| **Broken links** | Links to pages that don't exist |
| **Stale sources** | Sources whose raw file hash has changed since ingestion |
| **Thin concepts** | Concept pages with < 100 words or only 1 source |
| **Missing provenance** | Claims without chunk citations |
| **Contradictions** | Concepts with conflicting claims from different sources |
| **Index drift** | Index doesn't match actual wiki contents |
| **Token bloat** | Wiki exceeds context budget |

### Scorecard

```markdown
# KB Health Report — [date]

| Check | Status | Count |
|-------|--------|-------|
| Orphan pages | WARN | 3 |
| Broken links | PASS | 0 |
| Stale sources | FAIL | 7 |
| ... | ... | ... |

**Overall: [HEALTHY / NEEDS ATTENTION / UNHEALTHY]**
**Score: [0-100]**

## Action Items
1. [Most critical fix]
2. [Second priority]
3. [Third priority]
```

### Auto-fix

For safe fixes (broken links, index drift), offer to fix automatically.
For unsafe fixes (stale sources, contradictions), list them and ask user.

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

---

## Phase 7: EDIT PROTECTION

Generated and human-authored content coexist. Compile must never clobber human work.

### Content zones

Every wiki page has two zones:

1. **Generated zone** (above `<!-- human notes below -->` marker):
   - Written and overwritten by compile
   - Includes: Summary, Chunks, Key Claims, Definition, Details, Provenance
   - Users should NOT edit here (edits will be lost on recompile)

2. **Human zone** (below `<!-- human notes below -->` marker):
   - Never touched by compile
   - Users add corrections, context, opinions, links
   - If this zone contains a `**REVIEWED**` tag, the concept is considered verified

### Compile behavior

- If a page has no `<!-- human notes below -->` marker, append one at the end
- Regenerate everything ABOVE the marker
- Leave everything BELOW the marker untouched
- If a source page's hash hasn't changed since last compile, skip regeneration

### Conflict handling

- If a human note contradicts a generated claim, flag it in lint (not auto-resolve)
- If a concept page is marked `**REVIEWED**`, compile warns before regenerating
  and preserves the reviewed status
- Deleted source pages: if a raw source is removed, compile marks its source page
  as `**Status:** orphaned` but does NOT delete it (human notes may exist)

### Example page with both zones

```markdown
# JWT Authentication

> **First seen in:** [auth-design](../sources/auth-design.md)
> **Confidence:** high

## Definition
[generated content...]

## Provenance
[generated content...]

<!-- human notes below -->

## My Notes
The 24h expiry is too long for admin endpoints. We should use 1h for /admin/*.
**REVIEWED** — verified against prod config 2026-04-01
```

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
      "command": "if [ -d kb/ ]; then echo 'KB: run /knowledge-base lint to check freshness'; fi",
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
