defmodule Kb.Output do
  @moduledoc """
  Renders wiki content in visual formats and supports re-ingestion.

  Formats: slides (Marp), diagram (Mermaid), summary (condensed markdown),
  graph (Mermaid concept graph with bidirectional links).

  Re-ingestion: `file_back/1` copies an output artifact to kb/raw/generated/
  and ingests it with generated provenance markers.
  """

  @output_dir "kb/output"
  @generated_dir "kb/raw/generated"

  def run(format) do
    case Kb.Manifest.read() do
      {:ok, _manifest} -> render(format)
      {:error, :no_manifest} -> IO.puts("No KB found. Run `kb init` first.")
    end
  end

  defp render(format) do
    concepts = Path.wildcard("kb/wiki/concepts/*.md")

    if concepts == [] do
      IO.puts("No concepts compiled yet. Run `kb build` first.")
    else
      File.mkdir_p!(@output_dir)

      case format do
        "slides" -> render_slides(concepts)
        "diagram" -> render_diagram(concepts)
        "graph" -> render_graph(concepts)
        "summary" -> render_summary(concepts)
        ai when ai in ["llms-txt", "llms-full", "jsonld", "sitemap", "all"] -> render_ai(ai)
        other -> IO.puts("Unknown format: #{other}. Options: slides, diagram, graph, summary, llms-txt, llms-full, jsonld, sitemap, all")
      end
    end
  end

  defp render_ai(format) do
    case Kb.Output.Ai.run(format) do
      {:ok, path} ->
        IO.puts("Wrote #{path}")

      results when is_list(results) ->
        Enum.each(results, fn
          {:ok, path} -> IO.puts("Wrote #{path}")
          other -> IO.inspect(other, label: "output")
        end)

      {:error, {:unknown_format, other}} ->
        IO.puts("Unknown AI format: #{other}")
    end
  end

  defp render_slides(concepts) do
    slides =
      ["---\nmarp: true\ntheme: default\n---\n\n# Knowledge Base\n\n---\n" |
       Enum.map(concepts, fn path ->
         content = File.read!(path)
         title = extract_title(content)
         definition = extract_section(content, "Definition")
         "\n## #{title}\n\n#{definition}\n\n---\n"
       end)]

    output_path = Path.join(@output_dir, "kb-slides.md")
    File.write!(output_path, Enum.join(slides))
    IO.puts("Slides written to #{output_path}")
    offer_file_back(output_path)
  end

  defp render_diagram(concepts) do
    nodes = parse_concept_nodes(concepts)

    mermaid = "```mermaid\ngraph TD\n" <>
      Enum.map_join(nodes, "\n", fn {name, connections} ->
        id = slugify(name)
        Enum.map_join(connections, "\n", fn conn ->
          conn_id = slugify(conn)
          "  #{id} --> #{conn_id}"
        end)
      end) <> "\n```\n"

    output_path = Path.join(@output_dir, "concept-diagram.md")
    File.write!(output_path, "# Concept Diagram\n\n#{mermaid}")
    IO.puts("Diagram written to #{output_path}")
    offer_file_back(output_path)
  end

  defp render_graph(concepts) do
    # Full bidirectional graph: every link appears in both directions
    nodes = parse_concept_nodes(concepts)
    concept_names = Enum.map(nodes, fn {name, _} -> name end) |> MapSet.new()

    # Build bidirectional edge set
    edges =
      nodes
      |> Enum.flat_map(fn {name, connections} ->
        connections
        |> Enum.filter(&MapSet.member?(concept_names, &1))
        |> Enum.flat_map(fn conn ->
          # Normalize edge direction to avoid duplicates
          edge = if name < conn, do: {name, conn}, else: {conn, name}
          [edge]
        end)
      end)
      |> Enum.uniq()

    mermaid = "```mermaid\ngraph LR\n" <>
      Enum.map_join(edges, "\n", fn {a, b} ->
        "  #{slugify(a)} <--> #{slugify(b)}"
      end) <> "\n```\n"

    # Add isolated nodes (no connections)
    isolated =
      nodes
      |> Enum.filter(fn {_, conns} -> conns == [] end)
      |> Enum.map_join("\n", fn {name, _} -> "  #{slugify(name)}" end)

    full_mermaid = if isolated != "", do: mermaid <> isolated <> "\n", else: mermaid

    output_path = Path.join(@output_dir, "concept-graph.md")
    File.write!(output_path, "# Concept Graph\n\n#{full_mermaid}")
    IO.puts("Graph written to #{output_path}")
    offer_file_back(output_path)
  end

  defp render_summary(concepts) do
    summary =
      Enum.map_join(concepts, "\n\n", fn path ->
        content = File.read!(path)
        title = extract_title(content)
        definition = extract_section(content, "Definition")
        "### #{title}\n\n#{definition}"
      end)

    output_path = Path.join(@output_dir, "kb-summary.md")
    File.write!(output_path, "# Knowledge Base Summary\n\n#{summary}\n")
    IO.puts("Summary written to #{output_path}")
    offer_file_back(output_path)
  end

  @doc """
  Re-ingest an output artifact back into the wiki as a generated source.
  Returns {:ok, entry} or {:error, reason}.
  """
  def file_back(path) do
    unless File.exists?(path) do
      IO.puts("File not found: #{path}")
      return_error(:file_not_found)
    end

    File.mkdir_p!(@generated_dir)
    filename = "generated--#{Path.basename(path)}"
    dest = Path.join(@generated_dir, filename)
    File.cp!(path, dest)

    content = File.read!(dest)
    hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
    chunks = Kb.Chunk.chunk_by_heading(content)

    source_page = build_generated_source_page(path, filename, hash, chunks)
    source_dest = Path.join("kb/wiki/sources", Path.rootname(filename) <> ".md")
    File.write!(source_dest, source_page)

    entry = %{
      "path" => path,
      "slug" => filename,
      "hash" => hash,
      "ingested" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "chunks" => length(chunks),
      "generated" => true
    }

    case Kb.Manifest.update("file-back", fn manifest ->
      Kb.Manifest.add_source(manifest, entry)
    end) do
      {:ok, _} ->
        IO.puts("Filed back: #{path} -> #{filename} (generated source)")
        {:ok, entry}

      {:error, :no_manifest} ->
        IO.puts("No KB found. Run `kb init` first.")
        {:error, :no_manifest}

      {:error, :locked} ->
        IO.puts("KB is locked by another session. Try again later.")
        {:error, :locked}
    end
  end

  defp return_error(reason), do: {:error, reason}

  defp offer_file_back(path) do
    IO.puts("\nFile this output back into the wiki? Use: kb file #{path}")
  end

  defp build_generated_source_page(original_path, _slug, hash, chunks) do
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
    # #{Path.basename(original_path)}

    > **Source:** #{original_path}
    > **Provenance:** generated
    > **Ingested:** #{Date.utc_today()}
    > **Hash:** #{hash}
    > **Status:** fresh
    > **Chunks:** #{length(chunks)}

    ## Chunks
    #{chunk_sections}

    ## Key Claims
    <!-- populated by compile, excluded from confidence scoring -->

    ## Related Concepts
    <!-- populated by compile -->

    <!-- human notes below -->
    """
  end

  defp parse_concept_nodes(concepts) do
    Enum.map(concepts, fn path ->
      name = Path.basename(path, ".md")
      content = File.read!(path)
      connections = extract_connections(content)
      {name, connections}
    end)
  end

  defp extract_title(content) do
    case Regex.run(~r/^# (.+)$/m, content) do
      [_, title] -> title
      _ -> "Untitled"
    end
  end

  defp extract_section(content, section_name) do
    case Regex.run(~r/## #{section_name}\n(.*?)(?=\n##|\z)/s, content) do
      [_, body] -> String.trim(body) |> String.slice(0, 300)
      _ -> ""
    end
  end

  defp extract_connections(content) do
    Regex.scan(~r/\[([^\]]+)\]\(([^\)]*\.md)\)/, content)
    |> Enum.map(fn [_, _name, path] -> Path.basename(path, ".md") end)
    |> Enum.uniq()
  end

  defp slugify(name) do
    String.replace(name, ~r/[^a-zA-Z0-9]/, "_")
  end
end
