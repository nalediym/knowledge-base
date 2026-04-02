defmodule Kb.Chunk do
  @moduledoc """
  Content-addressed chunking.

  Splits source files into logical chunks and assigns each a stable ID
  based on the sha256 of its content (first 8 hex chars).
  """

  @type t :: %__MODULE__{
          id: String.t(),
          heading: String.t(),
          content: String.t(),
          line_start: non_neg_integer()
        }

  defstruct [:id, :heading, :content, :line_start]

  @doc """
  Chunk a markdown string by headings.
  Returns a list of %Kb.Chunk{} with content-addressed IDs.
  """
  def chunk_by_heading(content) do
    content
    |> String.split(~r/^(?=## )/m)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.with_index()
    |> Enum.map(fn {section, _idx} ->
      heading = extract_heading(section)
      trimmed = String.trim(section)
      hash = content_hash(trimmed)

      %__MODULE__{
        id: "c-#{hash}",
        heading: heading,
        content: trimmed,
        line_start: 0
      }
    end)
  end

  @doc """
  Compute content-addressed ID: first 8 hex chars of sha256.
  """
  def content_hash(text) do
    :crypto.hash(:sha256, text)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end

  defp extract_heading(section) do
    case Regex.run(~r/^#+\s+(.+)$/m, section) do
      [_, heading] -> String.trim(heading)
      nil -> String.slice(String.trim(section), 0, 60)
    end
  end
end
