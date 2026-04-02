# knowledge-base

LLM-compiled knowledge base skill for [Claude Code](https://claude.ai/code) and [OpenCode](https://github.com/opencode-ai/opencode).

Ingest raw sources, compile them into an interlinked markdown wiki, then query, lint, and output against it. Inspired by [Andrej Karpathy's LLM Knowledge Base pattern](https://x.com/karpathy/status/2039805659525644595).

## What it does

```
raw sources (docs, code, URLs, directories, text) → LLM compiles → markdown wiki → query / lint / output
```

**6 modes:**

| Mode | What it does |
|------|-------------|
| `init <path>` | Stamp KB directory structure onto a project |
| `ingest <path>` | Copy sources to `kb/raw/`, create summary pages in `kb/wiki/sources/`, update manifest. Does NOT compile. |
| `compile` | (Re)build the full wiki: index, concepts, backlinks, cross-links. Batches if token budget exceeded. |
| `query <question>` | Research an answer against the wiki with source citations. Files query to index for future reference. |
| `lint` | Health scorecard: staleness, orphans, broken links, thin concepts, missing provenance, contradictions, token bloat. Auto-fixes safe issues, asks before unsafe ones. |
| `output <format>` | Render as Marp slides, Mermaid diagrams, concept graph, or condensed summary |

**Default behavior** (no arguments): runs `lint` if a KB exists in the project, otherwise runs `init`. Detects KB root by looking for `kb/`, `wiki/`, or `knowledge/` directories.

### Supported source types

| Type | What happens |
|------|-------------|
| Local file | Copied to `kb/raw/`, source summary created |
| Directory | Recursively indexes `.md`, `.txt`, `.py`, `.ts`, `.rs`, `.json` files |
| URL | Fetched via WebFetch, saved as `.md` in `kb/raw/` |
| Raw text / clipboard | Saved as timestamped `.md` in `kb/raw/` |

Bulk ingest (e.g., an entire project) launches 3-4 parallel subagents for speed.

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

Running `init` creates this structure and seeds `index.md` and `.kb-manifest.json`:

```
kb/
  raw/              # Original source documents (user-managed, never LLM-edited)
  wiki/             # LLM-compiled articles (LLM-managed)
    index.md        # Master index with Sources, Concepts, Recent Queries sections
    concepts/       # One .md per concept (only concepts appearing in 2+ sources)
    sources/        # One .md per ingested source (summary, key claims, related concepts)
  output/           # Generated artifacts (slides, diagrams, reports, concept graphs)
  .kb-manifest.json # Tracks ingested files, timestamps, hashes, obsidian config, token budget
```

## Design principles

- **Chunk-based provenance** — every factual claim cites `source.md#chunk-N`. Sources are split into logical chunks (by heading, function boundary, or paragraph). Chunk IDs are stable across minor edits, unlike line numbers. If two sources contradict, both chunks are cited. Single-source surprising claims are marked low confidence.
- **Filesystem is source of truth** — works with any editor. Obsidian is an optional viewer, not a dependency.
- **Standard markdown** — no `[[wikilinks]]`, no proprietary syntax.
- **Hallucination guard** — the LLM cannot synthesize claims absent from sources. Every concept page traces back to raw source files with line numbers.
- **Staleness detection** — file hashes in the manifest detect when raw sources change. Compile also flags sources older than 30 days. Lint catches hash drift, broken links, and index-to-wiki mismatches.
- **Token-aware** — compile estimates token usage before starting. If the wiki exceeds `max_context_tokens` (default 200K), it compiles in batches and warns.
- **Edit protection** — every wiki page has a generated zone (rewritten on compile) and a human zone (never touched). Add notes, corrections, and `**REVIEWED**` tags below the `<!-- human notes below -->` marker. Compile will never clobber your work.

## Obsidian (optional)

At `init` time, the skill checks for Obsidian on macOS (`/Applications/Obsidian.app`). If found, it asks once whether to enable Obsidian integration. If you say yes:
- `config.obsidian` is set to `true` in `.kb-manifest.json`
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
      "command": "if [ -d kb/ ]; then echo 'KB: run /knowledge-base lint to check freshness'; fi"
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

Drop a `kb.config.json` in your project root to customize behavior. `init` creates one from defaults if missing. See [kb.config.json](kb.config.json) for the full schema.

Key settings: `compile.concept_threshold` (min sources per concept, default 2), `provenance.method` (`chunk` or `line`), `compile.incremental` (skip unchanged sources).

## Example

The `example/` directory shows a complete before/after:
- `example/raw/` — two source docs (auth design + API guidelines)
- `example/kb/wiki/sources/` — compiled source pages with chunks
- `example/kb/wiki/concepts/` — extracted concepts (jwt-authentication, rate-limiting) with chunk provenance
- `example/kb/wiki/index.md` — auto-generated index with Mermaid concept graph

## Prior art

- [Khoj AI](https://github.com/khoj-ai/khoj) — self-hosted second brain (retrieval, not compilation)
- [library-mcp](https://github.com/lethain/library-mcp) — MCP server for markdown knowledge bases
- [Microsoft MarkItDown](https://github.com/microsoft/markitdown) — document-to-markdown converter (good ingest layer)

The novel value here is the **compilation step** — transforming raw docs into an interlinked, deduplicated wiki with provenance. Existing tools do retrieval or conversion, not synthesis.

## License

MIT
