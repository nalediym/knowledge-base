defmodule Kb.LifecycleCLI do
  @moduledoc """
  Command handlers for `kb review`, `kb verify`, `kb archive`.

  Each command loads a wiki page, applies the lifecycle transition, and
  writes the result back. Illegal transitions surface a clear error and
  exit non-zero.
  """

  alias Kb.Lifecycle

  @doc "Run a lifecycle command. `action` in :review | :verify | :archive."
  def run(action, page_path) when action in [:review, :verify, :archive] do
    with {:ok, content} <- read_page(page_path),
         {:ok, new_content, new_state} <- Lifecycle.apply_command(content, action) do
      File.write!(page_path, new_content)
      IO.puts("#{action} #{page_path} — lifecycle: #{new_state}")
      :ok
    else
      {:error, :enoent} ->
        IO.puts("Error: page not found: #{page_path}")
        System.halt(1)

      {:error, msg} ->
        IO.puts("Error: #{msg}")
        System.halt(1)
    end
  end

  defp read_page(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end
end
