class Kb < Formula
  desc "LLM-compiled knowledge base — CLI + Claude Code skill (Bun/TS)"
  homepage "https://github.com/nalediym/knowledge-base"
  # Update `url`, `sha256`, and `version` at each release tag.
  # Compute sha256 with:
  #   curl -sL https://github.com/nalediym/knowledge-base/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256
  url "https://github.com/nalediym/knowledge-base/archive/refs/tags/v0.3.0.tar.gz"
  version "0.3.0"
  sha256 "b797fd760a0f065621d0607b2897c4c542fd8e0d0e6b274b29b212dffd6fdf03"
  license "MIT"
  head "https://github.com/nalediym/knowledge-base.git", branch: "main"

  depends_on "bun"

  def install
    # Install workspace deps and ship the whole tree under libexec so the
    # symlinked package paths inside packages/* resolve at runtime.
    system "bun", "install", "--frozen-lockfile"
    libexec.install Dir["*"]

    # Launcher that defers to bun + the workspace entry point.
    (bin/"kb").write <<~SH
      #!/usr/bin/env bash
      exec bun "#{libexec}/packages/cli/src/bin.ts" "$@"
    SH
    (bin/"kb").chmod 0755

    # Ship the skill markdown alongside the binary so users can symlink it
    # into ~/.claude/skills/ without re-cloning.
    pkgshare.install libexec/"SKILL.md" if (libexec/"SKILL.md").exist?
    pkgshare.install libexec/"README.md" if (libexec/"README.md").exist?
  end

  test do
    assert_match(/kb v/, shell_output("#{bin}/kb version"))
  end
end
