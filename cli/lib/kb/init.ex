defmodule Kb.Init do
  @moduledoc "Stamps the KB directory structure onto a project."

  @doc """
  Initialize a KB at `path`.

  Options:
    * `:yes` — accept prompt defaults (no interaction).
    * `:no_vault` — skip Obsidian vault detection.
    * `:prompt` — function used to ask the user (defaults to stdin).
      Must accept a string prompt and return a string answer.
  """
  def run(path, opts \\ []) do
    {base, config_overrides} = resolve_base(path, opts)

    dirs = [
      Path.join(base, "raw"),
      Path.join(base, "raw/media"),
      Path.join(base, "raw/generated"),
      Path.join(base, "wiki/concepts"),
      Path.join(base, "wiki/sources"),
      Path.join(base, "output")
    ]

    Enum.each(dirs, &File.mkdir_p!/1)

    # Write manifest — project name is the containing project dir, not the vault.
    project_name = Path.basename(Path.expand(path))
    manifest = Kb.Manifest.new(project_name)
    File.write!(Path.join(base, ".kb-manifest.json"), Jason.encode!(manifest, pretty: true) <> "\n")

    # Write index
    File.write!(Path.join(base, "wiki/index.md"), index_template())

    # Write config next to the kb/ root (either the vault root or the project root).
    config_root = Path.dirname(base)
    config_path = Path.join(config_root, "kb.config.json")

    unless File.exists?(config_path) do
      File.write!(config_path, config_template(project_name, config_overrides))
    end

    IO.puts("KB initialized at #{base}/")
  end

  # Returns {base_dir_for_kb, config_overrides_map}.
  defp resolve_base(path, opts) do
    project_base = Path.join(path, "kb")

    if Keyword.get(opts, :no_vault, false) do
      {project_base, %{}}
    else
      case Kb.Vault.find_vault_root(path) do
        {:ok, vault} ->
          IO.puts(:stderr, "Obsidian vault: #{vault}")
          target = Path.join(vault, "kb/")

          if accept_vault?(vault, target, opts) do
            {Path.join(vault, "kb"), %{in_vault: true, vault_path: vault}}
          else
            {project_base, %{}}
          end

        :not_found ->
          {project_base, %{}}
      end
    end
  end

  defp accept_vault?(vault, _target, opts) do
    cond do
      Keyword.get(opts, :yes, false) ->
        true

      true ->
        prompt_fn =
          Keyword.get(opts, :prompt, fn msg ->
            IO.gets(msg) |> to_string()
          end)

        answer =
          prompt_fn.("Place `kb/` inside this vault at #{vault}/kb/? (Y/n) ")
          |> to_string()
          |> String.trim()
          |> String.downcase()

        answer in ["", "y", "yes"]
    end
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

  defp config_template(project_name, overrides) do
    base = %{
      name: project_name,
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
      output_dir: "kb/output",
      images: %{
        download: true,
        max_size_mb: 10
      },
      impute: %{
        enabled: false,
        max_searches: 5
      },
      clipper: %{
        enabled: false,
        watch_dir: nil,
        auto_ingest: false
      }
    }

    base
    |> Map.merge(overrides)
    |> Jason.encode!(pretty: true)
    |> Kernel.<>("\n")
  end
end
