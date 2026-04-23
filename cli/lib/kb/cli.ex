defmodule Kb.CLI do
  @moduledoc """
  CLI entrypoint. Maps commands to modules.

  Usage:
    kb init [path]       — stamp KB directory structure
    kb add <source>      — ingest a file, directory, or URL
    kb build [--ai-siblings]
                         — compile wiki from raw sources
                           (--ai-siblings also emits .txt/.json per page)
    kb ask <question>    — query the knowledge base
    kb check             — lint health check
    kb output <format>   — render wiki as slides, diagram, summary, or graph
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

      ["build" | rest] ->
        opts = [ai_siblings: "--ai-siblings" in rest]
        Kb.Compile.run(opts)

      ["compile" | rest] ->
        opts = [ai_siblings: "--ai-siblings" in rest]
        Kb.Compile.run(opts)

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

      ["version" | _] ->
        IO.puts("kb v#{Kb.version()}")

      _ ->
        IO.puts(@moduledoc)
        System.halt(1)
    end
  end
end
