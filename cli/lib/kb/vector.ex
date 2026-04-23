defmodule Kb.Vector do
  @moduledoc """
  Compact float32 blob encoding for embedding vectors.

  Vectors are stored as SQLite BLOBs of little-endian float32 triples so they
  survive round-trips without JSON bloat.
  """

  @doc "Serialize a list of floats to a float32 little-endian binary."
  def to_blob(vec) when is_list(vec) do
    for v <- vec, into: <<>>, do: <<(v * 1.0)::float-little-size(32)>>
  end

  @doc "Deserialize a float32 little-endian binary back to a list of floats."
  def from_blob(bin) when is_binary(bin) do
    for <<v::float-little-size(32) <- bin>>, do: v
  end

  @doc """
  Cosine similarity between two equal-length vectors (lists of floats).

  Returns `0.0` when either vector is a zero vector (avoids NaN).
  """
  def cosine(a, b) when is_list(a) and is_list(b) and length(a) == length(b) do
    {dot, na, nb} =
      Enum.zip(a, b)
      |> Enum.reduce({0.0, 0.0, 0.0}, fn {x, y}, {d, na, nb} ->
        {d + x * y, na + x * x, nb + y * y}
      end)

    denom = :math.sqrt(na) * :math.sqrt(nb)
    if denom == 0.0, do: 0.0, else: dot / denom
  end

  def cosine(_, _), do: 0.0
end
