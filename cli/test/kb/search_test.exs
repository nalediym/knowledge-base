defmodule Kb.SearchTest do
  use ExUnit.Case, async: true

  alias Kb.Search

  describe "rrf_merge/3" do
    test "both lists contribute to the fused score" do
      fts = [
        %{path: "a.md", chunk_id: "c1", title: "A", score: 1.0, source: :fts},
        %{path: "b.md", chunk_id: "c1", title: "B", score: 0.5, source: :fts}
      ]

      sem = [
        %{path: "b.md", chunk_id: "c1", title: "B", score: 0.9, source: :semantic},
        %{path: "a.md", chunk_id: "c1", title: "A", score: 0.8, source: :semantic}
      ]

      merged = Search.rrf_merge(fts, sem, k: 60, top_n: 10)

      assert length(merged) == 2
      top = hd(merged)
      assert Enum.all?(merged, &(&1.components.fts > 0 and &1.components.semantic > 0))
      assert top.score > 0
    end

    test "an entry only appearing in the semantic list still ranks" do
      fts = [
        %{path: "only-fts.md", chunk_id: "c1", title: "F", score: 1.0, source: :fts}
      ]

      sem = [
        %{path: "only-sem.md", chunk_id: "c1", title: "S", score: 0.9, source: :semantic}
      ]

      merged = Search.rrf_merge(fts, sem, k: 60, top_n: 10)
      paths = Enum.map(merged, & &1.path) |> Enum.sort()
      assert paths == ["only-fts.md", "only-sem.md"]
    end

    test "a planted fixture — one doc wins FTS, another wins semantic, both surface" do
      # FTS winner ranks #1 in fts, not in semantic
      # Semantic winner ranks #1 in semantic, not in fts
      # Each source also contains noise-only docs further down its ranking.
      fts = [
        %{path: "fts-winner.md", chunk_id: "c1", title: "Fw", score: 5.0, source: :fts},
        %{path: "noise-fts.md", chunk_id: "c1", title: "Nf", score: 2.0, source: :fts}
      ]

      sem = [
        %{path: "sem-winner.md", chunk_id: "c1", title: "Sw", score: 0.95, source: :semantic},
        %{path: "noise-sem.md", chunk_id: "c1", title: "Ns", score: 0.2, source: :semantic}
      ]

      merged = Search.rrf_merge(fts, sem, k: 60, top_n: 4)
      top_two = merged |> Enum.take(2) |> Enum.map(& &1.path) |> MapSet.new()

      # Both winners sit at rank 1 in their list so they share the top slot
      # (tied at 1/(60+1)) — and RRF surfaces both above docs that only appear once at rank 2.
      assert MapSet.member?(top_two, "fts-winner.md")
      assert MapSet.member?(top_two, "sem-winner.md")
    end
  end
end
