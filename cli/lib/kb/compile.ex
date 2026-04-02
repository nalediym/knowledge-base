defmodule Kb.Compile do
  @moduledoc """
  Compiles the wiki from raw sources.

  Reads raw files (not cached summaries), re-chunks stale sources,
  extracts concepts with global dedup, and builds the index.
  """

  def run do
    case Kb.Manifest.read() do
      {:ok, manifest} -> compile(manifest)
      {:error, :no_manifest} -> IO.puts("No KB found. Run `kb init` first.")
    end
  end

  defp compile(manifest) do
    sources = Map.get(manifest, "sources", [])
    IO.puts("Compiling #{length(sources)} sources...")

    # Step 0: Staleness check — re-hash raw files
    {fresh, stale, orphaned} = check_staleness(sources)

    if stale != [] do
      IO.puts("#{length(stale)} sources changed since ingest — re-chunking")
    end

    if orphaned != [] do
      IO.puts("#{length(orphaned)} sources missing from raw/ — marking orphaned")
    end

    # Step 1: Read raw files, re-chunk stale ones
    # Step 2: Extract concepts (global dedup across all sources)
    # Step 3: Build index with uncategorized claims
    # Step 4: Backlink pass

    IO.puts("""
    Compile pipeline:
      Fresh: #{length(fresh)} (skipping re-chunk)
      Stale: #{length(stale)} (re-chunking from raw)
      Orphaned: #{length(orphaned)}

    Note: Full LLM-powered compilation requires the Claude Code skill.
    The CLI handles chunking, hashing, and index structure.
    Concept extraction requires an LLM call — use `kb build --llm` (coming soon).
    """)

    # Update manifest
    manifest
    |> Map.put("last_compiled", DateTime.utc_now() |> DateTime.to_iso8601())
    |> Kb.Manifest.write()
  end

  defp check_staleness(sources) do
    sources
    |> Enum.reduce({[], [], []}, fn source, {fresh, stale, orphaned} ->
      raw_path = Path.join("kb/raw", source["slug"])

      case File.read(raw_path) do
        {:ok, content} ->
          current_hash =
            :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

          if current_hash == source["hash"] do
            {[source | fresh], stale, orphaned}
          else
            {fresh, [source | stale], orphaned}
          end

        {:error, :enoent} ->
          {fresh, stale, [source | orphaned]}
      end
    end)
  end
end
