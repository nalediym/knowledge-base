defmodule Kb.LintTest do
  use ExUnit.Case, async: false

  @tmp_root "tmp/lint-test"

  setup do
    original = File.cwd!()
    File.rm_rf!(@tmp_root)
    File.mkdir_p!(Path.join(@tmp_root, "kb/wiki/candidates"))
    File.mkdir_p!(Path.join(@tmp_root, "kb/wiki/concepts"))
    File.mkdir_p!(Path.join(@tmp_root, "kb/wiki/sources"))
    File.mkdir_p!(Path.join(@tmp_root, "kb/raw/media"))

    # Minimal manifest so Kb.Lint.run/0 proceeds past the no_manifest branch.
    manifest = %{
      "version" => 1,
      "created" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "last_compiled" => nil,
      "sources" => [],
      "name" => "lint-test"
    }

    File.write!(
      Path.join(@tmp_root, "kb/.kb-manifest.json"),
      Jason.encode!(manifest)
    )

    File.cd!(@tmp_root)
    on_exit(fn ->
      File.cd!(original)
      File.rm_rf!(@tmp_root)
    end)

    :ok
  end

  test "lint reports PASS when candidates/ is at or under threshold" do
    for i <- 1..20 do
      File.write!("kb/wiki/candidates/c#{i}.md", "# c#{i}\n")
    end

    output = ExUnit.CaptureIO.capture_io(fn -> Kb.Lint.run() end)

    # The candidates row exists and is PASS (exactly-threshold is not overflow).
    assert output =~ ~r/Candidates overflow \| PASS \| 20/
  end

  test "lint warns (WARN) when candidates/ exceeds threshold" do
    for i <- 1..21 do
      File.write!("kb/wiki/candidates/c#{i}.md", "# c#{i}\n")
    end

    output = ExUnit.CaptureIO.capture_io(fn -> Kb.Lint.run() end)

    assert output =~ ~r/Candidates overflow \| WARN \| 21/
  end

  test "lint honors kb.config.json candidates.overflow_threshold" do
    File.write!("kb.config.json", Jason.encode!(%{
      "candidates" => %{"overflow_threshold" => 2}
    }))

    for i <- 1..3 do
      File.write!("kb/wiki/candidates/c#{i}.md", "# c#{i}\n")
    end

    output = ExUnit.CaptureIO.capture_io(fn -> Kb.Lint.run() end)

    assert output =~ ~r/Candidates overflow \| WARN \| 3/
  end
end
