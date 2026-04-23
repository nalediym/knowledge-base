defmodule KB.Sessions.Adapters.CodexCliTest do
  use ExUnit.Case, async: true

  alias KB.Sessions.Adapters.CodexCli
  alias KB.Sessions.{Renderer, SessionDoc}

  @fixture Path.expand("fixtures/codex_cli_session.jsonl", __DIR__)

  test "parses codex_cli jsonl fixture, extracts cwd/model/session_id" do
    {:ok, %SessionDoc{} = doc} = CodexCli.parse(@fixture)

    assert doc.agent == "codex_cli"
    assert doc.session_id == "cdx-9876"
    assert doc.project == "codex-demo"
    assert doc.model == "gpt-5-codex"
    # 1 user + 1 assistant + 1 web_search_call tool-use-as-assistant = 3
    assert length(doc.messages) == 3
    roles = Enum.map(doc.messages, & &1.role)
    assert roles == ["user", "assistant", "assistant"]
  end

  test "redact strips sk-* and emails" do
    {:ok, doc} = CodexCli.parse(@fixture)
    redacted = CodexCli.redact(doc)

    all = redacted.messages |> Enum.map(& &1.content) |> Enum.join("\n")
    refute all =~ ~r/sk-[A-Za-z0-9]{20,}/
    refute all =~ ~r/@example\.org/
    assert all =~ "[REDACTED_API_KEY]"
    assert all =~ "[REDACTED_EMAIL]"
  end

  test "renders with agent=codex_cli frontmatter" do
    {:ok, doc} = CodexCli.parse(@fixture)
    out = Renderer.render(CodexCli.redact(doc))

    assert out =~ "agent: \"codex_cli\""
    assert out =~ "project: \"codex-demo\""
    assert out =~ ~r/\[tool: WebSearch\]/
  end
end
