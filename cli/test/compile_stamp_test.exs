defmodule Kb.CompileStampTest do
  use ExUnit.Case

  setup do
    dir = Path.join(System.tmp_dir!(), "kb-stamp-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "kb/wiki/concepts"))
    File.mkdir_p!(Path.join(dir, "kb/wiki/sources"))

    original = File.cwd!()
    File.cd!(dir)
    on_exit(fn -> File.cd!(original); File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "stamps numeric confidence and shims legacy strings" do
    legacy = """
    ---
    title: Test Concept
    confidence: high
    ---

    # Test
    Some body.
    """

    fresh = """
    # Fresh Concept

    Body with [[some-link]] inline.
    """

    File.write!("kb/wiki/concepts/legacy.md", legacy)
    File.write!("kb/wiki/concepts/fresh.md", fresh)

    manifest = %{
      "sources" => [
        %{"slug" => "a", "ingested" => DateTime.utc_now() |> DateTime.to_iso8601()}
      ]
    }

    count = Kb.Compile.stamp_confidence_pages(manifest)
    assert count == 2

    legacy_out = File.read!("kb/wiki/concepts/legacy.md")
    assert legacy_out =~ "confidence: 0.85"

    fresh_out = File.read!("kb/wiki/concepts/fresh.md")
    assert Regex.match?(~r/confidence: 0\.\d\d/, fresh_out)
  end
end
