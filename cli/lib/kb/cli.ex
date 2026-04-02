defmodule Kb.CLI do
  @moduledoc """
  CLI entrypoint. Maps commands to modules.

  Usage:
    kb init [path]       — stamp KB directory structure
    kb add <source>      — ingest a file, directory, or URL
    kb build             — compile wiki from raw sources
    kb ask <question>    — query the knowledge base
    kb check             — lint health check
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

      ["version" | _] ->
        IO.puts("kb v#{Kb.version()}")

      _ ->
        IO.puts(@moduledoc)
        System.halt(1)
    end
  end
end
