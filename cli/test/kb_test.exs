defmodule KbTest do
  use ExUnit.Case
  doctest Kb

  test "Kb.version/0 returns a string" do
    assert is_binary(Kb.version())
  end
end
