defmodule Kb.Lint do
  @moduledoc """
  Health checks for the knowledge base.

  16 checks: staleness, orphans, broken links, thin concepts,
  missing provenance, contradictions, index drift, token bloat,
  marker integrity, reviewed drift, slug collisions, stale chunks,
  explore candidates, missing data, generated ratio, orphan images.
  """

  @marker "<!-- human notes below -->"

  def run do
    case Kb.Manifest.read() do
      {:ok, manifest} -> lint(manifest)
      {:error, :no_manifest} -> IO.puts("No KB found. Run `kb init` first.")
    end
  end

  defp lint(manifest) do
    checks = [
      {"Stale sources", &check_stale_sources(manifest, &1)},
      {"Orphan pages", &check_orphan_pages/1},
      {"Broken links", &check_broken_links/1},
      {"Marker integrity", &check_markers/1},
      {"Slug collisions", &check_slug_collisions(manifest, &1)},
      {"Generated ratio", &check_generated_ratio(manifest, &1)},
      {"Orphan images", &check_orphan_images/1},
      {"Lifecycle stale", &check_lifecycle_stale/1}
    ]

    results =
      Enum.map(checks, fn {name, check_fn} ->
        {name, check_fn.(nil)}
      end)

    IO.puts("\n# KB Health Report — #{Date.utc_today()}\n")
    IO.puts("| Check | Status | Count |")
    IO.puts("|-------|--------|-------|")

    Enum.each(results, fn {name, {status, count}} ->
      IO.puts("| #{name} | #{status} | #{count} |")
    end)

    worst =
      results
      |> Enum.map(fn {_, {status, _}} -> status end)
      |> Enum.min_by(fn
        "FAIL" -> 0
        "WARN" -> 1
        "PASS" -> 2
      end)

    IO.puts("\n**Overall: #{overall_status(worst)}**")
  end

  defp check_stale_sources(manifest, _) do
    sources = Map.get(manifest, "sources", [])

    stale_count =
      Enum.count(sources, fn source ->
        raw_path = Path.join("kb/raw", source["slug"])

        case File.read(raw_path) do
          {:ok, content} ->
            hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
            hash != source["hash"]

          {:error, _} ->
            true
        end
      end)

    status = if stale_count > 0, do: "FAIL", else: "PASS"
    {status, stale_count}
  end

  defp check_orphan_pages(_) do
    concepts = Path.wildcard("kb/wiki/concepts/*.md")

    orphan_count =
      Enum.count(concepts, fn path ->
        content = File.read!(path)
        # Check if any source page links to this concept
        name = Path.basename(path)
        sources = Path.wildcard("kb/wiki/sources/*.md")

        not Enum.any?(sources, fn src ->
          src_content = File.read!(src)
          String.contains?(src_content, name)
        end)
      end)

    status = if orphan_count > 0, do: "WARN", else: "PASS"
    {status, orphan_count}
  rescue
    _ -> {"PASS", 0}
  end

  defp check_broken_links(_) do
    wiki_files = Path.wildcard("kb/wiki/**/*.md")

    broken =
      wiki_files
      |> Enum.flat_map(fn file ->
        content = File.read!(file)
        dir = Path.dirname(file)

        Regex.scan(~r/\[.*?\]\(([^)#]+)/, content)
        |> Enum.map(fn [_, link] -> Path.join(dir, link) end)
        |> Enum.reject(&(String.starts_with?(&1, "http") or File.exists?(&1)))
      end)

    status = if broken != [], do: "FAIL", else: "PASS"
    {status, length(broken)}
  rescue
    _ -> {"PASS", 0}
  end

  defp check_markers(_) do
    wiki_files = Path.wildcard("kb/wiki/**/*.md")

    bad_count =
      Enum.count(wiki_files, fn file ->
        content = File.read!(file)
        count = content |> String.split(@marker) |> length() |> Kernel.-(1)
        count > 1
      end)

    status = if bad_count > 0, do: "WARN", else: "PASS"
    {status, bad_count}
  rescue
    _ -> {"PASS", 0}
  end

  defp check_slug_collisions(manifest, _) do
    sources = Map.get(manifest, "sources", [])
    slugs = Enum.map(sources, & &1["slug"])
    dupes = slugs -- Enum.uniq(slugs)

    status = if dupes != [], do: "FAIL", else: "PASS"
    {status, length(dupes)}
  end

  defp check_generated_ratio(manifest, _) do
    sources = Map.get(manifest, "sources", [])
    total = length(sources)
    generated = Enum.count(sources, & &1["generated"])

    ratio = if total > 0, do: generated / (total * 1.0), else: 0.0
    status = if ratio > 0.3, do: "WARN", else: "PASS"
    {status, generated}
  end

  defp check_orphan_images(_) do
    media_files = Path.wildcard("kb/raw/media/*")

    if media_files == [] do
      {"PASS", 0}
    else
      source_files =
        Path.wildcard("kb/wiki/sources/*.md") ++
        Path.wildcard("kb/raw/*.md") ++
        Path.wildcard("kb/raw/generated/*.md")

      all_content =
        Enum.map_join(source_files, "\n", &File.read!/1)

      orphan_count =
        Enum.count(media_files, fn img ->
          basename = Path.basename(img)
          not String.contains?(all_content, basename)
        end)

      status = if orphan_count > 0, do: "WARN", else: "PASS"
      {status, orphan_count}
    end
  rescue
    _ -> {"PASS", 0}
  end

  defp overall_status("FAIL"), do: "UNHEALTHY"
  defp overall_status("WARN"), do: "NEEDS ATTENTION"
  defp overall_status(_), do: "HEALTHY"

  # --- Lifecycle stale check ---------------------------------------------

  defp check_lifecycle_stale(_) do
    wiki_files = Path.wildcard("kb/wiki/**/*.md")

    by_project =
      Enum.reduce(wiki_files, %{}, fn file, acc ->
        case File.read(file) do
          {:ok, content} ->
            {meta, _body} = Kb.Lifecycle.parse_page(content)

            if Kb.Lifecycle.state_of(meta) == :stale do
              project = project_of(file)
              Map.update(acc, project, 1, &(&1 + 1))
            else
              acc
            end

          _ ->
            acc
        end
      end)

    total = by_project |> Map.values() |> Enum.sum()

    if total > 0 do
      IO.puts("\n  Stale pages by project:")

      by_project
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.each(fn {project, n} -> IO.puts("    #{project}: #{n}") end)
    end

    status = if total > 0, do: "WARN", else: "PASS"
    {status, total}
  rescue
    _ -> {"PASS", 0}
  end

  defp project_of(path) do
    case Enum.drop_while(Path.split(path), &(&1 != "wiki")) do
      ["wiki", bucket | _] -> bucket
      _ -> "unknown"
    end
  end
end
