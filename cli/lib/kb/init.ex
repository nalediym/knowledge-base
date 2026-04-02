defmodule Kb.Init do
  @moduledoc "Stamps the KB directory structure onto a project."

  def run(path) do
    base = Path.join(path, "kb")

    dirs = [
      Path.join(base, "raw"),
      Path.join(base, "wiki/concepts"),
      Path.join(base, "wiki/sources"),
      Path.join(base, "output")
    ]

    Enum.each(dirs, &File.mkdir_p!/1)

    # Write manifest
    manifest = Kb.Manifest.new(Path.basename(Path.expand(path)))
    File.write!(Path.join(base, ".kb-manifest.json"), Jason.encode!(manifest, pretty: true) <> "\n")

    # Write index
    File.write!(Path.join(base, "wiki/index.md"), index_template())

    # Write config if missing
    config_path = Path.join(path, "kb.config.json")

    unless File.exists?(config_path) do
      File.write!(config_path, config_template(path))
    end

    IO.puts("KB initialized at #{base}/")
  end

  defp index_template do
    """
    # Knowledge Base Index

    > Auto-maintained by `kb build`. Do not edit manually.
    > Last compiled: —
    > Sources: 0 | Concepts: 0 | Words: 0

    ## Sources
    <!-- auto-populated -->

    ## Concepts
    <!-- auto-populated -->

    ## Uncategorized Claims
    <!-- auto-populated -->

    ## Recent Queries
    <!-- auto-populated, max 20 entries -->
    """
  end

  defp config_template(path) do
    %{
      name: Path.basename(Path.expand(path)),
      version: 1,
      sources: %{
        include: ["**/*.md", "**/*.txt", "**/*.py", "**/*.ts", "**/*.rs",
                  "**/*.json", "**/*.yaml", "**/*.csv"],
        exclude: ["node_modules/**", "dist/**", ".git/**", "kb/**"]
      },
      compile: %{
        concept_threshold: 2,
        max_context_tokens: 200_000,
        incremental: true,
        batch_size: 10
      },
      provenance: %{
        required: true,
        method: "chunk",
        chunk_strategy: "heading"
      },
      obsidian: false,
      output_dir: "kb/output"
    }
    |> Jason.encode!(pretty: true)
    |> Kernel.<>("\n")
  end
end
