defmodule Kb.CLI do
  @moduledoc """
  CLI entrypoint. Maps commands to modules.

  Usage:
    kb init [path] [--yes] [--no-vault]
                         — stamp KB directory structure (auto-detects Obsidian vault)
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
        {opts, positional} = parse_init_args(rest)
        path = List.first(positional) || "."
        Kb.Init.run(path, opts)

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

  defp parse_init_args(args) do
    Enum.reduce(args, {[], []}, fn
      "--yes", {opts, pos} -> {[{:yes, true} | opts], pos}
      "-y", {opts, pos} -> {[{:yes, true} | opts], pos}
      "--no-vault", {opts, pos} -> {[{:no_vault, true} | opts], pos}
      other, {opts, pos} -> {opts, pos ++ [other]}
    end)
  end
end
