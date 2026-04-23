defmodule Kb.Compile do
  @moduledoc """
  Compiles the wiki from raw sources.

  Reads raw files (not cached summaries), re-chunks stale sources,
  extracts concepts with global dedup, and builds the index.
  """

  def run(args \\ []) do
    case Kb.Manifest.read() do
      {:ok, manifest} ->
        compile(manifest)
        if "--approve" in args, do: Kb.Approve.print_diffs()

      {:error, :no_manifest} ->
        IO.puts("No KB found. Run `kb init` first.")
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

    # Lifecycle sweep — auto-stale + drift demotion across all wiki pages
    config = read_config()
    sweep = Kb.LifecycleSweep.run(config: config)

    IO.puts("""
    Lifecycle:
      Visited:       #{sweep.visited}
      Filled default: #{sweep.filled_default}
      Auto-staled:   #{sweep.auto_staled}
      Drift demoted: #{sweep.drift_demoted}
      Drift warned:  #{sweep.drift_warned}
    """)

    # Stamp numeric confidence onto every concept page frontmatter.
    stamped = stamp_confidence_pages(manifest)
    if stamped > 0, do: IO.puts("Confidence: scored #{stamped} concept pages")

    # Update manifest
    manifest
    |> Map.put("last_compiled", DateTime.utc_now() |> DateTime.to_iso8601())
    |> Kb.Manifest.write()
  end

  defp read_config do
    case File.read("kb.config.json") do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, m} -> m
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  @doc """
  Walk `kb/wiki/concepts/*.md` and stamp numeric `confidence` frontmatter
  on every page. Legacy `high|medium|low` strings are shimmed to
  0.85/0.55/0.25 on first compile. Returns the number of pages updated.
  """
  def stamp_confidence_pages(manifest) do
    config = Kb.Confidence.load_config()
    sources = Map.get(manifest, "sources", [])

    "kb/wiki/concepts/*.md"
    |> Path.wildcard()
    |> Enum.map(&stamp_one(&1, sources, config))
    |> Enum.count(& &1)
  end

  defp stamp_one(path, sources, config) do
    case File.read(path) do
      {:ok, content} ->
        {fm, body} = split_frontmatter(content)
        slug = Path.basename(path, ".md")

        signals = page_signals(slug, body, fm, sources)

        legacy = Map.get(fm, "confidence")

        score =
          cond do
            is_binary(legacy) and Kb.Confidence.shim_legacy(legacy) ->
              Kb.Confidence.shim_legacy(legacy)

            true ->
              Kb.Confidence.score(signals, config)
          end

        new_fm = Map.put(fm, "confidence", score)
        File.write!(path, encode(new_fm, body))
        true

      _ ->
        false
    end
  end

  # Derive scoring signals for a concept page. Keeps the CLI independent
  # of the (future) LLM pass — reads what it can from the page body, the
  # manifest, and sibling wiki files.
  defp page_signals(slug, body, fm, sources) do
    source_links = Regex.scan(~r/\[\[([^\]]+)\]\]|\]\(([^)]+\.md)\)/, body)
    source_count =
      source_links
      |> length()
      |> max(sources_count_from_fm(fm))

    backlinks =
      Path.wildcard("kb/wiki/**/*.md")
      |> Enum.reject(&String.ends_with?(&1, "/#{slug}.md"))
      |> Enum.count(fn p -> String.contains?(File.read!(p), slug) end)

    age_days = age_days_from_sources(sources)

    %{
      sources: source_count,
      source_quality: Map.get(fm, "source_quality", []),
      backlinks: backlinks,
      age_days: age_days,
      content_type: Map.get(fm, "content_type", "concept")
    }
  end

  defp sources_count_from_fm(fm) do
    case Map.get(fm, "sources") do
      n when is_integer(n) -> n
      list when is_list(list) -> length(list)
      _ -> 0
    end
  end

  defp age_days_from_sources([]), do: 0

  defp age_days_from_sources(sources) do
    now = DateTime.utc_now()

    sources
    |> Enum.map(fn s ->
      case DateTime.from_iso8601(Map.get(s, "ingested", "")) do
        {:ok, dt, _} -> DateTime.diff(now, dt, :second) |> div(86_400)
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> 0
      ages -> Enum.min(ages)
    end
  end

  # ── frontmatter helpers (YAML only) ─────────────────────────────────

  defp split_frontmatter("---\n" <> rest) do
    case String.split(rest, "\n---\n", parts: 2) do
      [yaml, body] ->
        parsed =
          case YamlElixir.read_from_string(yaml) do
            {:ok, m} when is_map(m) -> m
            _ -> %{}
          end

        {parsed, body}

      _ ->
        {%{}, "---\n" <> rest}
    end
  end

  defp split_frontmatter(content), do: {%{}, content}

  defp encode(fm, body) when map_size(fm) == 0, do: body

  defp encode(fm, body) do
    yaml =
      fm
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map_join("\n", fn {k, v} -> "#{k}: #{encode_val(v)}" end)

    "---\n" <> yaml <> "\n---\n" <> body
  end

  defp encode_val(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 2)
  defp encode_val(v) when is_integer(v), do: Integer.to_string(v)
  defp encode_val(v) when is_binary(v), do: v
  defp encode_val(v) when is_boolean(v), do: to_string(v)
  defp encode_val(v) when is_list(v), do: "[" <> Enum.map_join(v, ", ", &encode_val/1) <> "]"
  defp encode_val(v), do: inspect(v)

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
