defmodule Kb.CLI do
  @moduledoc """
  CLI entrypoint. Maps commands to modules.

  Usage:
    kb init [path]               — stamp KB directory structure
    kb add <source>              — ingest a file, directory, or URL
    kb build                     — compile wiki from raw sources
    kb ask <question>            — query the knowledge base
    kb check                     — lint health check
    kb output <format>           — render wiki as slides, diagram, summary, or graph
    kb file <path>               — re-ingest an output artifact back into the wiki
    kb clip                      — ingest new files from Web Clipper watch directory
    kb obsidian:daily <message>  — append to today's Obsidian daily note
    kb obsidian:base <query>     — query an Obsidian Base
    kb obsidian:status           — show Obsidian CLI binary + reachability
    kb version                   — print version
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

      ["file" | paths] when paths != [] ->
        Enum.each(paths, &Kb.Output.file_back/1)

      ["clip" | _] ->
        Kb.Ingest.ingest_clipper()

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
end
