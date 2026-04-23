defmodule Kb.IndexTest do
  use ExUnit.Case, async: true

  alias Kb.{Index, Search}

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "kb-index-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(root, "kb/wiki/sources"))
    File.mkdir_p!(Path.join(root, "kb/wiki/concepts"))
    File.mkdir_p!(Path.join(root, "kb/raw"))

    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, root: root, index_path: Path.join(root, "kb/.index/search.sqlite")}
  end

  describe "FTS index" do
    test "indexes wiki pages and returns FTS hits on a fixture", %{
      root: root,
      index_path: index_path
    } do
      File.write!(Path.join(root, "kb/wiki/sources/apples.md"), """
      # Apples

      ## Overview

      Apples are crunchy fruits grown on trees. They store well in cellars.
      """)

      File.write!(Path.join(root, "kb/wiki/sources/cars.md"), """
      # Cars

      ## Overview

      Cars are vehicles with engines and wheels.
      """)

      assert {:ok, stats} = Index.build(root: root, index_path: index_path)
      assert stats.files == 2
      assert stats.reindexed == 2
      assert stats.chunks >= 2

      {:ok, conn} = Index.open(index_path)

      try do
        hits = Search.fts(conn, "crunchy fruits", top_k: 5)
        assert Enum.any?(hits, &String.contains?(&1.path, "apples.md"))
        refute Enum.any?(hits, &String.contains?(&1.path, "cars.md"))
      after
        Index.close(conn)
      end
    end

    test "skips raw/ unless --include-raw", %{root: root, index_path: index_path} do
      File.write!(Path.join(root, "kb/wiki/sources/alpha.md"), "# Alpha\n\nalpha content\n")
      File.write!(Path.join(root, "kb/raw/beta.md"), "# Beta\n\nbeta content\n")

      {:ok, s1} = Index.build(root: root, index_path: index_path)
      assert s1.files == 1

      File.rm!(index_path)
      {:ok, s2} = Index.build(root: root, index_path: index_path, include_raw: true)
      assert s2.files == 2
    end
  end

  describe "incremental reindex (mtime-based)" do
    test "only reindexes changed files on second run", %{root: root, index_path: index_path} do
      a = Path.join(root, "kb/wiki/sources/a.md")
      b = Path.join(root, "kb/wiki/sources/b.md")
      File.write!(a, "# A\n\nalpha\n")
      File.write!(b, "# B\n\nbeta\n")

      {:ok, first} = Index.build(root: root, index_path: index_path)
      assert first.reindexed == 2

      # Advance mtime for only one file.
      now = System.os_time(:second) + 2
      File.touch!(b, now)

      {:ok, second} = Index.build(root: root, index_path: index_path)
      assert second.files == 2
      assert second.reindexed == 1
    end

    test "prunes deleted files from the index", %{root: root, index_path: index_path} do
      a = Path.join(root, "kb/wiki/sources/keeps.md")
      g = Path.join(root, "kb/wiki/sources/goes.md")
      File.write!(a, "# Keeps\n\ncontent alpha\n")
      File.write!(g, "# Goes\n\ncontent gamma\n")

      {:ok, _} = Index.build(root: root, index_path: index_path)
      File.rm!(g)
      {:ok, _} = Index.build(root: root, index_path: index_path)

      {:ok, conn} = Index.open(index_path)

      try do
        assert [] == Search.fts(conn, "gamma", top_k: 10)
        assert [_ | _] = Search.fts(conn, "alpha", top_k: 10)
      after
        Index.close(conn)
      end
    end
  end
end
