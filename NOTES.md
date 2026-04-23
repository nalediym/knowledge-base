# feat/watch-mode — P1

**Priority:** P1 (composes with session-ingest → "KB grows while I sleep")
**Branch:** `feat/watch-mode`
**Effort:** 1 day

## Why

`kb` is a manual workflow today. Competitors have `watch` modes + SessionStart hooks + OS scheduled tasks. Without this, users won't feel KB compounding.

## References

- `~/.deep-research/sessions/kb-sota-2026/repos/llm-wiki/llmwiki/watch.py` (Pratiyush) — debounced file watcher
- `~/.deep-research/sessions/kb-sota-2026/repos/llm-wiki/docs/scheduled-sync.md` — OS-specific scheduled task generation
- `~/.deep-research/sessions/kb-sota-2026/repos/swarmvault/` — watch mode + git hooks
- Claude Code `SessionStart` hook docs in `~/.claude/CLAUDE.md` or https://docs.claude.com/en/docs/claude-code/hooks

## Elixir sketch

Use `FileSystem` (Hex) for cross-platform fs-event watching.

```elixir
defmodule KB.Watch do
  use GenServer
  # Subscribe to raw/ + configured session dirs
  # Debounce 500ms; on settle → enqueue ingest for each changed file
  # Flush queue → kb ingest + kb compile (if config.watch.auto_compile)
end
```

## Three flavors of watch

1. **Foreground watch:** `kb watch` — prints events, lives until Ctrl-C
2. **Claude Code SessionStart hook:** `kb watch --install-hook` patches `~/.claude/settings.json` with a hook entry that ingests queued files at session start
3. **Scheduled task:** `kb schedule --platform {macos|linux|windows}` writes `launchd.plist` | `systemd.timer + .service` | `task.xml` with cadence from config

## Config keys (in `kb.config.json`)

```json
{
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
  }
}
```

## Acceptance criteria

- [ ] `kb watch` runs foreground, watches `kb/raw/` + configured session paths, debounces 500ms
- [ ] New file or change → queued to `kb/.queue/`
- [ ] On debounce settle → `kb ingest` each queued file; optionally `kb compile`
- [ ] `kb watch --install-hook` adds SessionStart entry to `~/.claude/settings.json` that processes queue
- [ ] `kb schedule --platform macos` writes `~/Library/LaunchAgents/com.nalediym.kb.plist`
- [ ] `kb schedule --platform linux` writes `~/.config/systemd/user/kb.{service,timer}`
- [ ] `kb schedule --platform windows` writes `task.xml` + prints `schtasks` install command
- [ ] Each scheduled-task file contains cadence + path from config
- [ ] Tests: debounce correctly coalesces 10 writes within 500ms → 1 ingest run

## Depends on

- Needs: **#3 session-transcript-ingest** (for the interesting paths to watch)
- Composes with: #5 vault-auto-detect (may watch vault root too)
