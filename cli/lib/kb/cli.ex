defmodule Kb.CLI do
  @moduledoc """
  CLI entrypoint. Maps commands to modules.

  Usage:
    kb init [path]       — stamp KB directory structure
    kb add <source>      — ingest a file, directory, or URL
    kb build             — compile wiki from raw sources
    kb ask <question>    — query the knowledge base
    kb check             — lint health check
    kb output <format>   — render wiki as slides, diagram, summary, or graph
    kb graph serve       — launch interactive graph viewer (live updates via SSE)
    kb file <path>       — re-ingest an output artifact back into the wiki
    kb clip              — ingest new files from Web Clipper watch directory
    kb version           — print version
  """

  def main(args) do
    case args do
      ["init" | rest] ->
        path = List.first(rest) || "."
        Kb.Init.run(path)

      ["add" | sources] when sources != [] ->
        Enum.each(sources, &Kb.Ingest.run/1)

      ["build" | _] ->
        Kb.Compile.run()

      ["ask" | words] when words != [] ->
        question = Enum.join(words, " ")
        Kb.Query.run(question)

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

      ["version" | _] ->
        IO.puts("kb v#{Kb.version()}")

      _ ->
        IO.puts(@moduledoc)
        System.halt(1)
    end
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
