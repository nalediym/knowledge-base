defmodule KB.Sessions.StubsTest do
  use ExUnit.Case, async: true

  alias KB.Sessions.Adapters.{Copilot, Cursor, GeminiCli}

  test "copilot is always :not_installed in v1" do
    assert Copilot.detect() == :not_installed
    assert Copilot.parse("/nonexistent") == {:error, :not_implemented}
    assert Copilot.agent_name() == "copilot"
  end

  test "cursor detect returns :not_installed when store missing" do
    result = Cursor.detect()
    assert result == :not_installed or match?({:ok, _}, result)
    assert Cursor.parse("/nonexistent") == {:error, :not_implemented}
  end

  test "gemini detect returns :not_installed when store missing" do
    result = GeminiCli.detect()
    assert result == :not_installed or match?({:ok, _}, result)
    assert GeminiCli.parse("/nonexistent") == {:error, :not_implemented}
  end
end
