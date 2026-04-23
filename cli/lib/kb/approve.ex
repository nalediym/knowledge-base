defmodule Kb.Approve do
  @moduledoc """
  Candidates / approval workflow.

  New concept pages produced by `kb build` land in `kb/wiki/candidates/<name>.md`
  instead of `kb/wiki/concepts/<name>.md`. Existing concepts (already in
  `concepts/`) are updated in-place and are never routed to candidates.

  Approval promotes a candidate to a concept via a file move:

      kb approve <name>        # single concept
      kb approve --all         # bulk promote every candidate
      kb build --approve       # compile, then print a diff of each candidate
                               # vs its existing concept (or "NEW" when none)
                               # before staging for approval

  `kb approve` refuses to overwrite an existing concept page unless `--force`
  is passed. Existing concepts already in `concepts/` are untouched by the
  routing logic.
  """

  @candidates_dir "kb/wiki/candidates"
  @concepts_dir "kb/wiki/concepts"

  def candidates_dir, do: @candidates_dir
  def concepts_dir, do: @concepts_dir

  @doc """
  Resolve the target path for a concept page by `name` (stem, no `.md`).

  If `kb/wiki/concepts/<name>.md` already exists, the concept is considered
  established — the write goes to `concepts/` to update it in-place.
  Otherwise the write is routed to `candidates/` (a new concept pending
  approval).

  Pass `roots: base_dir` to resolve relative to an alternative KB root
  (used in tests).
  """
  def target_path(name, opts \\ []) do
    root = Keyword.get(opts, :root, ".")
    concepts = Path.join([root, @concepts_dir, "#{name}.md"])
    candidates = Path.join([root, @candidates_dir, "#{name}.md"])

    if File.exists?(concepts) do
      {:existing, concepts}
    else
      {:candidate, candidates}
    end
  end

  @doc """
  Write a new/updated concept page, routing new ones to `candidates/`.

  Returns `{:existing, path}` when the page updated an existing concept,
  or `{:candidate, path}` when the page was routed to `candidates/`.
  """
  def write_concept(name, content, opts \\ []) do
    {kind, path} = target_path(name, opts)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    {kind, path}
  end

  # -- CLI entry points ----------------------------------------------------

  @doc """
  Entry point for `kb approve [<name>] [--all] [--force]`.
  """
  def run(args) do
    {opts, positional} = parse_args(args)

    cond do
      opts[:all] ->
        promote_all(opts)

      positional == [] ->
        IO.puts("Usage: kb approve <name> | --all  [--force]")
        list_candidates()

      true ->
        Enum.each(positional, &promote_one(&1, opts))
    end
  end

  defp parse_args(args) do
    Enum.reduce(args, {[], []}, fn
      "--all", {opts, rest} -> {Keyword.put(opts, :all, true), rest}
      "--force", {opts, rest} -> {Keyword.put(opts, :force, true), rest}
      other, {opts, rest} -> {opts, rest ++ [other]}
    end)
  end

  defp list_candidates do
    case Path.wildcard("#{@candidates_dir}/*.md") do
      [] ->
        IO.puts("No candidates pending approval.")

      files ->
        IO.puts("Candidates pending approval (#{length(files)}):")
        Enum.each(files, fn f -> IO.puts("  - #{Path.basename(f, ".md")}") end)
    end
  end

  @doc """
  Promote a single candidate to a concept.

  Returns `:ok`, `{:error, :missing_candidate}`, or `{:error, :concept_exists}`.
  """
  def promote_one(name, opts \\ []) do
    root = Keyword.get(opts, :root, ".")
    force = Keyword.get(opts, :force, false)
    candidate = Path.join([root, @candidates_dir, "#{name}.md"])
    concept = Path.join([root, @concepts_dir, "#{name}.md"])

    cond do
      not File.exists?(candidate) ->
        IO.puts("No candidate named '#{name}' at #{candidate}")
        {:error, :missing_candidate}

      File.exists?(concept) and not force ->
        IO.puts(
          "Concept '#{name}' already exists at #{concept}. " <>
            "Pass --force to overwrite."
        )

        {:error, :concept_exists}

      true ->
        File.mkdir_p!(Path.dirname(concept))
        # Use rename when possible; fall back to copy + delete across fs.
        case File.rename(candidate, concept) do
          :ok ->
            :ok

          {:error, _} ->
            File.cp!(candidate, concept)
            File.rm!(candidate)
        end

        IO.puts("Approved: #{name} (#{candidate} -> #{concept})")
        :ok
    end
  end

  @doc """
  Bulk-promote every candidate.

  Prints a 1-line summary per promotion. Skips candidates whose concept
  already exists unless `--force` was passed.
  """
  def promote_all(opts \\ []) do
    root = Keyword.get(opts, :root, ".")
    pattern = Path.join([root, @candidates_dir, "*.md"])

    case Path.wildcard(pattern) do
      [] ->
        IO.puts("No candidates to promote.")
        :ok

      files ->
        results =
          Enum.map(files, fn f ->
            name = Path.basename(f, ".md")
            {name, promote_one(name, opts)}
          end)

        ok = Enum.count(results, fn {_, r} -> r == :ok end)
        IO.puts("Promoted #{ok}/#{length(results)} candidates.")
        :ok
    end
  end

  @doc """
  Print a diff (or "NEW") for every candidate against any existing concept.

  Used by `kb build --approve` as the approval staging step.
  """
  def print_diffs(opts \\ []) do
    root = Keyword.get(opts, :root, ".")
    pattern = Path.join([root, @candidates_dir, "*.md"])
    files = Path.wildcard(pattern)

    if files == [] do
      IO.puts("No candidates to review.")
    else
      IO.puts("Candidates staged for approval (#{length(files)}):\n")

      Enum.each(files, fn candidate ->
        name = Path.basename(candidate, ".md")
        concept = Path.join([root, @concepts_dir, "#{name}.md"])

        header = "=== #{name} ==="
        IO.puts(header)

        if File.exists?(concept) do
          IO.puts(diff(File.read!(concept), File.read!(candidate)))
        else
          IO.puts("NEW\n")
          IO.puts(File.read!(candidate))
        end

        IO.puts("")
      end)
    end
  end

  # Minimal line-based diff — no external deps. Marks removed lines with "-"
  # and added lines with "+". Shared prefix/suffix are printed as context.
  defp diff(old, new) do
    old_lines = String.split(old, "\n")
    new_lines = String.split(new, "\n")

    # Strip common prefix
    {common_prefix, old_rest, new_rest} = strip_prefix(old_lines, new_lines, [])

    prefix =
      common_prefix
      |> Enum.reverse()
      |> Enum.map(&"  #{&1}")

    removed = Enum.map(old_rest, &"- #{&1}")
    added = Enum.map(new_rest, &"+ #{&1}")

    (prefix ++ removed ++ added) |> Enum.join("\n")
  end

  defp strip_prefix([h | t1], [h | t2], acc), do: strip_prefix(t1, t2, [h | acc])
  defp strip_prefix(a, b, acc), do: {acc, a, b}
end
