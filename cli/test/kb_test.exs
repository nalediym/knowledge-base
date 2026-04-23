defmodule KbTest do
  use ExUnit.Case
  doctest Kb

  test "exposes a version string" do
    assert is_binary(Kb.version())
  end
end
