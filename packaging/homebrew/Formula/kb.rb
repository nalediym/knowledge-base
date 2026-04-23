class Kb < Formula
  desc "LLM-compiled knowledge base — CLI + Claude Code skill"
  homepage "https://github.com/nalediym/knowledge-base"
  # Update `url`, `sha256`, and `version` at each release tag.
  # Compute sha256 with:
  #   curl -sL https://github.com/nalediym/knowledge-base/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256
  url "https://github.com/nalediym/knowledge-base/archive/refs/tags/v0.1.0.tar.gz"
  version "0.1.0"
  sha256 "6ac083250ff3e12db96445f881bba89153c26077cf3b92401505a4affcee8d14"
  license "MIT"
  head "https://github.com/nalediym/knowledge-base.git", branch: "main"

  depends_on "elixir"
  depends_on "erlang"

  def install
    cd "cli" do
      # Let mix use a writable cache inside the build dir
      ENV["MIX_HOME"] = buildpath/".mix"
      ENV["HEX_HOME"] = buildpath/".hex"
      ENV["MIX_ENV"] = "prod"

      system "mix", "local.hex",   "--force"
      system "mix", "local.rebar", "--force"
      system "mix", "deps.get"
      system "mix", "escript.build"

      bin.install "kb"
    end

    # Ship the skill markdown alongside the binary so users can symlink it
    # into ~/.claude/skills/ without re-cloning.
    pkgshare.install "SKILL.md"
    pkgshare.install "README.md"
  end

  test do
    assert_match(/kb v/, shell_output("#{bin}/kb version"))
  end
end
