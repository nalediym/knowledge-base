defmodule Kb.Ingest do
  @moduledoc """
  Ingests sources into the KB.

  Copies files to kb/raw/ with path-based slugs, chunks content,
  creates source pages in kb/wiki/sources/, and updates the manifest.
  Supports image downloading with link rewriting and Web Clipper integration.
  """

  def run(source_path) do
    cond do
      File.dir?(source_path) -> ingest_directory(source_path)
      File.regular?(source_path) -> ingest_file_and_update_manifest(source_path)
      String.starts_with?(source_path, "http") -> ingest_url(source_path)
      true -> IO.puts("Unknown source type: #{source_path}")
    end
  end

  @doc "Ingest new files from the Web Clipper watch directory."
  def ingest_clipper do
    {:ok, config} = read_config()
    enabled = get_in(config, ["clipper", "enabled"]) || false
    watch_dir = get_in(config, ["clipper", "watch_dir"])

    cond do
      not enabled ->
        IO.puts("Web Clipper integration is disabled. Set clipper.enabled: true in kb.config.json")

      is_nil(watch_dir) or not File.dir?(watch_dir) ->
        IO.puts("Clipper watch_dir not set or not found: #{inspect(watch_dir)}")

      true ->
        do_ingest_clipper(watch_dir)
    end
  end

  defp do_ingest_clipper(watch_dir) do
    clipper_files =
      Path.join(watch_dir, "**/*.md")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)

    case Kb.Manifest.read() do
      {:ok, manifest} ->
        existing_paths = manifest |> Map.get("sources", []) |> Enum.map(& &1["path"])

        new_files = Enum.reject(clipper_files, &(&1 in existing_paths))

        if new_files == [] do
          IO.puts("No new files found in clipper directory.")
        else
          entries = Enum.map(new_files, &ingest_file/1)

          Kb.Manifest.update("clipper-ingest", fn m ->
            Enum.reduce(entries, m, &Kb.Manifest.add_source(&2, &1))
          end)

          IO.puts("Clipped #{length(entries)} new files from #{watch_dir}")
        end

      {:error, :no_manifest} ->
        IO.puts("No KB found. Run `kb init` first.")
    end
  end

  defp ingest_file(path) do
    slug = path_to_slug(path)
    raw_dest = Path.join("kb/raw", slug)
    content = File.read!(path)
    sanitized = Kb.Sanitize.sanitize(content)

    # Download images and rewrite links BEFORE writing raw file
    {final_content, images} = maybe_download_images(sanitized, slug)
    hash = file_hash(final_content)

    File.write!(raw_dest, final_content)

    chunks = Kb.Chunk.chunk_by_heading(final_content)

    source_page = build_source_page(path, slug, hash, chunks)
    source_dest = Path.join("kb/wiki/sources", Path.rootname(slug) <> ".md")
    File.write!(source_dest, source_page)

    entry = %{
      "path" => path,
      "slug" => slug,
      "hash" => hash,
      "ingested" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "chunks" => length(chunks),
      "images" => images
    }

    IO.puts("Ingested: #{path} -> #{slug} (#{length(chunks)} chunks, #{length(images)} images)")
    entry
  end

  defp ingest_file_and_update_manifest(path) do
    entry = ingest_file(path)

    case Kb.Manifest.update("ingest", fn manifest ->
      Kb.Manifest.add_source(manifest, entry)
    end) do
      {:ok, _} -> entry
      {:error, :no_manifest} ->
        IO.puts("No KB found. Run `kb init` first.")
        entry
      {:error, :locked} ->
        IO.puts("KB is locked by another session. Try again later.")
        entry
    end
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

    # Parallel ingest: workers return entries, main thread does single manifest write
    entries =
      Task.Supervisor.async_stream_nolink(
        Kb.IngestSupervisor,
        files,
        fn file -> ingest_file(file) end,
        max_concurrency: 4,
        timeout: 30_000
      )
      |> Enum.flat_map(fn
        {:ok, entry} -> [entry]
        {:exit, reason} ->
          IO.puts("Warning: ingest failed: #{inspect(reason)}")
          []
      end)

    # Single atomic manifest update with all entries
    case Kb.Manifest.update("directory-ingest", fn manifest ->
      Enum.reduce(entries, manifest, fn entry, acc ->
        Kb.Manifest.add_source(acc, entry)
      end)
    end) do
      {:ok, _} -> :ok
      {:error, :no_manifest} -> IO.puts("No KB found. Run `kb init` first.")
      {:error, :locked} -> IO.puts("KB is locked by another session. Try again later.")
    end

    IO.puts("Ingested #{length(entries)} files from #{dir_path}")
  end

  defp ingest_url(_url) do
    IO.puts("URL ingest not yet implemented -- use the Claude Code skill for now")
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

  defp maybe_download_images(content, source_slug) do
    {:ok, config} = read_config()
    download? = get_in(config, ["images", "download"]) || false
    max_bytes = ((get_in(config, ["images", "max_size_mb"]) || 10) * 1_048_576) |> trunc()

    if download? do
      image_refs = Regex.scan(~r/!\[([^\]]*)\]\(([^)]+)\)/, content)
      media_dir = "kb/raw/media"
      File.mkdir_p!(media_dir)

      {updated_content, downloaded} =
        image_refs
        |> Enum.filter(fn [_, _alt, url] ->
          ext = url |> Path.extname() |> String.downcase()
          ext in [".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"]
        end)
        |> Enum.reduce({content, []}, fn [full_match, alt, url], {acc_content, acc_images} ->
          filename = "#{source_slug}--#{Path.basename(url)}"
          dest = Path.join(media_dir, filename)

          if File.exists?(url) do
            case File.stat(url) do
              {:ok, %{size: size}} when size <= max_bytes ->
                File.cp!(url, dest)
                local_path = "media/#{filename}"
                new_content = String.replace(acc_content, full_match, "![#{alt}](#{local_path})")
                {new_content, [filename | acc_images]}

              {:ok, %{size: size}} ->
                mb = Float.round(size / 1_048_576, 1)
                IO.puts("  Skipping large image: #{url} (#{mb}MB > #{max_bytes / 1_048_576}MB)")
                {acc_content, acc_images}

              _ ->
                {acc_content, acc_images}
            end
          else
            IO.puts("  Skipping remote image: #{url} (use Claude Code skill for URL images)")
            {acc_content, acc_images}
          end
        end)

      {updated_content, Enum.reverse(downloaded)}
    else
      {content, []}
    end
  end

  defp read_config do
    case File.read("kb.config.json") do
      {:ok, json} -> Jason.decode(json)
      {:error, _} -> {:ok, %{}}
    end
  end
end
