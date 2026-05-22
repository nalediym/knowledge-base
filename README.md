# knowledge-base

Agents forget. Every new session is a cold start — re-reading the same files, re-deriving the same conclusions, re-discovering the same constraints. The session transcript that knew everything an hour ago is gone, and there's no audit trail of what was actually learned.

knowledge-base is one opinionated answer. The project ships two surfaces: a Claude Code / OpenCode **skill** that runs the full LLM-driven pipeline (chunk → contextual-retrieval → wiki compile with chunk-level citations), and a Bun/TypeScript **package** (CLI + stdio MCP server) that exposes the underlying primitives. The skill is the smart, full-feature surface today; the package is a growing primitives library that the skill leans on.

Compatible with [Claude Code](https://claude.ai/code), [OpenCode](https://github.com/opencode-ai/opencode), Claude Desktop, Cursor, and any MCP-capable client. Inspired by [Andrej Karpathy's LLM Knowledge Base pattern](https://x.com/karpathy/status/2039805659525644595).

## What it does today

Primitives that exist in the `packages/` tree and are exercised by the skill:

- **Content-addressed chunk hashing** — `source.md#c-XXXXXXXX` where the chunk ID is the first 8 chars of the sha256 of the chunk content (`@kb/core`). Stable across insertions and reorderings. Edits to the chunk content produce a new ID — that's a signal, not a bug, but the stability semantics are being revisited in [#12](https://github.com/nalediym/knowledge-base/issues/12).
- **Hybrid retrieval with reciprocal rank fusion** — `bun:sqlite` FTS5 + `sqlite-vec` embeddings merged with RRF (k=60) in `@kb/store-sqlite`. Used by the skill's `query` mode. The package CLI / MCP `kb_query` / `kb_search` currently fall back to substring search (gap tracked in [#13](https://github.com/nalediym/knowledge-base/issues/13)).
- **Contextual retrieval** — per-chunk LLM call that prepends a situating prefix before indexing, following [Anthropic's contextual retrieval pattern](https://www.anthropic.com/news/contextual-retrieval). `@kb/llm/contextualize`.
- **4-factor Ebbinghaus-decay confidence scoring function** — `(sources, quality, recency, cross-refs)` with τ-per-content-type in `@kb/core/confidence`. The function is pure; auto-application during compile is not yet wired ([#13](https://github.com/nalediym/knowledge-base/issues/13)).
- **5-state lifecycle machine + sweep function** — `draft → reviewed → verified → stale → archived` in `@kb/core/lifecycle`. Sweep demotes pages older than `stale_after_days` and demotes `verified` pages whose body hash drifts. Sweep is called by the skill, not auto-called by package compile yet ([#13](https://github.com/nalediym/knowledge-base/issues/13)).
- **Session-transcript ingest with secret redaction** — Claude Code + Codex stores walked, `sk-…` / `ghp_…` / named credentials / emails stripped before write. Cursor adapter stubbed. `@kb/adapters/sessions`.
- **Standard markdown + content-addressed source pages** — no `[[wikilinks]]`. The compile pipeline reads `kb/raw/` directly so source-page summaries can't go stale silently.

The skill layers on top: concept extraction with chunk citations, cross-source contradiction detection, edit-protected human/generated zones (marker convention enforced by the skill's compile flow), and AI-consumable exports (`llms-txt`, `llms-full`, `jsonld`, `sitemap`).

## Building toward

- **Reranker primitive** — cross-encoder or LLM rerank pass on top of `@kb/store-sqlite`'s RRF-fused results. Anthropic's contextual-retrieval write-up reports contextual embeddings + BM25 cut retrieval failure 49%, and adding a reranker cuts failure 67%. Pluggable like the conflict comparator.
- **Attention-aware ordering** — reorder retrieved chunks to put critical info at start/end, mitigating the lost-in-the-middle effect.
- **Working-memory / scratchpad layer** — session-scoped store an agent writes to mid-session ("tried X, failed because Y"), compiled into the long-term KB at session close.
- **MCP / CLI parity with the skill pipeline** — close the gap so `kb_query` does retrieval-with-citations end-to-end and the CLI exposes the same surface ([#13](https://github.com/nalediym/knowledge-base/issues/13)).

## At a glance

```
raw sources (docs, code, sessions) → compile → wiki with provenance → agents read via the /knowledge-base skill (today), with MCP / CLI catching up (#13)
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

## Agent surface

Three ways an agent reaches KB today. The skill is the full pipeline; the package surfaces (CLI + MCP) cover a subset and are catching up — see [#13](https://github.com/nalediym/knowledge-base/issues/13).

### 1. `/knowledge-base` skill (full pipeline)

Invoked from inside Claude Code / OpenCode. Drives the end-to-end LLM workflow: ingest → chunk → contextual-retrieval → compile → query with chunk citations → lint → output. This is where the wiki-compile and concept-extraction loop runs.

### 2. MCP server — `kb mcp`

Stdio JSON-RPC 2.0. Nine tool names usable from any MCP client (Claude Code, Claude Desktop, Cursor, Cline, Codex, Continue): `kb_query`, `kb_search`, `kb_list_sources`, `kb_read_page`, `kb_lint`, `kb_ingest`, `kb_compile`, `kb_export`, `kb_dashboard`. Check `tools/list` for the authoritative descriptions per build — today some are simpler than the skill's equivalents (substring search rather than full hybrid retrieval, etc.; tracked in [#13](https://github.com/nalediym/knowledge-base/issues/13)).

Configuration in [Using KB as an MCP server](#using-kb-as-an-mcp-server) below. KB discovery walks up from the server's cwd looking for `kb/.kb-manifest.json` — no `${workspaceFolder}` variables (client support is inconsistent).

### 3. CLI — `kb <command>`

`kb init`, `kb ingest`, `kb ingest --sessions`, `kb lint`, `kb output <format>`, `kb watch`, `kb mcp`. Run `kb --help` for the live list. The full wiki-compile + query loop currently lives in the skill, not the CLI — closing that gap is in [#13](https://github.com/nalediym/knowledge-base/issues/13).

### Session-transcript ingest — `kb ingest --sessions`

Mines installed agent stores (Claude Code, Codex CLI; Cursor stubbed) and writes one redacted markdown page per session under `kb/raw/sessions/`. Secrets — `sk-…` / `ghp_…` / named credentials / emails — are stripped before write. Combined with `kb watch` polling `kb/raw/`, ingested transcripts flow into the next compile cycle. Auto-installation of a Claude Code `SessionStart` hook is planned, not shipped ([#13](https://github.com/nalediym/knowledge-base/issues/13)).

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

- **Content-addressed chunk hashing** — every chunk gets an ID `c-XXXXXXXX` from the first 8 chars of `sha256(chunk_text)`. Stable across insertions and reorderings of OTHER chunks. Edits to the chunk content produce a new ID — see [#12](https://github.com/nalediym/knowledge-base/issues/12) for the ongoing stability rethink.
- **Compile reads raw files, not cached summaries** — source pages are intermediate artifacts. Compile re-reads `kb/raw/` to prevent stale-summary propagation.
- **Filesystem is source of truth** — works with any editor. Obsidian is an optional viewer, not a dependency.
- **Standard markdown** — no `[[wikilinks]]`, no proprietary syntax. (Heads up: input sanitization at ingest time is documented for the skill workflow but not implemented in the package adapter yet — see [#13](https://github.com/nalediym/knowledge-base/issues/13).)
- **Hallucination guard** — the skill's compile prompt forbids synthesizing claims absent from raw source chunks. Prompt-level policy at the skill layer; always verify surprising claims against raw sources.
- **Manifest locking** — file-based lock (`kb/.kb-lock`) with PID, timestamp, and 5-minute stale threshold prevents corruption from concurrent sessions.
- **Edit-protection marker convention** — the `<!-- human notes below -->` boundary is inserted at ingest time. The skill's compile flow respects it (rewrites above, leaves below); compile-time enforcement in the package compile pipeline is tracked in [#13](https://github.com/nalediym/knowledge-base/issues/13).
- **Path-based slugs** — files from different directories get unique slugs (`docs--README.md` vs `src--auth--README.md`). No collisions.
- **Secret redaction** — session-transcript ingest strips API keys (`sk-…`), GitHub tokens (`ghp_…`), named credentials, and emails before writing to disk.

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

The `@kb/store-sqlite` package combines SQLite FTS5 (porter + unicode61) and `sqlite-vec` embeddings via Reciprocal Rank Fusion (k=60, pool=4×limit). Embeddings live as raw Float32 BLOBs queryable across arbitrary dimensions. Embedding providers ship for Ollama (default, `nomic-embed-text`) and OpenAI. The Anthropic provider currently covers chat completion only — embeddings via Anthropic are not wired yet.

This is the retrieval path the skill's `query` mode uses. The package CLI / MCP `kb_query` and `kb_search` tools currently use simpler substring matching; bridging them to the hybrid retrieval is in [#13](https://github.com/nalediym/knowledge-base/issues/13).

### Contextual retrieval

[Anthropic's contextual retrieval](https://www.anthropic.com/news/contextual-retrieval) pattern is in `@kb/llm/contextualize`: per-chunk LLM call with the whole document threaded through `cache_control`, returns a short situating prefix prepended before indexing (default cap: 100 tokens).

### Lifecycle + sweep

Pages move through `draft → reviewed → verified → stale → archived` via frontmatter. `@kb/core/lifecycle-sweep` is a pure function that, given the current state, advances pages based on age (`stale_after_days`) and demotes `verified` pages whose body hash drifts from the stamped review hash. The skill calls sweep during compile; the package's compile inferrer does not yet auto-call it ([#13](https://github.com/nalediym/knowledge-base/issues/13)).

### Output re-ingestion (skill workflow)

After generating output (slides, diagrams, summaries), the skill can file it back into the wiki: copies to `kb/raw/generated/` with a `generated--` prefix. The intent is that generated sources should be excluded from confidence scoring to prevent hallucination amplification, and that lint should warn above a generated-ratio threshold — both are skill-level policies, not yet enforced by the package's confidence function or lint ([#13](https://github.com/nalediym/knowledge-base/issues/13)).

### Obsidian (optional)

The skill's `init` flow checks for Obsidian on macOS. If found, it asks once whether to enable Obsidian integration. If yes, `obsidian: true` is set in `kb.config.json` and the skill opens results via the `obsidian://` URI scheme after compile/output. The package's `kb init` only creates directories, config, index, and manifest — Obsidian detection is skill-side only ([#13](https://github.com/nalediym/knowledge-base/issues/13)).

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

The skill reads `kb.config.json` during its workflow. The package CLI doesn't load it yet — `kb ingest` currently only handles `.md` files / directories, regardless of `sources.include`. Bridging the CLI to the config is part of [#13](https://github.com/nalediym/knowledge-base/issues/13).

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
- **URL ingest:** The MCP `kb_ingest` tool returns "use the skill" for `http(s)://` paths.
- **Skill ↔ package gap:** Several smart behaviors (concept extraction, full hybrid retrieval, lifecycle auto-sweep, confidence application during compile, sanitization) live in the `/knowledge-base` skill but not yet in the package CLI/MCP. Catch-up tracked in [#13](https://github.com/nalediym/knowledge-base/issues/13).

## Roadmap

- **v0.4 (in progress):** Graph viewer (live SSE), schedule (launchd/systemd), Obsidian Web Clipper auto-ingest port.
- **v0.5:** Cursor SQLite session parser, Gemini CLI + GitHub Copilot adapters.
- **v0.6:** Review governance (pending claims, team workflows).

## References

The papers, tweets, and specs that shape KB. Linked from the sections that use them.

### Foundational

- **[Karpathy — LLM Knowledge Base pattern](https://x.com/karpathy/status/2039805659525644595)** — the original framing: raw sources compiled into a wiki an LLM can navigate. KB is one implementation of this pattern.
- **[Anthropic — Contextual Retrieval](https://www.anthropic.com/news/contextual-retrieval)** — per-chunk LLM call that prepends a situating prefix before embedding. Anthropic reports contextual embeddings + BM25 cut retrieval failure 49%, and adding a reranker cuts failure 67%. Implemented in `@kb/llm/contextualize`.
- **Cormack, Clarke, Büttcher — Reciprocal Rank Fusion** ([SIGIR 2009, PDF](https://plg.uwaterloo.ca/~gvcormac/cormacksigir09-rrf.pdf)) — the k=60 formula KB uses to merge FTS5 and semantic results.
- **Liu et al. — Lost in the Middle** ([arXiv:2307.03172](https://arxiv.org/abs/2307.03172)) — LLM attention degrades for information in the middle of long contexts. Motivates the attention-aware ordering item in *Building toward*.
- **Ebbinghaus — Forgetting curve** (Über das Gedächtnis, 1885) — exponential decay of memory over time. KB's confidence scoring applies an Ebbinghaus-style decay with τ-per-content-type.

### Protocol & interop

- **[Model Context Protocol spec](https://modelcontextprotocol.io)** — the JSON-RPC 2.0 protocol KB's stdio server implements. Nine `kb_*` tools are the canonical agent API.
- **[llmstxt.org](https://llmstxt.org)** — the `llms.txt` spec KB renders via `kb output llms-txt`.

### Adjacent / prior art

- **[Khoj AI](https://github.com/khoj-ai/khoj)** — self-hosted second brain (retrieval, not compilation).
- **[library-mcp](https://github.com/lethain/library-mcp)** — MCP server for markdown knowledge bases.
- **[Microsoft MarkItDown](https://github.com/microsoft/markitdown)** — document-to-markdown converter (good ingest layer).
- **[Obsidian Web Clipper](https://obsidian.md/clipper)** — browser extension for clipping web pages as markdown.

## License

MIT
