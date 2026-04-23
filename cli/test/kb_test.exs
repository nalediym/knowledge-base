defmodule KbTest do
  use ExUnit.Case
  doctest Kb

  test "Kb.version/0 returns a version string" do
    assert is_binary(Kb.version())
  end
end
