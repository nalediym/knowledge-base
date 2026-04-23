defmodule Kb.CLI do
  @moduledoc """
  CLI entrypoint. Maps commands to modules.

  Usage:
    kb init [path]       — stamp KB directory structure
    kb add <source>      — ingest a file, directory, or URL
    kb build             — compile wiki from raw sources
                           (pass --approve to diff each candidate before staging)
    kb compile           — alias for kb build
    kb approve [<name>]  — promote candidates/<name>.md -> concepts/<name>.md
                           (use --all to bulk promote, --force to overwrite)
    kb review <page>     — promote a page: draft → reviewed
    kb verify <page>     — promote a page: reviewed → verified (stamps REVIEWED)
    kb archive <page>    — archive a page (any state → archived)
    kb ask <question>    — query the knowledge base
    kb check             — lint health check
    kb lint              — alias for kb check
    kb output <format>   — render wiki as slides, diagram, summary, or graph
    kb file <path>       — re-ingest an output artifact back into the wiki
    kb clip              — ingest new files from Web Clipper watch directory
    kb mcp               — launch MCP stdio server (JSON-RPC 2.0 on stdio)
    kb ingest --sessions [--agent claude|codex|all]
                         — mine agent session transcripts into kb/raw/sessions/
    kb watch [--hook] [--poll-ms 500]
                         — debounced poll of raw/session dirs; optional SessionStart hook
    kb schedule --platform {macos|linux|windows} [--output <file>]
                         — emit launchd/systemd/task.xml scaffolds
    kb version           — print version
  """

  def main(args) do
    case args do
      ["init" | rest] ->
        path = List.first(rest) || "."
        Kb.Init.run(path)

      ["add" | sources] when sources != [] ->
        Enum.each(sources, &Kb.Ingest.run/1)

      ["ingest" | rest] ->
        handle_ingest(rest)

      ["build" | rest] ->
        Kb.Compile.run(rest)

      ["approve" | rest] ->
        Kb.Approve.run(rest)

      ["compile" | _] ->
        Kb.Compile.run()

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

      ["check" | _] ->
        Kb.Lint.run()

      ["output" | rest] ->
        format = List.first(rest) || "summary"
        Kb.Output.run(format)

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
end
