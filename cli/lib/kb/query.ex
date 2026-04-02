defmodule Kb.Query do
  @moduledoc """
  Query the knowledge base.

  Searches source pages and concepts for relevant content.
  Sanitizes questions before filing to the index.
  """

  def run(question) do
    sanitized = sanitize_question(question)

    IO.puts("Searching KB for: #{sanitized}\n")

    # Search source pages for matching content
    sources = Path.wildcard("kb/wiki/sources/*.md")
    concepts = Path.wildcard("kb/wiki/concepts/*.md")

    source_matches =
      Enum.filter(sources, fn path ->
        content = File.read!(path) |> String.downcase()
        String.contains?(content, String.downcase(sanitized))
      end)

    concept_matches =
      Enum.filter(concepts, fn path ->
        content = File.read!(path) |> String.downcase()
        String.contains?(content, String.downcase(sanitized))
      end)

    if source_matches == [] and concept_matches == [] do
      IO.puts("No matches found. Try different keywords.")
    else
      if concept_matches != [] do
        IO.puts("## Matching Concepts\n")

        Enum.each(concept_matches, fn path ->
          IO.puts("- #{Path.basename(path, ".md")}")
        end)
      end

      if source_matches != [] do
        IO.puts("\n## Matching Sources\n")

        Enum.each(source_matches, fn path ->
          IO.puts("- #{Path.basename(path, ".md")}")
        end)
      end

      IO.puts("\nNote: Full LLM-powered Q&A requires the Claude Code skill.")
      IO.puts("The CLI provides keyword search. Use `/knowledge-base query` for synthesis.")
    end

    # File the query to index (sanitized, max 20)
    file_query(sanitized)
  end

  defp sanitize_question(question) do
    question
    |> String.replace(~r/[#\[\](){}|`<>]/, "")
    |> String.replace(~r/!\[.*?\]\(.*?\)/, "")
    |> String.slice(0, 200)
    |> String.trim()
  end

  defp file_query(question) do
    index_path = "kb/wiki/index.md"

    if File.exists?(index_path) do
      content = File.read!(index_path)
      entry = "- #{question} — #{Date.utc_today()}\n"

      # Find Recent Queries section and append
      if String.contains?(content, "## Recent Queries") do
        [before_section, queries_section] = String.split(content, "## Recent Queries", parts: 2)

        # Keep max 20 entries
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
