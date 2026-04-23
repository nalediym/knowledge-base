defmodule KbTest do
  use ExUnit.Case

  test "version/0 returns a string" do
    assert is_binary(Kb.version())
  end
end
