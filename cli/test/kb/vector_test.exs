defmodule Kb.VectorTest do
  use ExUnit.Case, async: true

  alias Kb.Vector

  test "round-trip blob encoding" do
    vec = [0.1, -0.25, 1.5, 0.0, 3.0]
    blob = Vector.to_blob(vec)
    decoded = Vector.from_blob(blob)

    Enum.zip(vec, decoded)
    |> Enum.each(fn {a, b} ->
      assert_in_delta a, b, 1.0e-6
    end)
  end

  test "cosine similarity is 1.0 for identical vectors" do
    vec = [1.0, 2.0, 3.0]
    assert_in_delta Vector.cosine(vec, vec), 1.0, 1.0e-6
  end

  test "cosine similarity is 0.0 for orthogonal vectors" do
    assert_in_delta Vector.cosine([1.0, 0.0], [0.0, 1.0]), 0.0, 1.0e-6
  end

  test "cosine similarity handles zero vector without NaN" do
    assert Vector.cosine([0.0, 0.0], [1.0, 1.0]) == 0.0
  end
end
