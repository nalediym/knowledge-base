defmodule Kb.ApproveTest do
  use ExUnit.Case, async: false

  @tmp_root "tmp/approve-test"

  setup do
    File.rm_rf!(@tmp_root)
    File.mkdir_p!(Path.join(@tmp_root, "kb/wiki/candidates"))
    File.mkdir_p!(Path.join(@tmp_root, "kb/wiki/concepts"))
    on_exit(fn -> File.rm_rf!(@tmp_root) end)
    {:ok, root: @tmp_root}
  end

  describe "target_path/2 (compile routes new concepts to candidates/)" do
    test "routes a new concept to candidates/", %{root: root} do
      assert {:candidate, path} = Kb.Approve.target_path("alpha", root: root)
      assert String.ends_with?(path, "kb/wiki/candidates/alpha.md")
    end

    test "routes an existing concept to concepts/ (update in-place)", %{root: root} do
      existing = Path.join([root, "kb/wiki/concepts/beta.md"])
      File.write!(existing, "# beta\n\noriginal body\n")

      assert {:existing, path} = Kb.Approve.target_path("beta", root: root)
      assert path == existing
    end
  end

  describe "write_concept/3 (compile step)" do
    test "new concept lands in candidates/, not concepts/", %{root: root} do
      {:candidate, path} =
        Kb.Approve.write_concept("gamma", "# gamma\n\nbody\n", root: root)

      assert File.exists?(path)
      assert String.contains?(path, "/candidates/")
      refute File.exists?(Path.join([root, "kb/wiki/concepts/gamma.md"]))
    end

    test "existing concept is updated in-place in concepts/", %{root: root} do
      existing = Path.join([root, "kb/wiki/concepts/delta.md"])
      File.write!(existing, "# delta\n\nv1\n")

      {:existing, path} =
        Kb.Approve.write_concept("delta", "# delta\n\nv2\n", root: root)

      assert path == existing
      assert File.read!(existing) == "# delta\n\nv2\n"
      refute File.exists?(Path.join([root, "kb/wiki/candidates/delta.md"]))
    end
  end

  describe "promote_one/2 (kb approve <name>)" do
    test "moves candidate -> concept", %{root: root} do
      candidate = Path.join([root, "kb/wiki/candidates/zeta.md"])
      concept = Path.join([root, "kb/wiki/concepts/zeta.md"])
      File.write!(candidate, "# zeta\n")

      assert :ok = Kb.Approve.promote_one("zeta", root: root)
      refute File.exists?(candidate)
      assert File.exists?(concept)
      assert File.read!(concept) == "# zeta\n"
    end

    test "refuses when concept already exists (no --force)", %{root: root} do
      candidate = Path.join([root, "kb/wiki/candidates/eta.md"])
      concept = Path.join([root, "kb/wiki/concepts/eta.md"])
      File.write!(candidate, "new\n")
      File.write!(concept, "old\n")

      assert {:error, :concept_exists} = Kb.Approve.promote_one("eta", root: root)
      assert File.exists?(candidate)
      assert File.read!(concept) == "old\n"
    end

    test "overwrites with --force", %{root: root} do
      candidate = Path.join([root, "kb/wiki/candidates/theta.md"])
      concept = Path.join([root, "kb/wiki/concepts/theta.md"])
      File.write!(candidate, "new\n")
      File.write!(concept, "old\n")

      assert :ok = Kb.Approve.promote_one("theta", root: root, force: true)
      refute File.exists?(candidate)
      assert File.read!(concept) == "new\n"
    end

    test "errors when candidate missing", %{root: root} do
      assert {:error, :missing_candidate} =
               Kb.Approve.promote_one("nope", root: root)
    end
  end

  describe "promote_all/1 (kb approve --all)" do
    test "bulk promotes all candidates", %{root: root} do
      for name <- ["a", "b", "c"] do
        File.write!(Path.join([root, "kb/wiki/candidates/#{name}.md"]), "# #{name}\n")
      end

      assert :ok = Kb.Approve.promote_all(root: root)

      for name <- ["a", "b", "c"] do
        assert File.exists?(Path.join([root, "kb/wiki/concepts/#{name}.md"]))
        refute File.exists?(Path.join([root, "kb/wiki/candidates/#{name}.md"]))
      end
    end

    test "skips candidates whose concept already exists (no --force)", %{root: root} do
      File.write!(Path.join([root, "kb/wiki/candidates/keep.md"]), "new\n")
      File.write!(Path.join([root, "kb/wiki/concepts/keep.md"]), "old\n")
      File.write!(Path.join([root, "kb/wiki/candidates/fresh.md"]), "fresh\n")

      assert :ok = Kb.Approve.promote_all(root: root)

      # Skipped candidate stays put.
      assert File.exists?(Path.join([root, "kb/wiki/candidates/keep.md"]))
      assert File.read!(Path.join([root, "kb/wiki/concepts/keep.md"])) == "old\n"
      # Fresh candidate is promoted.
      refute File.exists?(Path.join([root, "kb/wiki/candidates/fresh.md"]))
      assert File.exists?(Path.join([root, "kb/wiki/concepts/fresh.md"]))
    end
  end

  describe "print_diffs/1 (kb build --approve)" do
    test "prints NEW for candidates with no existing concept", %{root: root} do
      File.write!(Path.join([root, "kb/wiki/candidates/new-one.md"]), "# new-one\n")

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Kb.Approve.print_diffs(root: root)
        end)

      assert output =~ "new-one"
      assert output =~ "NEW"
    end

    test "prints a diff when candidate differs from existing concept", %{root: root} do
      File.write!(Path.join([root, "kb/wiki/concepts/iota.md"]), "alpha\nbeta\n")
      File.write!(Path.join([root, "kb/wiki/candidates/iota.md"]), "alpha\ngamma\n")

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Kb.Approve.print_diffs(root: root)
        end)

      assert output =~ "iota"
      # Shared prefix shown as context, differing lines shown with +/-.
      assert output =~ "- beta"
      assert output =~ "+ gamma"
    end
  end
end
