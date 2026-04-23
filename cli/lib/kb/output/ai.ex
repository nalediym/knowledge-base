defmodule Kb.Output.Ai do
  @moduledoc """
  AI-consumable exports for the wiki.

  Emits artifacts other agents can consume without scraping HTML:

  - `llms.txt`       — short index (llmstxt.org spec): H1 title,
                       blockquote summary, H2 sections with links
  - `llms-full.txt`  — flattened plain text of every page, capped at 5 MB
  - `graph.jsonld`   — schema.org JSON-LD graph of sources/concepts/index
  - `sitemap.xml`    — hand-rolled XML sitemap with <lastmod> from mtime
  - per-page `.txt`  — body-only plain text sibling for each wiki page
  - per-page `.json` — structured metadata + body + chunks sibling

  All outputs are written under `kb/output/` (except `.txt` / `.json`
  siblings which live next to their source `.md`).
  """

  @output_dir "kb/output"
  @wiki_dir "kb/wiki"
  # ~5 MB cap for llms-full.txt
  @llms_full_cap 5 * 1024 * 1024
  @site_base "https://example.invalid"

  # --- Entry points -------------------------------------------------------

  def run(format, opts \\ []) do
    wiki_dir = Keyword.get(opts, :wiki_dir, @wiki_dir)
    output_dir = Keyword.get(opts, :output_dir, @output_dir)
    File.mkdir_p!(output_dir)

    pages = collect_pages(wiki_dir)

    case format do
      "llms-txt" -> write_llms_txt(pages, wiki_dir, output_dir)
      "llms-full" -> write_llms_full(pages, output_dir)
      "jsonld" -> write_jsonld(pages, output_dir)
      "sitemap" -> write_sitemap(pages, output_dir)
      "all" -> write_all(pages, wiki_dir, output_dir)
      other -> {:error, {:unknown_format, other}}
    end
  end

  @doc """
  Emit `.txt` and `.json` siblings for every markdown page in the wiki.
  Returns the list of sibling paths written.
  """
  def write_siblings(opts \\ []) do
    wiki_dir = Keyword.get(opts, :wiki_dir, @wiki_dir)
    pages = collect_pages(wiki_dir)

    Enum.flat_map(pages, fn page ->
      txt_path = Path.rootname(page.path) <> ".txt"
      json_path = Path.rootname(page.path) <> ".json"

      File.write!(txt_path, to_plain_text(page))
      File.write!(json_path, page_to_json(page))

      [txt_path, json_path]
    end)
  end

  # --- Page collection ----------------------------------------------------

  @doc false
  def collect_pages(wiki_dir) do
    wiki_dir
    |> Path.join("**/*.md")
    |> Path.wildcard()
    # Skip siblings if ever mis-named (.md is our source of truth)
    |> Enum.sort()
    |> Enum.map(&read_page(&1, wiki_dir))
  end

  defp read_page(path, wiki_dir) do
    body = File.read!(path)
    {frontmatter, body_no_fm} = split_frontmatter(body)
    title = extract_title(body_no_fm) || Path.basename(path, ".md")
    rel_path = Path.relative_to(path, wiki_dir)

    category = page_category(rel_path)
    summary = extract_summary(body_no_fm)

    %{
      path: path,
      rel_path: rel_path,
      title: title,
      category: category,
      frontmatter: frontmatter,
      body: body_no_fm,
      full: body,
      summary: summary,
      mtime: file_mtime(path),
      chunks: Kb.Chunk.chunk_by_heading(body_no_fm)
    }
  end

  defp page_category(rel_path) do
    cond do
      String.starts_with?(rel_path, "concepts/") -> "concept"
      String.starts_with?(rel_path, "sources/") -> "source"
      String.starts_with?(rel_path, "candidates/") -> "candidate"
      rel_path == "index.md" -> "index"
      true -> "page"
    end
  end

  defp split_frontmatter("---\n" <> rest) do
    case String.split(rest, "\n---\n", parts: 2) do
      [fm, body] ->
        parsed =
          case YamlElixir.read_from_string(fm) do
            {:ok, map} when is_map(map) -> map
            _ -> %{}
          end

        {parsed, body}

      _ ->
        {%{}, "---\n" <> rest}
    end
  end

  defp split_frontmatter(body), do: {%{}, body}

  defp extract_title(body) do
    case Regex.run(~r/^#\s+(.+)$/m, body) do
      [_, title] -> String.trim(title)
      _ -> nil
    end
  end

  defp extract_summary(body) do
    # Prefer an explicit ## Summary section
    case Regex.run(~r/^##\s+Summary\s*\n(.*?)(?=\n##\s|\z)/ms, body) do
      [_, summary] ->
        summary |> String.trim() |> first_paragraph()

      _ ->
        # Otherwise: first non-blank, non-heading, non-blockquote paragraph
        body
        |> String.split("\n\n")
        |> Enum.map(&String.trim/1)
        |> Enum.find(fn p ->
          p != "" and not String.starts_with?(p, "#") and
            not String.starts_with?(p, ">") and
            not String.starts_with?(p, "<!--")
        end)
        |> case do
          nil -> ""
          p -> first_paragraph(p)
        end
    end
  end

  defp first_paragraph(str) do
    str
    |> String.split("\n\n", parts: 2)
    |> List.first()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> truncate(280)
  end

  defp truncate(str, max) do
    if String.length(str) > max do
      String.slice(str, 0, max - 1) <> "…"
    else
      str
    end
  end

  defp file_mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: ts}} ->
        ts |> DateTime.from_unix!() |> DateTime.to_iso8601()

      _ ->
        DateTime.utc_now() |> DateTime.to_iso8601()
    end
  end

  # --- llms.txt -----------------------------------------------------------

  defp write_llms_txt(pages, _wiki_dir, output_dir) do
    {title, summary} = index_meta(pages)

    sections =
      pages
      |> Enum.reject(&(&1.category == "index"))
      |> Enum.group_by(& &1.category)

    body = [
      "# #{title}\n",
      "\n",
      "> #{summary}\n"
    ]

    section_order = ["concept", "source", "candidate", "page"]

    section_body =
      section_order
      |> Enum.filter(&Map.has_key?(sections, &1))
      |> Enum.map(fn cat ->
        heading =
          case cat do
            "concept" -> "Concepts"
            "source" -> "Sources"
            "candidate" -> "Candidates"
            "page" -> "Pages"
          end

        entries =
          sections
          |> Map.fetch!(cat)
          |> Enum.sort_by(& &1.title)
          |> Enum.map_join("\n", fn page ->
            desc = if page.summary == "", do: "", else: ": #{page.summary}"
            "- [#{page.title}](#{page.rel_path})#{desc}"
          end)

        "\n## #{heading}\n\n#{entries}\n"
      end)
      |> Enum.join("")

    path = Path.join(output_dir, "llms.txt")
    File.write!(path, IO.iodata_to_binary([body, section_body]))
    {:ok, path}
  end

  defp index_meta(pages) do
    case Enum.find(pages, &(&1.category == "index")) do
      nil ->
        {"Knowledge Base", "LLM-compiled knowledge base"}

      idx ->
        summary =
          case extract_summary(idx.body) do
            "" -> "LLM-compiled knowledge base"
            s -> s
          end

        {idx.title, summary}
    end
  end

  # --- llms-full.txt ------------------------------------------------------

  defp write_llms_full(pages, output_dir) do
    truncation_note =
      "\n\n<!-- llms-full truncated at #{@llms_full_cap} bytes -->\n"

    {chunks, _size, truncated?} =
      Enum.reduce(pages, {[], 0, false}, fn page, {acc, size, trunc?} ->
        if trunc? do
          {acc, size, trunc?}
        else
          piece =
            """
            ====================
            # #{page.title}
            Path: #{page.rel_path}
            Category: #{page.category}
            ====================

            #{to_plain_text(page)}

            """

          piece_size = byte_size(piece)

          if size + piece_size > @llms_full_cap do
            {acc, size, true}
          else
            {[piece | acc], size + piece_size, false}
          end
        end
      end)

    payload =
      chunks
      |> Enum.reverse()
      |> IO.iodata_to_binary()

    payload = if truncated?, do: payload <> truncation_note, else: payload

    path = Path.join(output_dir, "llms-full.txt")
    File.write!(path, payload)
    {:ok, path}
  end

  # --- graph.jsonld -------------------------------------------------------

  defp write_jsonld(pages, output_dir) do
    nodes =
      pages
      |> Enum.map(&page_to_jsonld_node/1)

    doc = %{
      "@context" => "https://schema.org",
      "@graph" => nodes
    }

    path = Path.join(output_dir, "graph.jsonld")
    File.write!(path, Jason.encode!(doc, pretty: true) <> "\n")
    {:ok, path}
  end

  defp page_to_jsonld_node(page) do
    type =
      case page.category do
        "concept" -> "DefinedTerm"
        "source" -> "CreativeWork"
        "index" -> "CollectionPage"
        "candidate" -> "DefinedTerm"
        _ -> "Article"
      end

    base = %{
      "@id" => page_id(page),
      "@type" => type,
      "name" => page.title,
      "url" => page_url(page),
      "dateModified" => page.mtime,
      "category" => page.category
    }

    base =
      if page.summary == "",
        do: base,
        else: Map.put(base, "description", page.summary)

    related =
      page.body
      |> extract_markdown_links()
      |> Enum.map(fn href ->
        %{"@id" => link_to_id(page, href)}
      end)

    if related == [], do: base, else: Map.put(base, "isRelatedTo", related)
  end

  defp page_id(page), do: "kb://" <> page.rel_path
  defp page_url(page), do: Path.join(@site_base, page.rel_path)

  defp link_to_id(page, href) do
    cond do
      String.starts_with?(href, "http") ->
        href

      true ->
        resolved =
          page.rel_path
          |> Path.dirname()
          |> Path.join(href)
          |> Path.expand("/")
          |> String.trim_leading("/")

        "kb://" <> resolved
    end
  end

  defp extract_markdown_links(body) do
    Regex.scan(~r/\[[^\]]+\]\(([^)]+\.md)\)/, body)
    |> Enum.map(fn [_, href] -> href end)
    |> Enum.uniq()
  end

  # --- sitemap.xml --------------------------------------------------------

  defp write_sitemap(pages, output_dir) do
    urls =
      Enum.map_join(pages, "\n", fn page ->
        """
          <url>
            <loc>#{xml_escape(page_url(page))}</loc>
            <lastmod>#{xml_escape(page.mtime)}</lastmod>
          </url>\
        """
      end)

    doc = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{urls}
    </urlset>
    """

    path = Path.join(output_dir, "sitemap.xml")
    File.write!(path, doc)
    {:ok, path}
  end

  defp xml_escape(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  # --- `all` --------------------------------------------------------------

  defp write_all(pages, wiki_dir, output_dir) do
    [
      write_llms_txt(pages, wiki_dir, output_dir),
      write_llms_full(pages, output_dir),
      write_jsonld(pages, output_dir),
      write_sitemap(pages, output_dir)
    ]
  end

  # --- Conversions --------------------------------------------------------

  @doc false
  def to_plain_text(page) do
    page.body
    |> strip_html_comments()
    |> strip_code_fences()
    |> strip_images()
    |> strip_inline_formatting()
    |> collapse_blank_lines()
    |> String.trim()
  end

  defp strip_html_comments(str),
    do: Regex.replace(~r/<!--.*?-->/s, str, "")

  defp strip_code_fences(str) do
    # Keep the code text but strip the fences themselves
    Regex.replace(~r/```[a-zA-Z0-9_\-]*\n?/, str, "")
  end

  defp strip_images(str),
    do: Regex.replace(~r/!\[([^\]]*)\]\([^)]*\)/, str, "\\1")

  defp strip_inline_formatting(str) do
    str
    # markdown links: keep text
    |> (&Regex.replace(~r/\[([^\]]+)\]\([^)]+\)/, &1, "\\1")).()
    # bold/italic
    |> (&Regex.replace(~r/(\*\*|__)(.*?)\1/, &1, "\\2")).()
    |> (&Regex.replace(~r/(\*|_)(.*?)\1/, &1, "\\2")).()
    # inline code
    |> (&Regex.replace(~r/`([^`]+)`/, &1, "\\1")).()
  end

  defp collapse_blank_lines(str),
    do: Regex.replace(~r/\n{3,}/, str, "\n\n")

  defp page_to_json(page) do
    chunks =
      Enum.map(page.chunks, fn chunk ->
        %{
          "id" => chunk.id,
          "heading" => chunk.heading,
          "content" => chunk.content
        }
      end)

    %{
      "path" => page.rel_path,
      "title" => page.title,
      "category" => page.category,
      "frontmatter" => page.frontmatter,
      "summary" => page.summary,
      "lastmod" => page.mtime,
      "body" => page.body,
      "chunks" => chunks
    }
    |> Jason.encode!(pretty: true)
  end
end
