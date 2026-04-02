# knowledge-base

LLM-compiled knowledge base skill for [Claude Code](https://claude.ai/code).

Ingest raw sources, compile them into an interlinked markdown wiki, then query, lint, and output against it. Inspired by [Andrej Karpathy's LLM Knowledge Base pattern](https://x.com/karpathy/status/2039805659525644595).

## What it does

```
raw sources (docs, code, URLs) → LLM compiles → markdown wiki → query / lint / output
```

**6 modes:**

| Mode | What it does |
|------|-------------|
| `init <path>` | Stamp KB directory structure onto a project |
| `ingest <path>` | Index source files into the wiki |
| `compile` | Build the full wiki: index, concepts, backlinks, cross-links |
| `query <question>` | Research an answer against the wiki, with citations |
| `lint` | Health check: staleness, orphans, broken links, hallucination audit |
| `output <format>` | Render as Marp slides, Mermaid diagrams, or summaries |

## Install

### Claude Code

```bash
# Copy the skill into your Claude Code skills directory
mkdir -p ~/.claude/skills/knowledge-base
cp SKILL.md ~/.claude/skills/knowledge-base/

# Or symlink it
ln -sf "$(pwd)" ~/.claude/skills/knowledge-base
```

Then invoke with `/knowledge-base init` in any project.

### Directory structure it creates

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

## Design principles

- **Provenance first** — every generated page links back to raw sources. No orphan claims.
- **Filesystem is source of truth** — works with any editor. Obsidian is an optional viewer, not a dependency.
- **Standard markdown** — no `[[wikilinks]]`, no proprietary syntax.
- **Hallucination guard** — if the LLM can't cite it from a source, it doesn't write it.
- **Staleness detection** — file hashes in the manifest detect when sources change.

## Obsidian (optional)

The skill detects Obsidian at `init` time. If present, it can open the compiled wiki as a vault after each compile. Uses `obsidian://` URI scheme — no CLI dependency, no paid license required.

## Composability

Pairs well with other Claude Code skills:

| Skill | How |
|-------|-----|
| `/research` | Feed evidence receipts into KB as sources |
| `/build-mode` | Query KB for architecture decisions before building |
| `/cleanup-mode` | Run `lint` as part of session cleanup |

## Prior art

- [Khoj AI](https://github.com/khoj-ai/khoj) — self-hosted second brain (retrieval, not compilation)
- [library-mcp](https://github.com/lethain/library-mcp) — MCP server for markdown knowledge bases
- [Microsoft MarkItDown](https://github.com/microsoft/markitdown) — document-to-markdown converter (good ingest layer)

The novel value here is the **compilation step** — transforming raw docs into an interlinked, deduplicated wiki with provenance. Existing tools do retrieval or conversion, not synthesis.

## License

MIT
