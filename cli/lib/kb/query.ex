defmodule Kb.Query do
  @moduledoc """
  Query the knowledge base.

  Preferred path: SQLite FTS5 index (and embeddings when present) merged via
  reciprocal-rank fusion. Falls back to the legacy grep-style scan when no
  `kb/.index/search.sqlite` exists yet — that keeps fresh vaults working before
  the user runs `kb index`.

  Sanitizes questions before filing them to the index page.
  """

  alias Kb.{Index, Search}

  @default_top 10

  def run(question, opts \\ []) do
    sanitized = sanitize_question(question)
    IO.puts("Searching KB for: #{sanitized}\n")

    index_path = Keyword.get(opts, :index_path, Index.default_path())

    results =
      if File.exists?(index_path) do
        hybrid_query(index_path, sanitized, opts)
      else
        IO.puts("(no index at #{index_path}; run `kb index` for faster hybrid search)\n")
        grep_query(sanitized)
      end

    print_results(results)
    file_query(sanitized)
    results
  end

  defp hybrid_query(index_path, question, opts) do
    {:ok, conn} = Index.open(index_path)

    try do
      top_n = Keyword.get(opts, :top_n, @default_top)
      Search.hybrid(conn, question, top_n: top_n, top_k: top_n * 2)
    after
      Index.close(conn)
    end
  end

  defp grep_query(question) do
    sources = Path.wildcard("kb/wiki/sources/*.md")
    concepts = Path.wildcard("kb/wiki/concepts/*.md")
    needle = String.downcase(question)

    (concepts ++ sources)
    |> Enum.filter(fn path ->
      content = File.read!(path) |> String.downcase()
      String.contains?(content, needle)
    end)
    |> Enum.map(fn path ->
      %{
        path: path,
        chunk_id: nil,
        title: Path.basename(path, ".md"),
        score: 0.0,
        source: :grep
      }
    end)
  end

  defp print_results([]) do
    IO.puts("No matches found. Try different keywords.")
  end

  defp print_results(results) do
    concepts = Enum.filter(results, &String.contains?(&1.path, "/concepts/"))
    sources = Enum.filter(results, &String.contains?(&1.path, "/sources/"))
    other = results -- concepts -- sources

    if concepts != [] do
      IO.puts("## Matching Concepts\n")
      Enum.each(concepts, &print_hit/1)
      IO.puts("")
    end

    if sources != [] do
      IO.puts("## Matching Sources\n")
      Enum.each(sources, &print_hit/1)
      IO.puts("")
    end

    if other != [] do
      IO.puts("## Other\n")
      Enum.each(other, &print_hit/1)
      IO.puts("")
    end

    IO.puts("Note: Full LLM-powered Q&A requires the Claude Code skill.")
    IO.puts("The CLI provides retrieval. Use `/knowledge-base query` for synthesis.")
  end

  defp print_hit(%{path: path, title: title, score: score, source: source}) do
    label = title || Path.basename(path, ".md")
    confidence_suffix =
      case read_confidence(path) do
        nil -> ""
        c -> " (confidence: #{format_score(c)} #{Kb.Confidence.bucket(c)})"
      end

    IO.puts(
      "- #{label} — #{path} [#{source} #{:erlang.float_to_binary(score, decimals: 4)}]" <>
        confidence_suffix
    )
  end

  defp read_confidence(path) do
    with {:ok, content} <- File.read(path),
         "---\n" <> rest <- content,
         [yaml, _body] <- String.split(rest, "\n---\n", parts: 2),
         [_, raw] <- Regex.run(~r/(?m)^confidence:\s*(.+)$/, yaml) do
      case Float.parse(String.trim(raw)) do
        {f, _} -> f
        :error -> Kb.Confidence.shim_legacy(raw)
      end
    else
      _ -> nil
    end
  end

  defp format_score(s) when is_float(s), do: :erlang.float_to_binary(s, decimals: 2)
  defp format_score(s), do: to_string(s)

  # Conservative sanitizer: strip markdown control chars that could poison the
  # index page. Keeps the question semantically intact.
  defp sanitize_question(question) do
    question
    |> String.replace(~r/!\[.*?\]\(.*?\)/, "")
    |> String.replace(~r/[#\[\](){}|`<>]/, "")
    |> String.slice(0, 200)
    |> String.trim()
  end

  defp file_query(question) do
    index_path = "kb/wiki/index.md"

    if File.exists?(index_path) do
      content = File.read!(index_path)
      entry = "- #{question} — #{Date.utc_today()}\n"

      if String.contains?(content, "## Recent Queries") do
        [before_section, queries_section] = String.split(content, "## Recent Queries", parts: 2)

        existing_lines =
          queries_section
          |> String.split("\n")
          |> Enum.filter(&String.starts_with?(String.trim(&1), "- "))
          |> Enum.take(19)

        new_section =
          "## Recent Queries\n" <>
            entry <>
            Enum.join(existing_lines, "\n") <>
            "\n"

        File.write!(index_path, before_section <> new_section)
      end
    end
  end
end
