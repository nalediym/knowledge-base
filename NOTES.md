# feat/mcp-server — P0

**Priority:** P0 (zero discovery without this)
**Branch:** `feat/mcp-server`
**Effort:** ~3-6 hrs
**Goal:** expose `kb` functionality as an MCP stdio server so users can drop it into `.mcp.json` / `claude_desktop_config.json`.

## Why

Every 2026 PKM tool on GitHub has an MCP server. KB has none → invisible to Claude Code / Cursor / Claude Desktop users.

## References (after running scripts/clone-competitors.sh)

- **Primary ref:** `~/.deep-research/sessions/kb-sota-2026/repos/llm-wiki/llmwiki/mcp.py` — stdlib-only, no SDK dep, 12 tools (Pratiyush)
- **Secondary:** `~/.deep-research/sessions/kb-sota-2026/repos/basic-memory/src/basic_memory/mcp/` — AGPL Python, richer tool set
- **Production ref:** `~/.deep-research/sessions/kb-sota-2026/repos/swarmvault/` — TypeScript, stdio transport
- **Obsidian MCPs for tool naming convention:**
  - `~/.deep-research/sessions/kb-sota-2026/repos/obsidian-mcp-server/` (cyanheads)
  - `~/.deep-research/sessions/kb-sota-2026/repos/obsidian-mcp-tools/` (jacksteamdev)

## Tools to expose (minimum viable set of 9)

| Tool | Args | Returns |
|------|------|---------|
| `kb_query` | `question`, `max_pages?` | answer text + page refs + citations |
| `kb_search` | `term`, `include_raw?` | list of matching pages with snippets |
| `kb_list_sources` | `project?` | metadata for all ingested sources |
| `kb_read_page` | `path` (path-traversal guarded) | page content + frontmatter |
| `kb_lint` | (none) | scorecard JSON |
| `kb_ingest` | `path` | ingest result (file count, slug map) |
| `kb_compile` | `dry_run?` | compile summary (counts, token estimate) |
| `kb_export` | `format` (llms-txt, jsonld, marp, mermaid) | rendered artifact or path |
| `kb_dashboard` | (none) | counts by type/lifecycle/confidence |

## Elixir implementation sketch

- Subcommand: `kb mcp` launches stdio JSON-RPC loop
- Use `Jason` for encoding, read/write over `:stdio`
- Each tool delegates to existing `KB.Commands.*` modules
- Path guard: `Path.safe_relative_to/2` vs `$KB_ROOT`

## Acceptance criteria

- [ ] `kb mcp` starts an MCP stdio server (responds to `initialize`)
- [ ] All 9 tools registered with `tools/list`
- [ ] `tools/call` routes to correct handler; each returns structured JSON
- [ ] Path args reject `..` and paths outside `$KB_ROOT` (test with `../../etc/passwd`)
- [ ] Integration test: add to `claude_desktop_config.json` → query works
- [ ] README section: "Using KB as an MCP server" with snippet for Claude Desktop + Claude Code `.mcp.json`
- [ ] After shipping: PR to `hesreallyhim/awesome-claude-code` under a Knowledge Bases section

## Bench

**Competitor stdio servers to benchmark against:**
- Pratiyush `python3 -m llmwiki.mcp` — 12 tools
- Basic Memory `basic-memory mcp` — ~15 tools
- SwarmVault `swarmvault mcp` — ~20 tools

Aim for 9 tools in v1; grow toward 15.

## Does-not-block

Nothing. Start here.
