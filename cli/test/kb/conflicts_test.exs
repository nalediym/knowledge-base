defmodule Kb.ConflictsTest do
  use ExUnit.Case

  alias Kb.Conflicts

  @moduletag :tmp_dir

  describe "lifecycle/1" do
    test "picks up YAML frontmatter" do
      draft = """
      ---
      lifecycle: draft
      ---
      # Page
      """

      reviewed = """
      ---
      lifecycle: reviewed
      ---
      # Page
      """

      verified = """
      ---
      lifecycle: verified
      ---
      # Page
      """

      assert Conflicts.lifecycle(draft) == :draft
      assert Conflicts.lifecycle(reviewed) == :reviewed
      assert Conflicts.lifecycle(verified) == :verified
    end

    test "returns :none when no frontmatter" do
      assert Conflicts.lifecycle("# Page\n\nBody") == :none
    end
  end

  describe "scan_page?/1" do
    test "rejects drafts and accepts everything else", %{tmp_dir: tmp} do
      draft = Path.join(tmp, "d.md")
      reviewed = Path.join(tmp, "r.md")
      plain = Path.join(tmp, "p.md")

      File.write!(draft, "---\nlifecycle: draft\n---\n# x")
      File.write!(reviewed, "---\nlifecycle: reviewed\n---\n# x")
      File.write!(plain, "# x")

      refute Conflicts.scan_page?(draft)
      assert Conflicts.scan_page?(reviewed)
      assert Conflicts.scan_page?(plain)
    end
  end

  describe "extract_claims/1" do
    test "parses a Key Claims section into claim structs", %{tmp_dir: tmp} do
      path = Path.join(tmp, "src.md")

      File.write!(path, """
      # Source
      ## Key Claims
      - JWT tokens expire after 24 hours — c-1ee0207b
      - Refresh tokens are one-time use — c-fcba1172

      ## Other
      unrelated
      """)

      claims = Conflicts.extract_claims(path)
      assert length(claims) == 2
      assert Enum.at(claims, 0).chunk_id == "c-1ee0207b"
      assert Enum.at(claims, 0).source == "src"
      assert Enum.at(claims, 0).text =~ "JWT"
    end
  end

  describe "run/1 with heuristic provider" do
    test "planted contradiction across sources lands in report", %{tmp_dir: tmp} do
      kb_dir = setup_kb_with_contradiction(tmp)

      {:ok, %{findings: findings, report_path: path}} =
        Conflicts.run(kb_dir: kb_dir, provider: "heuristic", date: ~D[2026-04-23])

      assert length(findings) >= 1
      assert File.exists?(path)

      body = File.read!(path)
      assert body =~ "Contradictions — 2026-04-23"
      assert body =~ "concept: attention.md"
      assert body =~ "c-aaaaaaaa"
      assert body =~ "c-bbbbbbbb"
      assert body =~ "Claim A"
      assert body =~ "Claim B"
    end

    test "agreeing sources produce no false positive", %{tmp_dir: tmp} do
      kb_dir = setup_kb_with_agreement(tmp)

      {:ok, %{findings: findings, report_path: path}} =
        Conflicts.run(kb_dir: kb_dir, provider: "heuristic", date: ~D[2026-04-23])

      assert findings == []
      assert File.exists?(path)
      body = File.read!(path)
      assert body =~ "No contradictions"
    end

    test "skips draft concept pages", %{tmp_dir: tmp} do
      kb_dir = setup_kb_with_contradiction(tmp)

      # Flip concept to draft
      concept = Path.join([kb_dir, "wiki", "concepts", "attention.md"])
      original = File.read!(concept)
      File.write!(concept, "---\nlifecycle: draft\n---\n" <> original)

      {:ok, %{findings: findings}} =
        Conflicts.run(kb_dir: kb_dir, provider: "heuristic", date: ~D[2026-04-23])

      assert findings == []
    end
  end

  defp setup_kb_with_contradiction(tmp) do
    kb_dir = Path.join(tmp, "kb")
    concepts = Path.join([kb_dir, "wiki", "concepts"])
    sources = Path.join([kb_dir, "wiki", "sources"])
    File.mkdir_p!(concepts)
    File.mkdir_p!(sources)

    File.write!(Path.join(concepts, "attention.md"), """
    # Attention

    > Related sources

    ## Details
    See [vaswani](../sources/vaswani.md) and [flash](../sources/flash.md).

    ## Provenance
    - [vaswani.md](../sources/vaswani.md) — c-aaaaaaaa
    - [flash.md](../sources/flash.md) — c-bbbbbbbb
    """)

    File.write!(Path.join(sources, "vaswani.md"), """
    # Vaswani 2017

    ## Key Claims
    - Attention complexity is quadratic with dense patterns — c-aaaaaaaa
    """)

    File.write!(Path.join(sources, "flash.md"), """
    # FlashAttention

    ## Key Claims
    - Attention complexity is linear with sparse patterns — c-bbbbbbbb
    """)

    kb_dir
  end

  defp setup_kb_with_agreement(tmp) do
    kb_dir = Path.join(tmp, "kb")
    concepts = Path.join([kb_dir, "wiki", "concepts"])
    sources = Path.join([kb_dir, "wiki", "sources"])
    File.mkdir_p!(concepts)
    File.mkdir_p!(sources)

    File.write!(Path.join(concepts, "jwt.md"), """
    # JWT

    ## Details
    See [a](../sources/a.md) and [b](../sources/b.md).
    """)

    File.write!(Path.join(sources, "a.md"), """
    # A

    ## Key Claims
    - JWT tokens expire after 24 hours — c-11111111
    """)

    File.write!(Path.join(sources, "b.md"), """
    # B

    ## Key Claims
    - JWT tokens are valid for 24 hours — c-22222222
    """)

    kb_dir
  end
end
