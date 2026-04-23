defmodule Kb.Vault do
  @moduledoc """
  Obsidian vault auto-detection.

  Walks up from a starting path looking for a `.obsidian/` directory.
  Stops at the filesystem root or `$HOME`. Returns `{:ok, path}` or `:not_found`.
  """

  @doc """
  Walk upward from `start` searching for `.obsidian/`.

  Traversal stops at the filesystem root or `$HOME` (if HOME is set and is
  an ancestor of `start`). Symlinks are resolved via `Path.expand/1`.

  Returns `{:ok, absolute_path}` when a vault is found, `:not_found` otherwise.
  """
  def find_vault_root(start \\ File.cwd!()) do
    start
    |> Path.expand()
    |> walk_up(home_boundary())
  end

  defp walk_up(dir, home_boundary) do
    cond do
      vault?(dir) ->
        {:ok, dir}

      at_root?(dir) ->
        :not_found

      # Stop when we pass above $HOME — vaults rarely live above HOME and
      # searching further risks scanning e.g. /Users/.
      home_boundary != nil and dir == home_boundary ->
        if vault?(dir), do: {:ok, dir}, else: :not_found

      true ->
        parent = Path.dirname(dir)

        if parent == dir do
          :not_found
        else
          walk_up(parent, home_boundary)
        end
    end
  end

  defp vault?(dir), do: File.dir?(Path.join(dir, ".obsidian"))

  defp at_root?(dir), do: Path.dirname(dir) == dir

  defp home_boundary do
    case System.get_env("HOME") do
      nil -> nil
      "" -> nil
      home -> Path.expand(home) |> Path.dirname()
    end
  end
end
