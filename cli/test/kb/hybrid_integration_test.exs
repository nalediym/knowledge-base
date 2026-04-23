defmodule Kb.HybridIntegrationTest do
  @moduledoc """
  End-to-end: build FTS index, hand-plant an embeddings row, confirm RRF merges.

  We don't depend on Ollama being running — instead we write a synthetic query
  vector + chunk vector directly into the embeddings table so the pipeline is
  deterministic.
  """
  use ExUnit.Case, async: true

  alias Exqlite.Sqlite3
  alias Kb.{Index, Search, Vector}

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "kb-hybrid-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(root, "kb/wiki/sources"))
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, root: root, index_path: Path.join(root, "kb/.index/search.sqlite")}
  end

  test "hybrid surfaces both an FTS-only winner and a semantic-only winner", %{
    root: root,
    index_path: index_path
  } do
    # Doc A: contains the literal keyword 'quokka' — will win FTS.
    File.write!(Path.join(root, "kb/wiki/sources/quokka.md"), """
    # Quokka Notes

    ## Overview

    The quokka is a small macropod native to western Australia.
    """)

    # Doc B: semantically related (marsupial) but lacks the keyword.
    File.write!(Path.join(root, "kb/wiki/sources/marsupial.md"), """
    # Marsupial Reference

    ## Overview

    Kangaroos and wallabies belong to the same family of pouched mammals.
    """)

    assert {:ok, _} = Index.build(root: root, index_path: index_path)

    {:ok, conn} = Index.open(index_path)

    try do
      # Plant embeddings: query vector aligns with marsupial.md's chunk.
      {:ok, stmt} = Sqlite3.prepare(conn, "SELECT path, chunk_id FROM pages")
      rows = Index.fetch_all(conn, stmt)
      Sqlite3.release(conn, stmt)

      marsupial_row =
        Enum.find(rows, fn [p, _] -> String.contains?(p, "marsupial.md") end)

      quokka_row =
        Enum.find(rows, fn [p, _] -> String.contains?(p, "quokka.md") end)

      assert marsupial_row && quokka_row

      [mp, mc] = marsupial_row
      [qp, qc] = quokka_row

      # Marsupial aligns with the "query" vector [1, 0]; quokka is orthogonal.
      insert_embedding(conn, mp, mc, [1.0, 0.0])
      insert_embedding(conn, qp, qc, [0.0, 1.0])

      # FTS-only for "quokka" — quokka wins.
      fts_hits = Search.fts(conn, "quokka", top_k: 5)
      assert [top | _] = fts_hits
      assert String.contains?(top.path, "quokka.md")

      # Build a fake semantic result by computing cosine against the planted vectors.
      qvec = [1.0, 0.0]

      {:ok, estmt} = Sqlite3.prepare(conn, "SELECT path, chunk_id, vector FROM embeddings")
      emb_rows = Index.fetch_all(conn, estmt)
      Sqlite3.release(conn, estmt)

      sem_hits =
        emb_rows
        |> Enum.map(fn [path, cid, blob] ->
          vec = Vector.from_blob(blob)

          %{
            path: path,
            chunk_id: cid,
            title: Path.basename(path, ".md"),
            score: Vector.cosine(qvec, vec),
            source: :semantic
          }
        end)
        |> Enum.sort_by(& &1.score, :desc)

      [sem_top | _] = sem_hits
      assert String.contains?(sem_top.path, "marsupial.md")

      merged = Search.rrf_merge(fts_hits, sem_hits, k: 60, top_n: 5)
      top_paths = Enum.map(merged, & &1.path)

      assert Enum.any?(top_paths, &String.contains?(&1, "quokka.md"))
      assert Enum.any?(top_paths, &String.contains?(&1, "marsupial.md"))
    after
      Index.close(conn)
    end
  end

  defp insert_embedding(conn, path, chunk_id, vec) do
    {:ok, stmt} =
      Sqlite3.prepare(
        conn,
        "INSERT OR REPLACE INTO embeddings(path, chunk_id, model, dim, vector) VALUES (?1, ?2, ?3, ?4, ?5)"
      )

    blob = Vector.to_blob(vec)
    :ok = Sqlite3.bind(stmt, [path, chunk_id, "test-model", length(vec), blob])
    :done = Sqlite3.step(conn, stmt)
    Sqlite3.release(conn, stmt)
  end
end
