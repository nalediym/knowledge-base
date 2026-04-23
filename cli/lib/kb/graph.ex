defmodule Kb.Graph do
  @moduledoc """
  Scans `kb/wiki/**/*.md` and builds a node/edge graph of sources, concepts,
  candidates, and the references between them.

  Node types:
    * `source`    — a page under `kb/wiki/sources/`
    * `concept`   — a page under `kb/wiki/concepts/`
    * `candidate` — a referenced page that does not yet exist on disk
    * `stale`     — a source or concept whose frontmatter `Status:` is `stale`

  Edges are derived from standard markdown links `[text](rel-or-abs.md)` and
  chunk citations of the form `source.md#c-XXXXXXXX` (merged into the edge's
  citation list).
  """

  @type node_kind :: :source | :concept | :candidate | :stale

  @type graph_node :: %{
          id: String.t(),
          label: String.t(),
          kind: node_kind(),
          path: String.t() | nil,
          status: String.t() | nil
        }

  @type graph_edge :: %{
          from: String.t(),
          to: String.t(),
          citations: [String.t()]
        }

  @type graph :: %{nodes: [graph_node()], edges: [graph_edge()]}

  @doc """
  Build the graph for the given wiki root (defaults to `kb/wiki`).
  Returns `%{nodes: [...], edges: [...]}`.
  """
  @spec build(String.t()) :: graph()
  def build(wiki_root \\ "kb/wiki") do
    sources = list_pages(Path.join(wiki_root, "sources"))
    concepts = list_pages(Path.join(wiki_root, "concepts"))

    pages =
      Enum.map(sources, &page_info(&1, :source, wiki_root)) ++
        Enum.map(concepts, &page_info(&1, :concept, wiki_root))

    existing_ids =
      pages
      |> Enum.map(& &1.id)
      |> MapSet.new()

    # Collect edges and gather referenced IDs that don't match a real page.
    {raw_edges, referenced_ids} =
      pages
      |> Enum.flat_map(fn page -> extract_references(page) end)
      |> Enum.reduce({[], MapSet.new()}, fn %{to: t} = edge, {edges, refs} ->
        {[edge | edges], MapSet.put(refs, t)}
      end)

    # Candidate nodes: referenced but not on disk.
    candidate_ids = MapSet.difference(referenced_ids, existing_ids)

    candidate_nodes =
      candidate_ids
      |> Enum.sort()
      |> Enum.map(fn id ->
        %{
          id: id,
          label: humanize(id),
          kind: :candidate,
          path: nil,
          status: nil
        }
      end)

    nodes =
      pages
      |> Enum.map(fn p ->
        kind = if p.status == "stale", do: :stale, else: p.kind

        %{
          id: p.id,
          label: p.label,
          kind: kind,
          path: p.path,
          status: p.status
        }
      end)
      |> Kernel.++(candidate_nodes)
      |> Enum.sort_by(& &1.id)

    edges =
      raw_edges
      |> merge_edges()
      |> Enum.sort_by(&{&1.from, &1.to})

    %{nodes: nodes, edges: edges}
  end

  @doc """
  Builds a minimal delta for a newly-ingested source file. Used by the
  in-process simulator to test live updates.
  """
  @spec simulate_ingest_delta(String.t(), node_kind()) :: %{
          add_nodes: [graph_node()],
          add_edges: [graph_edge()]
        }
  def simulate_ingest_delta(slug, kind \\ :source) do
    %{
      add_nodes: [
        %{
          id: slug,
          label: humanize(slug),
          kind: kind,
          path: nil,
          status: "fresh"
        }
      ],
      add_edges: []
    }
  end

  # --- internal ---

  defp list_pages(dir) do
    if File.dir?(dir) do
      Path.wildcard(Path.join(dir, "*.md"))
    else
      []
    end
  end

  defp page_info(path, kind, _wiki_root) do
    content =
      case File.read(path) do
        {:ok, c} -> c
        _ -> ""
      end

    slug = Path.basename(path, ".md")

    %{
      id: slug,
      label: extract_title(content) || humanize(slug),
      kind: kind,
      path: Path.expand(path),
      status: extract_status(content),
      content: content
    }
  end

  defp extract_title(content) do
    case Regex.run(~r/^#\s+(.+)$/m, content) do
      [_, t] -> String.trim(t)
      _ -> nil
    end
  end

  defp extract_status(content) do
    case Regex.run(~r/\*\*Status:\*\*\s*([a-zA-Z-]+)/, content) do
      [_, s] -> String.downcase(String.trim(s))
      _ -> nil
    end
  end

  # Extracts all markdown links in the page that point at .md files and
  # collapses them into edges with optional chunk citations.
  #
  # Supports:
  #   * [text](path.md)             — plain link
  #   * [text](path.md#c-abcdef12)  — inline fragment form
  #   * [text](path.md)#c-abcdef12  — KB convention: fragment after close paren
  defp extract_references(%{id: from, content: content}) do
    Regex.scan(
      ~r/\[([^\]]+)\]\(([^\)\s]*?\.md)(#c-[a-zA-Z0-9]+)?\)(#c-[a-zA-Z0-9]+)?/,
      content
    )
    |> Enum.map(fn captures ->
      {_text, path, inline, trailing} =
        case captures do
          [_, t, p, inline, trailing] -> {t, p, inline, trailing}
          [_, t, p, inline] -> {t, p, inline, ""}
          [_, t, p] -> {t, p, "", ""}
        end

      chunk =
        cond do
          inline != "" -> String.trim_leading(inline, "#")
          trailing != "" -> String.trim_leading(trailing, "#")
          true -> nil
        end

      to = Path.basename(path, ".md")
      %{from: from, to: to, citation: chunk}
    end)
    |> Enum.reject(fn %{to: t} -> t == from or t == "" end)
  end

  defp merge_edges(raw_edges) do
    raw_edges
    |> Enum.group_by(fn %{from: f, to: t} -> {f, t} end)
    |> Enum.map(fn {{from, to}, list} ->
      citations =
        list
        |> Enum.map(& &1.citation)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      %{from: from, to: to, citations: citations}
    end)
  end

  defp humanize(slug) do
    slug
    |> String.replace(~r/[-_]+/, " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
