# knowledge-base

LLM-compiled knowledge base skill for [Claude Code](https://claude.ai/code) and [OpenCode](https://github.com/opencode-ai/opencode).

Ingest raw sources, compile them into an interlinked markdown wiki, then query, lint, and output against it. Inspired by [Andrej Karpathy's LLM Knowledge Base pattern](https://x.com/karpathy/status/2039805659525644595).

## What it does

```
raw sources (docs, code, URLs, directories, clips) -> LLM compiles from raw files -> markdown wiki -> query / lint / output
```

**7 modes:**

| Mode | Skill | CLI | What it does |
|------|-------|-----|-------------|
| Init | `init <path>` | `kb init [path]` | Stamp KB directory structure onto a project |
| Ingest | `ingest <path>` | `kb add <source>` | Copy sources to `kb/raw/`, create summary pages, update manifest |
| Compile | `compile` | `kb build` | (Re)build wiki from raw files: re-chunk, extract concepts, build index |
| Query | `query <question>` | `kb ask <question>` | Research an answer against the wiki with chunk citations |
| Lint | `lint` | `kb check` | Health scorecard: 16 checks including staleness, orphans, broken links, missing provenance, generated ratio |
| Output | `output <format>` | `kb output <format>` | Render as Marp slides, Mermaid diagrams, concept graph, or summary |
| Clip | `clip` | `kb clip` | Ingest new files from Obsidian Web Clipper watch directory |

Additional CLI commands: `kb file <path>` (re-ingest output back into wiki), `kb version`.

**Default behavior** (no arguments): runs `lint` if a KB exists (detected by `kb/.kb-manifest.json`), otherwise runs `init`.

### Supported source types

| Type | What happens |
|------|-------------|
| Local file | Copied to `kb/raw/` with path-based slug, source summary created |
| Directory | Recursively indexes files matching `config.sources.include` globs |
| URL | Fetched via WebFetch, saved as `.md` in `kb/raw/` (skill only) |
| Raw text / clipboard | Saved as timestamped `.md` in `kb/raw/` |
| Web Clipper | Scanned from `clipper.watch_dir`, ingested via standard pipeline |

Bulk ingest launches parallel subagents for source page creation, with a single atomic manifest write to prevent conflicts.

## Install

### Claude Code

```bash
# Clone and symlink (recommended)
git clone https://github.com/nalediym/knowledge-base.git
ln -sf "$(pwd)/knowledge-base" ~/.claude/skills/knowledge-base
```

Or copy directly:

```bash
git clone https://github.com/nalediym/knowledge-base.git
mkdir -p ~/.claude/skills/knowledge-base
cp knowledge-base/SKILL.md ~/.claude/skills/knowledge-base/
```

### OpenCode

```bash
git clone https://github.com/nalediym/knowledge-base.git
ln -sf "$(pwd)/knowledge-base" ~/.opencode/skills/knowledge-base
```

Then invoke with `/knowledge-base` in any project.

### Elixir CLI

The `cli/` directory contains a standalone Elixir CLI for structural operations (chunking, hashing, linting, output rendering). LLM-dependent features (concept extraction, query synthesis, explore-next) require the Claude Code skill.

```bash
cd cli
mix deps.get
mix escript.build
# Binary: ./kb
```

### Required tool permissions

The skill uses: `Read`, `Write`, `Edit`, `Glob`, `Grep`, `Bash`, `Agent`, `WebFetch`, `WebSearch`. Approve these when prompted or add to your allowed tools config.

## Directory structure

Running `init` creates this structure and seeds `index.md`, `.kb-manifest.json`, and `kb.config.json`:

```
kb/
  raw/              # Original source documents (user-managed, never LLM-edited)
    media/          # Downloaded images referenced by sources
    generated/      # Re-ingested output artifacts (see Output Re-ingestion)
  wiki/             # LLM-compiled articles (LLM-managed)
    index.md        # Master index: Sources, Concepts, Uncategorized Claims, Recent Queries
    concepts/       # One .md per concept (only concepts appearing in 2+ sources)
    sources/        # One .md per ingested source (chunks, key claims, related concepts)
  output/           # Generated artifacts (slides, diagrams, reports, concept graphs)
  .kb-manifest.json # Runtime state: ingested files, timestamps, hashes
  .kb-lock          # Transient lock file for concurrent write protection
kb.config.json      # Single source of truth for all configuration
```

## Design principles

- **Content-addressed chunk provenance** -- every factual claim cites `source.md#c-XXXXXXXX` where the chunk ID is the first 8 chars of the sha256 of the chunk content. IDs are stable across insertions, reorderings, and minor edits.
- **Compile reads raw files, not cached summaries** -- source pages are intermediate artifacts. Compile re-reads `kb/raw/` to prevent stale-summary propagation.
- **Filesystem is source of truth** -- works with any editor. Obsidian is an optional viewer, not a dependency.
- **Standard markdown** -- no `[[wikilinks]]`, no proprietary syntax. Ingested content is sanitized (HTML stripped, marker strings escaped, dangerous URIs removed).
- **Hallucination guard** -- the LLM cannot synthesize claims absent from raw source chunks. Prompt-level policy; always verify surprising claims against raw sources.
- **Manifest locking** -- file-based lock (`kb/.kb-lock`) with PID, timestamp, and 5-minute stale threshold prevents corruption from concurrent sessions.
- **Token-aware** -- compile estimates token usage before starting. Batches with a global merge pass if wiki exceeds `max_context_tokens` (default 200K).
- **Edit protection** -- every wiki page has a generated zone (rewritten on compile) and a human zone (never touched), separated by `<!-- human notes below -->`. `**REVIEWED** [sha256:XXXX]` tags include a content hash that lint checks for drift.
- **Singleton facts preserved** -- claims appearing in only 1 source are listed in the index under "Uncategorized Claims" with source citations. Nothing is silently dropped.
- **Path-based slugs** -- files from different directories get unique slugs (`docs--README.md` vs `src--auth--README.md`). No collisions.

## Features

### Image support

When `images.download` is true, ingesting sources with image references will:
- Download images to `kb/raw/media/` (local files only in CLI; URLs via skill)
- Rewrite markdown image links to point to local paths
- Skip images exceeding `images.max_size_mb` (default 10MB)
- During compile, multimodal LLMs extract descriptions from images as alt-text

Supported formats: `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg`

### Explore-Next suggestions

After every query answer, the skill generates 3-5 follow-up questions based on:
- Gaps in the KB's coverage of the topic
- Thin concepts with low confidence or few sources
- Unlinked connections between related concepts
- Contradictions worth investigating
- Stale sources that may have newer data

Every query "adds up" -- each answer opens doors to deeper exploration.

### Missing data imputation

When `impute.enabled` is true, lint identifies low-confidence concepts and searches the web for corroborating data. Findings are presented as **proposals** (never auto-ingested). Imputed sources are flagged `needs-review` and excluded from confidence scoring.

### Output re-ingestion

After generating output (slides, diagrams, summaries), you can file it back into the wiki:
- `kb file <path>` copies the output to `kb/raw/generated/` with a `generated--` prefix
- Generated sources are excluded from confidence scoring (prevents hallucination amplification)
- Lint warns if generated sources exceed 30% of total sources

Your explorations and queries "add up" in the knowledge base.

### Obsidian Web Clipper integration

Clip web pages directly into your KB while browsing:
1. Install the [Obsidian Web Clipper](https://obsidian.md/clipper) browser extension
2. Configure it to save to a folder (e.g., `~/obsidian-vault/clipped/`)
3. Set `clipper.watch_dir` and `clipper.enabled: true` in `kb.config.json`
4. Run `kb clip` to ingest new clips

Web Clipper preserves rich metadata (title, author, date, source URL) as YAML frontmatter, and downloads images locally. The `auto_ingest` option scans the clipper directory automatically before each compile.

## Obsidian (optional)

At `init` time, the skill checks for Obsidian on macOS (`/Applications/Obsidian.app`). If found, it asks once whether to enable Obsidian integration. If you say yes:
- `obsidian` is set to `true` in `kb.config.json` (the single config source)
- After `compile` and `output`, the skill opens the result via `obsidian://` URI scheme
- No CLI dependency, no paid license required
- All links remain standard markdown (not `[[wikilinks]]`)

## Maintenance hooks (optional)

Add to `~/.claude/settings.json` for automatic KB maintenance:

**Post-commit reminder:**
```json
{
  "hooks": {
    "post-commit": [{
      "type": "command",
      "command": "if [ -d kb/ ] && [ -f kb/.kb-manifest.json ]; then echo 'KB: run /knowledge-base lint to check freshness'; fi"
    }]
  }
}
```

**Auto-detect new raw sources:**
```json
{
  "hooks": {
    "post-tool-use:Write": [{
      "type": "command",
      "command": "if echo '$TOOL_INPUT' | grep -q 'kb/raw/'; then echo 'KB: new raw source detected -- run /knowledge-base ingest'; fi"
    }]
  }
}
```

## Composability

Pairs well with other Claude Code skills:

| Skill | How |
|-------|-----|
| `/research` | Feed evidence receipts into KB as sources |
| `/build-mode` | Query KB for architecture decisions before building |
| `/cleanup-mode` | Run `lint` as part of session cleanup |
| `/gstack-learn` | Sync learnings into KB as sources |
| `/gstack-retro` | Retro findings become KB sources |

## Configuration

Drop a `kb.config.json` in your project root to customize behavior. `init` creates one from defaults if missing. See [kb.config.json](kb.config.json) for the default config.

Key settings:

| Key | Default | What it does |
|-----|---------|-------------|
| `compile.concept_threshold` | `2` | Min sources per concept |
| `compile.incremental` | `true` | Skip unchanged sources |
| `provenance.chunk_strategy` | `"heading"` | How to split sources (`heading` or `paragraph`) |
| `sources.include` | `["**/*.md", ...]` | Glob patterns for file types to index |
| `images.download` | `true` | Download and localize images during ingest |
| `images.max_size_mb` | `10` | Skip images larger than this |
| `impute.enabled` | `false` | Enable web search for missing data during lint |
| `impute.max_searches` | `5` | Max web searches per lint run |
| `clipper.enabled` | `false` | Enable Obsidian Web Clipper integration |
| `clipper.watch_dir` | `null` | Path to Web Clipper output folder |
| `clipper.auto_ingest` | `false` | Auto-scan clipper dir before compile |

## Example

The `example/` directory shows a complete before/after:
- `example/raw/` -- two source docs (auth design + API guidelines)
- `example/kb/wiki/sources/` -- compiled source pages with content-addressed chunk IDs, verbatim excerpts, and `<!-- human notes below -->` markers
- `example/kb/wiki/concepts/` -- extracted concepts with full `#c-XXXXXXXX` provenance on every claim, `**REVIEWED**` tag with content hash
- `example/kb/wiki/index.md` -- auto-generated index with Mermaid concept graph and "Uncategorized Claims" section for singleton facts (CSRF, error format, versioning)

## Known limitations

- **Concurrency:** Single-threaded per Claude Code session. Manifest locking (`kb/.kb-lock`) prevents corruption from concurrent sessions with a 5-minute stale threshold.
- **Scale:** Index-based retrieval works to ~500 sources. Beyond that, proper search is needed.
- **Trust model:** Hallucination guard is prompt-level, not a runtime guarantee.
- **Images:** Description extraction depends on multimodal LLM capability. SVGs are stored but not described. Large images (> `max_size_mb`) are skipped. URL image download requires the Claude Code skill (CLI handles local images only).
- **Imputation:** Web search results are proposals only, never auto-ingested. Disabled by default. Quality depends on search result relevance.
- **Re-ingestion loops:** Generated sources are excluded from confidence scoring. Lint warns if generated ratio exceeds 30%.
- **Web Clipper:** Requires manual `kb clip` unless `auto_ingest` is enabled. Watch directory must be set in config.

## Roadmap

- **Phase 2 (in progress):** Elixir CLI (`cli/`) provides structural operations. LLM-dependent features (concept extraction, query synthesis) still require the Claude Code skill.
- **Phase 3:** Adapters for PDFs, DOCX, notebooks, issue trackers.
- **Phase 4:** Review governance (pending claims, conflict resolution, team workflows).

## Prior art

- [Khoj AI](https://github.com/khoj-ai/khoj) -- self-hosted second brain (retrieval, not compilation)
- [library-mcp](https://github.com/lethain/library-mcp) -- MCP server for markdown knowledge bases
- [Microsoft MarkItDown](https://github.com/microsoft/markitdown) -- document-to-markdown converter (good ingest layer)
- [Obsidian Web Clipper](https://obsidian.md/clipper) -- browser extension for clipping web pages as markdown

The novel value here is the **compilation step** -- transforming raw docs into an interlinked, deduplicated wiki with provenance. Existing tools do retrieval or conversion, not synthesis.

## License

MIT
