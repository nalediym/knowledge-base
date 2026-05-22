# knowledge-base

LLM-compiled knowledge base skill for [Claude Code](https://claude.ai/code) and [OpenCode](https://github.com/opencode-ai/opencode), plus a Bun/TypeScript CLI + MCP server.

Ingest raw sources, compile them into an interlinked markdown wiki, then query, lint, and output against it. Inspired by [Andrej Karpathy's LLM Knowledge Base pattern](https://x.com/karpathy/status/2039805659525644595).

## What it does

```
raw sources (docs, code, URLs, directories, sessions) -> LLM compiles -> markdown wiki -> query / lint / output
```

**Core flow:**

| Mode | Skill | CLI | What it does |
|------|-------|-----|-------------|
| Init | `init <path>` | `kb init [path]` | Stamp KB directory structure onto a project |
| Ingest | `ingest <path>` | `kb add <source>` / `kb ingest <source>` | Copy sources to `kb/raw/`, create summary pages, update manifest |
| Sessions | `ingest --sessions` | `kb ingest --sessions [--agent claude\|codex\|all]` | Mine agent transcripts with secret redaction |
| Compile | `compile` | (skill — full compile uses an LLM) | (Re)build wiki from raw files |
| Query | `query <question>` | (skill) | Research an answer with chunk citations |
| Lint | `lint --conflicts` | `kb lint --conflicts` | Cross-source contradiction detection (heuristic or LLM) |
| Output | `output <format>` | `kb output <llms-txt\|llms-full\|jsonld\|sitemap\|all>` | Render AI-consumable exports |
| Watch | `watch` | `kb watch` | Debounced poll of `kb/raw/` → ingest |
| MCP | `mcp` | `kb mcp` | Launch stdio MCP server (9 `kb_*` tools) |

**Default behavior** (no arguments): `kb` prints help; the skill runs `lint` if a KB exists, otherwise `init`.

## Install

### Claude Code skill

```bash
git clone https://github.com/nalediym/knowledge-base.git
ln -sf "$(pwd)/knowledge-base" ~/.claude/skills/knowledge-base
```

Then invoke with `/knowledge-base` in any project.

### OpenCode skill

```bash
git clone https://github.com/nalediym/knowledge-base.git
ln -sf "$(pwd)/knowledge-base" ~/.opencode/skills/knowledge-base
```

### CLI (Bun)

**One-line install** (installs Bun via `bun.sh/install` if missing, clones the repo, drops a `kb` launcher into `~/.local/bin`):

```bash
curl -fsSL https://raw.githubusercontent.com/nalediym/knowledge-base/main/scripts/install.sh | bash
```

**Homebrew** (macOS / Linux):

```bash
brew tap oven-sh/bun           # one-time: bun isn't in homebrew-core
brew install nalediym/kb/kb
```

The formula declares `bun` (from `oven-sh/bun`) as a dependency and ships the workspace under `libexec/`. `kb` is a thin shell wrapper around `bun packages/cli/src/bin.ts`.

**Manual** (if you already have Bun ≥ 1.3):

```bash
git clone https://github.com/nalediym/knowledge-base.git
cd knowledge-base
bun install
./packages/cli/src/bin.ts --version   # => kb v0.3.0
```

Add `bun packages/cli/src/bin.ts` to your PATH however you prefer.

### Required tool permissions (skill)

The skill uses: `Read`, `Write`, `Edit`, `Glob`, `Grep`, `Bash`, `Agent`, `WebFetch`, `WebSearch`. Approve these when prompted or add to your allowed tools config.

## Using KB as an MCP server

`kb mcp` launches a [Model Context Protocol](https://modelcontextprotocol.io/) stdio server exposing 9 tools: `kb_query`, `kb_search`, `kb_list_sources`, `kb_read_page`, `kb_lint`, `kb_ingest`, `kb_compile`, `kb_export`, `kb_dashboard`.

The server reads line-delimited JSON-RPC 2.0 from stdin, writes responses to stdout, and logs to stderr. File-path arguments are validated against `$KB_ROOT` (defaults to walking up from cwd for `kb/.kb-manifest.json`, capped at `$HOME`); `..` traversal and absolute paths outside the root are rejected.

**Claude Code / Cursor (`.mcp.json` in your project root):**

```json
{
  "mcpServers": {
    "kb": {
      "command": "kb",
      "args": ["mcp"],
      "env": {
        "KB_ROOT": "/absolute/path/to/your/project"
      }
    }
  }
}
```

**Claude Desktop (`claude_desktop_config.json`):**

macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
Windows: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "kb": {
      "command": "kb",
      "args": ["mcp"],
      "env": {
        "KB_ROOT": "/absolute/path/to/your/project"
      }
    }
  }
}
```

After editing, restart the client. The KB tools will appear in the tool picker.

**Quick smoke test:**

```bash
printf '%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | kb mcp
```

## Directory structure

Running `init` creates this structure and seeds `index.md`, `.kb-manifest.json`, and `kb.config.json`:

```
kb/
  raw/              # Original source documents (user-managed, never LLM-edited)
    media/          # Downloaded images referenced by sources
    generated/      # Re-ingested output artifacts (see Output Re-ingestion)
    sessions/       # Agent session transcripts (one .md per session, per project)
  wiki/             # LLM-compiled articles (LLM-managed)
    index.md        # Master index — auto-maintained
    concepts/       # One .md per concept (only concepts appearing in 2+ sources)
    candidates/     # New concept candidates pending approval
    sources/        # One .md per ingested source (chunks, key claims, related concepts)
  output/           # Generated artifacts (llms.txt, jsonld, sitemap, reports)
  .kb-manifest.json # Runtime state: ingested files, timestamps, hashes
  .kb-lock          # Transient lock file for concurrent write protection
kb.config.json      # Single source of truth for all configuration
```

## Design principles

- **Content-addressed chunk provenance** — every factual claim cites `source.md#c-XXXXXXXX` where the chunk ID is the first 8 chars of the sha256 of the chunk content. IDs are stable across insertions, reorderings, and minor edits.
- **Compile reads raw files, not cached summaries** — source pages are intermediate artifacts. Compile re-reads `kb/raw/` to prevent stale-summary propagation.
- **Filesystem is source of truth** — works with any editor. Obsidian is an optional viewer, not a dependency.
- **Standard markdown** — no `[[wikilinks]]`, no proprietary syntax. Ingested content is sanitized (HTML stripped, marker strings escaped, dangerous URIs removed).
- **Hallucination guard** — the LLM cannot synthesize claims absent from raw source chunks. Prompt-level policy; always verify surprising claims against raw sources.
- **Manifest locking** — file-based lock (`kb/.kb-lock`) with PID, timestamp, and 5-minute stale threshold prevents corruption from concurrent sessions.
- **Edit protection** — every wiki page has a generated zone (rewritten on compile) and a human zone (never touched), separated by `<!-- human notes below -->`.
- **Singleton facts preserved** — claims appearing in only 1 source are listed in the index under "Uncategorized Claims" with source citations. Nothing is silently dropped.
- **Path-based slugs** — files from different directories get unique slugs (`docs--README.md` vs `src--auth--README.md`). No collisions.
- **Secret redaction** — session-transcript ingest strips API keys (`sk-…`), GitHub tokens (`ghp_…`), named credentials, emails, and `$USER` before writing to disk.

## Features

### Session transcript ingest

`kb ingest --sessions` walks installed agent stores and writes one markdown page per session under `kb/raw/sessions/<project>/<date>-<slug>.md` with redacted content. Supported agents (auto-detected):

| Agent | Store | Notes |
|-------|-------|-------|
| Claude Code | `~/.claude/projects/<encoded-cwd>/<session>.jsonl` | Text + tool_use blocks; thinking blocks dropped |
| Codex CLI | `~/.codex/sessions/**/*.jsonl`, `~/.codex/projects/**/*.jsonl` | Normalized to user/assistant pairs |
| Cursor | `~/Library/Application Support/Cursor/User/workspaceStorage` | Detected only — parse pending |

Each transcript gets YAML frontmatter (`source_type: session`, `agent`, `project`, `session_id`, `started_at`, `model`, `source_path`) and a numbered turn-by-turn body.

### Contradiction detection

`kb lint --conflicts` walks every concept page, pulls Key Claims bullets from each referenced source page, pairs claims across different sources, and asks a `ClaimComparator` whether they disagree. Output lands at `kb/output/contradictions-YYYY-MM-DD.md`.

Two comparators ship in the box:

- **Heuristic** (default, no network): topic-overlap gate → antonym table → negation asymmetry → numeric disagreement.
- **LLM** (`llmComparator(provider)`): wraps any `LLMProvider` from `@kb/llm` (Anthropic, Ollama, OpenAI). Pluggable per call.

Lifecycle gating skips pages with `lifecycle: draft` on either the concept or source side.

### AI-consumable exports

`kb output <format>` renders the wiki for other agents:

- `llms-txt` — short index per [llmstxt.org](https://llmstxt.org), grouped by category, with summaries
- `llms-full` — flattened plain text of every page (capped at 5 MB, truncated cleanly)
- `jsonld` — schema.org JSON-LD `@graph` with `kb://` IDs and `isRelatedTo` cross-links
- `sitemap` — XML sitemap with `<lastmod>` from filesystem mtime
- `all` — write all four

### Watch

`kb watch` polls `kb/raw/` every 500 ms (configurable), diffs mtimes against a baseline, and triggers ingest after a debounce window of quiet. No native fs-events dependency — keeps the binary portable.

### Hybrid retrieval

The `@kb/store-sqlite` package combines SQLite FTS5 (porter + unicode61) and `sqlite-vec` embeddings via Reciprocal Rank Fusion (k=60, pool=4×limit). Embeddings live as raw Float32 BLOBs queryable across arbitrary dimensions. Default embedding provider is Ollama (`nomic-embed-text`); Anthropic and OpenAI providers ship too.

### Contextual retrieval

The Anthropic Sept 2024 [contextual retrieval](https://www.anthropic.com/news/contextual-retrieval) pattern is in `@kb/llm/contextualize`: per-chunk LLM call with the whole document threaded through `cache_control`, returns a 50–100 token situating prefix prepended before indexing.

### Lifecycle + sweep

Pages move through `draft → reviewed → verified → stale → archived` via frontmatter. `@kb/core/lifecycle-sweep` advances pages automatically based on age and confidence thresholds.

### Output re-ingestion

After generating output (slides, diagrams, summaries), you can file it back into the wiki via the skill: copies to `kb/raw/generated/` with a `generated--` prefix. Generated sources are excluded from confidence scoring (prevents hallucination amplification). Lint warns if generated ratio exceeds 30%.

### Obsidian (optional)

At `init` time, the skill checks for Obsidian on macOS. If found, it asks once whether to enable Obsidian integration. If you say yes, `obsidian: true` is set in `kb.config.json` and the skill opens results via the `obsidian://` URI scheme after compile/output. No CLI dependency, no paid license required.

## Architecture

Bun monorepo at the repo root, packages connected via Bun workspaces:

| Package | Purpose |
|---------|---------|
| `@kb/core` | Types, chunking, manifest+locking, lifecycle state machine + sweep, confidence scoring, frontmatter, Adapter/Inferrer contracts, fs watcher |
| `@kb/store-sqlite` | `bun:sqlite` + `sqlite-vec` + FTS5 hybrid retrieval with RRF |
| `@kb/adapters` | Markdown source adapter; session adapters (claude-code, codex, cursor) + redactor + renderer |
| `@kb/llm` | LLM/Embedding interfaces, mocks, Anthropic/Ollama/OpenAI providers, `contextualizeChunk` |
| `@kb/inferrers` | `compile` (contextual retrieval pipeline), `candidates` (approval workflow), `conflicts` (contradiction detection), `exports` (AI-consumable formats) |
| `@kb/mcp` | Stdio JSON-RPC 2.0 MCP server, `KB_ROOT` path guard, 9 `kb_*` tools |
| `@kb/cli` | `kb` command — wires all the above into a single binary |

## Composability

Pairs well with other Claude Code skills:

| Skill | How |
|-------|-----|
| `/research` | Feed evidence receipts into KB as sources |
| `/build-mode` | Query KB for architecture decisions before building |
| `/cleanup-mode` | Run `lint` as part of session cleanup |
| `/gstack-retro` | Retro findings become KB sources |

## Configuration

Drop a `kb.config.json` in your project root to customize behavior. `init` creates one from defaults if missing.

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
| `clipper.enabled` | `false` | Enable Obsidian Web Clipper integration |
| `clipper.watch_dir` | `null` | Path to Web Clipper output folder |

## Example

The `example/` directory shows a complete before/after:
- `example/raw/` — two source docs (auth design + API guidelines)
- `example/kb/wiki/sources/` — compiled source pages with content-addressed chunk IDs and `<!-- human notes below -->` markers
- `example/kb/wiki/concepts/` — extracted concepts with full `#c-XXXXXXXX` provenance on every claim
- `example/kb/wiki/index.md` — auto-generated index

## Known limitations

- **Concurrency:** Single-threaded per Claude Code session. Manifest locking (`kb/.kb-lock`) prevents corruption with a 5-minute stale threshold.
- **Scale:** Hybrid retrieval works to ~10K chunks comfortably. Backlinks are recomputed in-memory; stream-based migration tracked in [#1](https://github.com/nalediym/knowledge-base/issues/1).
- **Trust model:** Hallucination guard and secret redaction are prompt/regex-level, not runtime guarantees. Verify surprising claims against raw sources.
- **Cursor sessions:** Detected but not parsed (stored in SQLite, not JSONL).
- **URL ingest:** The CLI's `kb_ingest` MCP tool returns a "use the skill" message for `http(s)://` paths.

## Roadmap

- **v0.4 (in progress):** Graph viewer (live SSE), schedule (launchd/systemd), Obsidian Web Clipper auto-ingest port.
- **v0.5:** Cursor SQLite session parser, Gemini CLI + GitHub Copilot adapters.
- **v0.6:** Review governance (pending claims, team workflows).

## Prior art

- [Khoj AI](https://github.com/khoj-ai/khoj) — self-hosted second brain (retrieval, not compilation)
- [library-mcp](https://github.com/lethain/library-mcp) — MCP server for markdown knowledge bases
- [Microsoft MarkItDown](https://github.com/microsoft/markitdown) — document-to-markdown converter (good ingest layer)
- [Obsidian Web Clipper](https://obsidian.md/clipper) — browser extension for clipping web pages as markdown

The novel value here is the **compilation step** — transforming raw docs into an interlinked, deduplicated wiki with provenance. Existing tools do retrieval or conversion, not synthesis.

## License

MIT
