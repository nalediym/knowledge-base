defmodule Kb.Conflicts do
  @moduledoc """
  `kb lint --conflicts` — scans concept pages, collects claims from the
  source pages each concept cites, and compares claims across sources via
  a pluggable LLM provider. Writes a contradictions report under
  `kb/output/contradictions-YYYY-MM-DD.md`.

  Design notes:
    - A "claim" is a `## Key Claims` bullet on a source page. Each bullet
      looks like `- <text> — <chunk-id>` where chunk-id is `c-xxxxxxxx`.
    - Within a concept page, we only compare claims that come from
      *different* source pages (contradictions across sources are the
      signal; duplicates within one source are not).
    - Lifecycle gating: if a page has YAML frontmatter with
      `lifecycle: reviewed|verified|draft`, only reviewed/verified are
      scanned. Pages without frontmatter are treated as non-draft.
  """

  alias Kb.LLM

  @type claim :: %{
          text: String.t(),
          source: String.t(),
          source_path: String.t(),
          chunk_id: String.t()
        }

  @type finding :: %{
          concept: String.t(),
          claim_a: claim(),
          claim_b: claim(),
          note: String.t() | nil
        }

  @doc """
  Top-level entry point invoked by `Kb.CLI`.

  Opts:
    * `:provider` — `"heuristic" | "ollama" | "openai" | "anthropic"`. Default "heuristic".
    * `:kb_dir`   — KB root directory. Default `"kb"`.
    * `:output_dir` — override for report dir. Default `<kb_dir>/output`.
    * `:date`     — override report date (tests). Default today.
  """
  def run(opts \\ []) do
    kb_dir = Keyword.get(opts, :kb_dir, "kb")
    provider_name = Keyword.get(opts, :provider, "heuristic")
    provider = LLM.resolve(provider_name)
    date = Keyword.get(opts, :date, Date.utc_today())
    output_dir = Keyword.get(opts, :output_dir, Path.join(kb_dir, "output"))

    concepts_glob = Path.join([kb_dir, "wiki", "concepts", "*.md"])
    concepts = Path.wildcard(concepts_glob)

    if concepts == [] do
      IO.puts("No concept pages found under #{concepts_glob}.")
      {:ok, %{findings: [], report_path: nil}}
    else
      findings =
        concepts
        |> Enum.filter(&scan_page?/1)
        |> Enum.flat_map(fn concept_path ->
          scan_concept(concept_path, kb_dir, provider)
        end)

      report_path = write_report(findings, output_dir, date)

      IO.puts(
        "kb lint --conflicts: #{length(findings)} contradiction(s) found using `#{provider_name}` provider."
      )

      IO.puts("Report: #{report_path}")

      {:ok, %{findings: findings, report_path: report_path}}
    end
  end

  @doc """
  Returns whether a wiki page is in scope for scanning given its
  lifecycle frontmatter (if any).
  """
  def scan_page?(path) do
    case File.read(path) do
      {:ok, content} ->
        case lifecycle(content) do
          :reviewed -> true
          :verified -> true
          :draft -> false
          :none -> true
        end

      _ ->
        false
    end
  end

  @doc """
  Parse a page for a `lifecycle: X` frontmatter value. Accepts:
    - YAML frontmatter between --- fences
    - A single-line `lifecycle: X` blockquote callout
  Returns `:reviewed | :verified | :draft | :none`.
  """
  def lifecycle(content) do
    frontmatter = extract_frontmatter(content)

    value =
      cond do
        frontmatter != nil ->
          frontmatter
          |> String.split("\n")
          |> Enum.find_value(fn line ->
            case Regex.run(~r/^\s*lifecycle\s*:\s*([A-Za-z_-]+)/, line) do
              [_, v] -> String.downcase(v)
              _ -> nil
            end
          end)

        true ->
          case Regex.run(~r/\blifecycle\s*:\s*([A-Za-z_-]+)/, content) do
            [_, v] -> String.downcase(v)
            _ -> nil
          end
      end

    case value do
      "reviewed" -> :reviewed
      "verified" -> :verified
      "draft" -> :draft
      _ -> :none
    end
  end

  defp extract_frontmatter(content) do
    case Regex.run(~r/\A---\s*\n(.*?)\n---\s*\n/s, content) do
      [_, fm] -> fm
      _ -> nil
    end
  end

  # --- Concept scanning ---

  @doc false
  def scan_concept(concept_path, kb_dir, provider) do
    concept_name = Path.basename(concept_path, ".md")
    source_paths = find_referenced_sources(concept_path, kb_dir)

    claims =
      source_paths
      |> Enum.filter(&scan_page?/1)
      |> Enum.flat_map(&extract_claims/1)

    claims
    |> cross_source_pairs()
    |> Enum.flat_map(fn {a, b} ->
      case LLM.compare_claims(provider, a, b) do
        :disagree ->
          [%{concept: concept_name, claim_a: a, claim_b: b, note: nil}]

        _ ->
          []
      end
    end)
  end

  @doc """
  Find source wiki pages referenced from a concept page. Looks for
  markdown links pointing at `../sources/<name>.md` or `sources/<name>.md`.
  """
  def find_referenced_sources(concept_path, kb_dir) do
    sources_dir = Path.join([kb_dir, "wiki", "sources"])
    content = File.read!(concept_path)

    Regex.scan(~r/\]\(\.*\/?sources\/([a-zA-Z0-9_\-\.]+)\.md/, content)
    |> Enum.map(fn [_, slug] -> Path.join(sources_dir, slug <> ".md") end)
    |> Enum.uniq()
    |> Enum.filter(&File.exists?/1)
  end

  @doc """
  Parse a source page's `## Key Claims` section into a list of claims.
  Each bullet `- <text> — <chunk-id>` (em-dash or `--`) becomes one claim.
  """
  def extract_claims(source_path) do
    source_name = Path.basename(source_path, ".md")
    content = File.read!(source_path)

    case extract_section(content, "Key Claims") do
      nil ->
        []

      section ->
        section
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&String.starts_with?(&1, "-"))
        |> Enum.map(&parse_claim_bullet(&1, source_name, source_path))
        |> Enum.reject(&is_nil/1)
    end
  end

  defp extract_section(content, heading) do
    pattern = ~r/^##\s+#{Regex.escape(heading)}\s*\n(.*?)(?=^##\s|\z)/ms

    case Regex.run(pattern, content) do
      [_, body] -> body
      _ -> nil
    end
  end

  defp parse_claim_bullet(line, source, source_path) do
    # Strip leading `- `
    rest = String.replace_prefix(line, "-", "") |> String.trim()

    # Split on em-dash or `--`; chunk id is on the right side.
    parts =
      cond do
        String.contains?(rest, "—") -> String.split(rest, "—", parts: 2)
        String.contains?(rest, " -- ") -> String.split(rest, " -- ", parts: 2)
        true -> [rest]
      end

    case parts do
      [text, tail] ->
        chunk_id =
          case Regex.run(~r/(c-[a-f0-9]{6,})/i, tail) do
            [_, id] -> id
            _ -> ""
          end

        if chunk_id == "" do
          nil
        else
          %{
            text: String.trim(text),
            source: source,
            source_path: source_path,
            chunk_id: chunk_id
          }
        end

      _ ->
        nil
    end
  end

  @doc """
  Produce ordered pairs of claims that come from different source pages.
  Returns at most one ordering per pair (a < b by source name).
  """
  def cross_source_pairs(claims) do
    indexed = Enum.with_index(claims)

    for {a, i} <- indexed,
        {b, j} <- indexed,
        j > i,
        a.source != b.source do
      if a.source <= b.source, do: {a, b}, else: {b, a}
    end
  end

  # --- Report writer ---

  defp write_report(findings, output_dir, date) do
    File.mkdir_p!(output_dir)
    path = Path.join(output_dir, "contradictions-#{Date.to_iso8601(date)}.md")
    File.write!(path, render_report(findings, date))
    path
  end

  @doc false
  def render_report(findings, date) do
    header = "# Contradictions — #{Date.to_iso8601(date)}\n\n"

    if findings == [] do
      header <> "No contradictions found across scanned concept pages.\n"
    else
      grouped = Enum.group_by(findings, & &1.concept)

      body =
        grouped
        |> Enum.sort_by(fn {concept, _} -> concept end)
        |> Enum.map_join("\n", fn {concept, entries} ->
          concept_header = "## concept: #{concept}.md\n\n"
          concept_header <> Enum.map_join(entries, "\n", &render_finding/1)
        end)

      header <> body <> "\n"
    end
  end

  defp render_finding(%{claim_a: a, claim_b: b, note: note}) do
    base = """
    - Claim A: "#{a.text}"
      - Source: #{a.source}.md##{a.chunk_id}
    - Claim B: "#{b.text}"
      - Source: #{b.source}.md##{b.chunk_id}
    """

    if note do
      base <> "- Resolution: #{note}\n"
    else
      base
    end
  end
end
