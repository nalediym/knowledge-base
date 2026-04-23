defmodule Kb.CLI do
  @moduledoc """
  CLI entrypoint. Maps commands to modules.

  Usage:
    kb init [path] [--yes] [--no-vault]
                                 — stamp KB (auto-detects Obsidian vault)
    kb add <source>              — ingest a file, directory, or URL
    kb build [--approve] [--ai-siblings]
                                 — compile wiki from raw sources
                                   (--approve diffs candidates before staging;
                                    --ai-siblings emits .txt/.json per page)
    kb compile                   — alias for kb build
    kb approve [<name>]          — promote candidates/<name>.md -> concepts/<name>.md
                                   (use --all to bulk promote, --force to overwrite)
    kb review <page>             — promote a page: draft → reviewed
    kb verify <page>             — promote a page: reviewed → verified (stamps REVIEWED)
    kb archive <page>            — archive a page (any state → archived)
    kb index [--include-raw] [--embeddings]
                                 — build SQLite FTS5 index (+ optional Ollama embeddings)
    kb query <question>          — hybrid retrieval (FTS + embeddings via RRF)
    kb ask <question>            — alias for `kb query`
    kb check                     — lint health check
    kb lint                      — alias for kb check
    kb output <format>           — render wiki as slides, diagram, summary, or graph
    kb graph serve [--port N] [--no-open]
                                 — launch interactive graph viewer (SSE live updates)
    kb file <path>               — re-ingest an output artifact back into the wiki
    kb clip                      — ingest new files from Web Clipper watch directory
    kb mcp                       — launch MCP stdio server (JSON-RPC 2.0 on stdio)
    kb ingest --sessions [--agent claude|codex|all]
                                 — mine agent session transcripts into kb/raw/sessions/
    kb watch [--hook] [--poll-ms 500]
                                 — debounced poll of raw/session dirs; SessionStart hook
    kb schedule --platform {macos|linux|windows} [--output <file>]
                                 — emit launchd/systemd/task.xml scaffolds
    kb obsidian:daily <message>  — append to today's Obsidian daily note
    kb obsidian:base <query>     — query an Obsidian Base
    kb obsidian:status           — show Obsidian CLI binary + reachability
    kb version                   — print version
  """

  def main(args) do
    case args do
      ["init" | rest] ->
        {opts, positional} = parse_init_args(rest)
        path = List.first(positional) || "."
        Kb.Init.run(path, opts)

      ["add" | sources] when sources != [] ->
        Enum.each(sources, &Kb.Ingest.run/1)

      ["ingest" | rest] ->
        handle_ingest(rest)

      ["build" | rest] ->
        Kb.Compile.run(rest)

      ["approve" | rest] ->
        Kb.Approve.run(rest)

      ["compile" | rest] ->
        Kb.Compile.run(rest)

      ["lint" | _] ->
        Kb.Lint.run()

      ["review", page | _] ->
        Kb.LifecycleCLI.run(:review, page)

      ["verify", page | _] ->
        Kb.LifecycleCLI.run(:verify, page)

      ["archive", page | _] ->
        Kb.LifecycleCLI.run(:archive, page)

      ["ask" | words] when words != [] ->
        question = Enum.join(words, " ")
        Kb.Query.run(question)

      ["query" | words] when words != [] ->
        question = Enum.join(words, " ")
        Kb.Query.run(question)

      ["index" | rest] ->
        run_index(rest)

      ["check" | _] ->
        Kb.Lint.run()

      ["output" | rest] ->
        format = List.first(rest) || "summary"
        Kb.Output.run(format)

      ["graph", "serve" | rest] ->
        opts = parse_graph_serve_opts(rest)
        Kb.Graph.Server.start(opts)

      ["graph" | _] ->
        IO.puts("Usage: kb graph serve [--port 4000] [--no-open]")
        System.halt(1)

      ["file" | paths] when paths != [] ->
        Enum.each(paths, &Kb.Output.file_back/1)

      ["clip" | _] ->
        Kb.Ingest.ingest_clipper()

      ["mcp" | _] ->
        Kb.MCP.run()

      ["watch" | rest] ->
        Kb.Watch.run(rest)

      ["schedule" | rest] ->
        Kb.Watch.Schedule.run(rest)

      ["obsidian:daily" | words] when words != [] ->
        message = Enum.join(words, " ")

        case Kb.Obsidian.daily_append(message) do
          :ok -> IO.puts("Appended to daily note.")
          {:error, reason} -> IO.puts("Obsidian daily:append failed: #{inspect(reason)}")
        end

      ["obsidian:base" | words] when words != [] ->
        query = Enum.join(words, " ")

        case Kb.Obsidian.base_query(query) do
          :ok -> IO.puts("Base query dispatched.")
          {:error, reason} -> IO.puts("Obsidian base:query failed: #{inspect(reason)}")
        end

      ["obsidian:status" | _] ->
        case Kb.Obsidian.status() do
          {:ok, %{binary: bin, running: true, version: v}} ->
            IO.puts("Obsidian CLI: #{bin}")
            IO.puts("Running: yes")
            IO.puts("Version: #{v}")

          {:ok, %{binary: bin, running: false}} ->
            IO.puts("Obsidian CLI: #{bin}")
            IO.puts("Running: no (desktop app not responding)")

          {:error, :unsupported_os} ->
            IO.puts("Obsidian CLI is unsupported on Windows (v1).")

          {:error, :not_found} ->
            IO.puts("Obsidian CLI not found on PATH. Falling back to obsidian:// URL scheme.")
        end

      ["version" | _] ->
        IO.puts("kb v#{Kb.version()}")

      _ ->
        IO.puts(@moduledoc)
        System.halt(1)
    end
  end

  defp handle_ingest(args) do
    {flags, _rest, _invalid} =
      OptionParser.parse(args,
        switches: [sessions: :boolean, agent: :string, dry_run: :boolean],
        aliases: [a: :agent]
      )

    cond do
      Keyword.get(flags, :sessions, false) ->
        opts =
          []
          |> maybe_put(:agent, Keyword.get(flags, :agent))
          |> maybe_put(:dry_run, Keyword.get(flags, :dry_run))

        KB.Commands.IngestSessions.run(opts)

      true ->
        IO.puts("Usage: kb ingest --sessions [--agent claude|codex|all] [--dry-run]")
        System.halt(1)
    end
  end

  defp maybe_put(kw, _k, nil), do: kw
  defp maybe_put(kw, k, v), do: Keyword.put(kw, k, v)

  defp parse_init_args(args) do
    Enum.reduce(args, {[], []}, fn
      "--yes", {opts, pos} -> {[{:yes, true} | opts], pos}
      "-y", {opts, pos} -> {[{:yes, true} | opts], pos}
      "--no-vault", {opts, pos} -> {[{:no_vault, true} | opts], pos}
      other, {opts, pos} -> {opts, pos ++ [other]}
    end)
  end

  defp run_index(flags) do
    include_raw? = "--include-raw" in flags
    embeddings? = "--embeddings" in flags

    opts = [include_raw: include_raw?, embeddings: embeddings?]

    {:ok, stats} = Kb.Index.build(opts)

    IO.puts(
      "Indexed #{stats.files} files, #{stats.chunks} chunks " <>
        "(reindexed #{stats.reindexed}, embedded #{stats.embedded})."
    )
  end

  defp parse_graph_serve_opts(args) do
    {parsed, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [port: :integer, open: :boolean, wiki_root: :string],
        aliases: [p: :port]
      )

    port = Keyword.get(parsed, :port, 4000)
    open? = Keyword.get(parsed, :open, true)
    wiki_root = Keyword.get(parsed, :wiki_root, "kb/wiki")

    [port: port, open?: open?, wiki_root: wiki_root]
  end
end
