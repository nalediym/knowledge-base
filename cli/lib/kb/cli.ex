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

      ["lint" | rest] ->
        run_lint(rest)

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

  defp run_lint(args) do
    cond do
      "--conflicts" in args ->
        provider = parse_flag(args, "--provider") || "heuristic"
        Kb.Conflicts.run(provider: provider)

      args == [] ->
        Kb.Lint.run()

      true ->
        IO.puts("Usage: kb lint --conflicts [--provider heuristic|ollama|openai|anthropic]")
        System.halt(1)
    end
  end

  defp parse_flag(args, name) do
    case Enum.find_index(args, &(&1 == name)) do
      nil -> nil
      idx -> Enum.at(args, idx + 1)
    end
  end
end
