defmodule KB.Sessions.Adapters.ClaudeCodeTest do
  use ExUnit.Case, async: true

  alias KB.Sessions.Adapters.ClaudeCode
  alias KB.Sessions.{Renderer, SessionDoc}

  @fixture Path.expand("fixtures/claude_code_session.jsonl", __DIR__)

  test "parses a claude_code jsonl fixture into a SessionDoc" do
    {:ok, %SessionDoc{} = doc} = ClaudeCode.parse(@fixture)

    assert doc.agent == "claude_code"
    assert doc.session_id == "abc12345-0000-0000-0000-000000000000"
    assert doc.project == "demo"
    assert doc.model == "claude-opus-4-7"
    # 2 user + 1 assistant = 3 non-empty messages
    assert length(doc.messages) == 3
    roles = Enum.map(doc.messages, & &1.role)
    assert roles == ["user", "assistant", "user"]
  end

  test "redact strips sk-*, ghp_*, and emails from parsed messages" do
    {:ok, doc} = ClaudeCode.parse(@fixture)
    redacted = ClaudeCode.redact(doc)

    all_content = redacted.messages |> Enum.map(& &1.content) |> Enum.join("\n")

    refute all_content =~ ~r/sk-[A-Za-z0-9]{20,}/
    refute all_content =~ ~r/ghp_[A-Za-z0-9]{36}/
    refute all_content =~ ~r/@example\.com/
    assert all_content =~ "[REDACTED_API_KEY]"
    assert all_content =~ "[REDACTED_GH_TOKEN]"
    assert all_content =~ "[REDACTED_EMAIL]"
  end

  test "render writes frontmatter with session source_type" do
    {:ok, doc} = ClaudeCode.parse(@fixture)
    out = Renderer.render(ClaudeCode.redact(doc))

    assert out =~ ~r/^---\n/
    assert out =~ "source_type: \"session\""
    assert out =~ "agent: \"claude_code\""
    assert out =~ "project: \"demo\""
    # Redacted content should also be present in the rendered output.
    refute out =~ ~r/sk-[A-Za-z0-9]{20,}/
  end

  test "output_path lives under kb/raw/sessions/<project>/YYYY-MM-DD-<slug>.md" do
    {:ok, doc} = ClaudeCode.parse(@fixture)
    path = Renderer.output_path("kb/raw/sessions", doc)

    assert path =~ ~r|kb/raw/sessions/demo/2026-04-20-[a-z0-9]+\.md$|
  end
end
