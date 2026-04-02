# knowledge-base

LLM-compiled knowledge base skill for [Claude Code](https://claude.ai/code) and [OpenCode](https://github.com/opencode-ai/opencode).

Ingest raw sources, compile them into an interlinked markdown wiki, then query, lint, and output against it. Inspired by [Andrej Karpathy's LLM Knowledge Base pattern](https://x.com/karpathy/status/2039805659525644595).

## What it does

```
raw sources (docs, code, URLs, directories, text) → LLM compiles from raw files → markdown wiki → query / lint / output
```

**6 modes:**

| Mode | What it does |
|------|-------------|
| `init <path>` | Stamp KB directory structure onto a project |
| `ingest <path>` | Copy sources to `kb/raw/`, create summary pages in `kb/wiki/sources/`, update manifest. Does NOT compile. |
| `compile` | (Re)build wiki from **raw files** (not cached summaries): re-chunk, extract concepts with global dedup, build index. Batches with merge pass if token budget exceeded. |
| `query <question>` | Research an answer against the wiki with chunk citations. Sanitizes and files query to index (max 20, rotated). |
| `lint` | Health scorecard: 12 checks including staleness, orphans, broken links, missing provenance, marker integrity, reviewed drift, slug collisions. Auto-fixes safe issues, asks before unsafe ones. |
| `output <format>` | Render as Marp slides, Mermaid diagrams, concept graph, or condensed summary |

**Default behavior** (no arguments): runs `lint` if a KB exists (detected by `kb/.kb-manifest.json`), otherwise runs `init`.

### Supported source types

| Type | What happens |
|------|-------------|
| Local file | Copied to `kb/raw/` with path-based slug, source summary created |
| Directory | Recursively indexes files matching `config.sources.include` globs |
| URL | Fetched via WebFetch, saved as `.md` in `kb/raw/` |
| Raw text / clipboard | Saved as timestamped `.md` in `kb/raw/` |

Bulk ingest launches parallel subagents for source page creation, with serialized manifest writes to prevent conflicts.

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

### Required tool permissions

The skill uses: `Read`, `Write`, `Edit`, `Glob`, `Grep`, `Bash`, `Agent`, `WebFetch`, `WebSearch`. Approve these when prompted or add to your allowed tools config.

## Directory structure

Running `init` creates this structure and seeds `index.md`, `.kb-manifest.json`, and `kb.config.json`:

```
kb/
  raw/              # Original source documents (user-managed, never LLM-edited)
  wiki/             # LLM-compiled articles (LLM-managed)
    index.md        # Master index: Sources, Concepts, Uncategorized Claims, Recent Queries
    concepts/       # One .md per concept (only concepts appearing in 2+ sources)
    sources/        # One .md per ingested source (chunks, key claims, related concepts)
  output/           # Generated artifacts (slides, diagrams, reports, concept graphs)
  .kb-manifest.json # Runtime state: ingested files, timestamps, hashes
kb.config.json      # Single source of truth for all configuration
```

## Design principles

- **Content-addressed chunk provenance** — every factual claim cites `source.md#c-XXXXXXXX` where the chunk ID is the first 8 chars of the sha256 of the chunk content. IDs are stable across insertions, reorderings, and minor edits. If chunk text changes, the ID changes (signaling stale citations).
- **Compile reads raw files, not cached summaries** — source pages are intermediate artifacts. Compile re-reads `kb/raw/` to prevent stale-summary propagation and poisoned-wiki amplification.
- **Filesystem is source of truth** — works with any editor. Obsidian is an optional viewer, not a dependency.
- **Standard markdown** — no `[[wikilinks]]`, no proprietary syntax. Ingested content is sanitized (HTML stripped, marker strings escaped, dangerous URIs removed).
- **Hallucination guard** — the LLM cannot synthesize claims absent from raw source chunks. This is a prompt-level policy, not a runtime guarantee. Always verify surprising claims against raw sources.
- **Staleness detection** — file hashes in the manifest detect when raw sources change. Compile checks hashes before building. Lint catches hash drift, chunk drift, broken links, and index-to-wiki mismatches.
- **Token-aware** — compile estimates token usage before starting. Batches with a global merge pass if wiki exceeds `max_context_tokens` (default 200K).
- **Edit protection** — every wiki page has a generated zone (rewritten on compile) and a human zone (never touched), separated by `<!-- human notes below -->`. The marker is sanitized during ingest to prevent spoofing. `**REVIEWED** [sha256:XXXX]` tags include a content hash that lint checks for drift.
- **Singleton facts preserved** — claims appearing in only 1 source don't get concept pages, but they're listed in the index under "Uncategorized Claims" with source citations. Nothing is silently dropped.
- **Path-based slugs** — files from different directories with the same name get unique slugs (`docs--README.md` vs `src--auth--README.md`). No collisions.

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
      "command": "if echo '$TOOL_INPUT' | grep -q 'kb/raw/'; then echo 'KB: new raw source detected — run /knowledge-base ingest'; fi"
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

Key settings: `compile.concept_threshold` (min sources per concept, default 2), `provenance.chunk_strategy` (`heading` or `paragraph`), `compile.incremental` (skip unchanged sources), `sources.include` (glob patterns for file types to index).

## Example

The `example/` directory shows a complete before/after:
- `example/raw/` — two source docs (auth design + API guidelines)
- `example/kb/wiki/sources/` — compiled source pages with content-addressed chunk IDs, verbatim excerpts, and `<!-- human notes below -->` markers
- `example/kb/wiki/concepts/` — extracted concepts with full `#c-XXXXXXXX` provenance on every claim, `**REVIEWED**` tag with content hash
- `example/kb/wiki/index.md` — auto-generated index with Mermaid concept graph and "Uncategorized Claims" section for singleton facts (CSRF, error format, versioning)

## Known limitations

- **Concurrency:** single-threaded per Claude Code session. Don't run compile while another session ingests.
- **Scale:** index-based retrieval works to ~500 sources. Beyond that, the Elixir CLI (see `cli/`) will add proper search.
- **Trust model:** hallucination guard is prompt-level, not a runtime guarantee.

## Roadmap

- **Phase 2:** Extract to Elixir CLI (`kb init`, `kb add`, `kb build`, `kb ask`, `kb check`). See `cli/` directory.
- **Phase 3:** Adapters for PDFs, DOCX, notebooks, issue trackers.
- **Phase 4:** Review governance (pending claims, conflict resolution, team workflows).

## Prior art

- [Khoj AI](https://github.com/khoj-ai/khoj) — self-hosted second brain (retrieval, not compilation)
- [library-mcp](https://github.com/lethain/library-mcp) — MCP server for markdown knowledge bases
- [Microsoft MarkItDown](https://github.com/microsoft/markitdown) — document-to-markdown converter (good ingest layer)

The novel value here is the **compilation step** — transforming raw docs into an interlinked, deduplicated wiki with provenance. Existing tools do retrieval or conversion, not synthesis.

## License

MIT
