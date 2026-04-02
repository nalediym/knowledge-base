defmodule Kb.Ingest do
  @moduledoc """
  Ingests sources into the KB.

  Copies files to kb/raw/ with path-based slugs, chunks content,
  creates source pages in kb/wiki/sources/, and updates the manifest.
  """

  def run(source_path) do
    cond do
      File.dir?(source_path) -> ingest_directory(source_path)
      File.regular?(source_path) -> ingest_file(source_path)
      String.starts_with?(source_path, "http") -> ingest_url(source_path)
      true -> IO.puts("Unknown source type: #{source_path}")
    end
  end

  defp ingest_file(path) do
    slug = path_to_slug(path)
    raw_dest = Path.join("kb/raw", slug)
    content = File.read!(path)
    sanitized = Kb.Sanitize.sanitize(content)
    hash = file_hash(sanitized)

    File.write!(raw_dest, sanitized)

    chunks = Kb.Chunk.chunk_by_heading(sanitized)

    source_page = build_source_page(path, slug, hash, chunks)
    source_dest = Path.join("kb/wiki/sources", Path.rootname(slug) <> ".md")
    File.write!(source_dest, source_page)

    # Update manifest (serialized)
    {:ok, manifest} = Kb.Manifest.read()

    entry = %{
      "path" => path,
      "slug" => slug,
      "hash" => hash,
      "ingested" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "chunks" => length(chunks)
    }

    manifest
    |> Kb.Manifest.add_source(entry)
    |> Kb.Manifest.write()

    IO.puts("Ingested: #{path} → #{slug} (#{length(chunks)} chunks)")
  end

  defp ingest_directory(dir_path) do
    {:ok, config} = read_config()
    includes = get_in(config, ["sources", "include"]) || ["**/*.md"]
    excludes = get_in(config, ["sources", "exclude"]) || []

    files =
      includes
      |> Enum.flat_map(fn pattern ->
        Path.join(dir_path, pattern) |> Path.wildcard()
      end)
      |> Enum.reject(fn file ->
        Enum.any?(excludes, fn pattern ->
          String.contains?(file, String.replace(pattern, "**", ""))
        end)
      end)
      |> Enum.filter(&File.regular?/1)

    # Parallel ingest via Task.Supervisor, but serialize manifest writes
    tasks =
      Task.Supervisor.async_stream_nolink(
        Kb.IngestSupervisor,
        files,
        fn file -> ingest_file(file) end,
        max_concurrency: 4,
        timeout: 30_000
      )

    Enum.each(tasks, fn
      {:ok, _} -> :ok
      {:exit, reason} -> IO.puts("Warning: ingest failed: #{inspect(reason)}")
    end)

    IO.puts("Ingested #{length(files)} files from #{dir_path}")
  end

  defp ingest_url(_url) do
    IO.puts("URL ingest not yet implemented — use the Claude Code skill for now")
  end

  defp path_to_slug(path) do
    path
    |> String.replace("/", "--")
    |> String.replace(~r/^\.--/, "")
  end

  defp file_hash(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  defp build_source_page(path, _slug, hash, chunks) do
    chunk_sections =
      chunks
      |> Enum.map(fn chunk ->
        """
        ### #{chunk.id}: #{chunk.heading}
        > #{String.slice(chunk.content, 0, 300)}
        """
      end)
      |> Enum.join("\n")

    """
    # #{Path.basename(path)}

    > **Source:** #{path}
    > **Ingested:** #{Date.utc_today()}
    > **Hash:** #{hash}
    > **Status:** fresh
    > **Chunks:** #{length(chunks)}

    ## Chunks
    #{chunk_sections}

    ## Key Claims
    <!-- populated by compile -->

    ## Related Concepts
    <!-- populated by compile -->

    <!-- human notes below -->
    """
  end

  defp read_config do
    case File.read("kb.config.json") do
      {:ok, json} -> Jason.decode(json)
      {:error, _} -> {:ok, %{}}
    end
  end
end
