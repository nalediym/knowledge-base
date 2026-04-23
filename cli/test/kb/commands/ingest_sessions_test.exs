defmodule KB.Commands.IngestSessionsTest do
  use ExUnit.Case, async: false

  alias KB.Commands.IngestSessions
  alias KB.Sessions.Adapters.ClaudeCode

  @fixture Path.expand("../sessions/fixtures/claude_code_session.jsonl", __DIR__)

  setup do
    tmp =
      Path.join(System.tmp_dir!(), "kb-session-ingest-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    %{tmp: tmp}
  end

  test "end-to-end: parse + redact + render fixture to disk", %{tmp: tmp} do
    {:ok, doc} = ClaudeCode.parse(@fixture)
    redacted = ClaudeCode.redact(doc)
    path = KB.Sessions.Renderer.output_path(tmp, redacted)

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, KB.Sessions.Renderer.render(redacted))

    content = File.read!(path)

    # Acceptance: no sk-* in output
    refute content =~ ~r/sk-[A-Za-z0-9]{20,}/
    # Acceptance: no raw emails
    refute content =~ ~r/@example\.com/
    # Acceptance: frontmatter present
    assert content =~ "source_type: \"session\""
    assert content =~ "agent: \"claude_code\""
    # Path shape
    assert path =~ ~r|/demo/2026-04-20-[a-z0-9]+\.md$|
  end

  test "filter_adapters via IngestSessions.run(dry_run: true) with unknown agent logs nothing" do
    # Unknown agent name produces empty adapter list — no crash, no entries.
    assert {:ok, []} = IngestSessions.run(agent: "nonesuch", dry_run: true)
  end
end
