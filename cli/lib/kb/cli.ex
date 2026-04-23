defmodule Kb.CLI do
  @moduledoc """
  CLI entrypoint. Maps commands to modules.

  Usage:
    kb init [path]          — stamp KB directory structure
    kb add <source>         — ingest a file, directory, or URL
    kb build                — compile wiki from raw sources
    kb index [--include-raw] [--embeddings]
                           — build SQLite FTS5 index (+ optional Ollama embeddings)
    kb query <question>     — hybrid retrieval (FTS + embeddings via RRF)
    kb ask <question>       — alias for `kb query`
    kb check                — lint health check
    kb output <format>      — render wiki as slides, diagram, summary, or graph
    kb file <path>          — re-ingest an output artifact back into the wiki
    kb clip                 — ingest new files from Web Clipper watch directory
    kb version              — print version
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
end
