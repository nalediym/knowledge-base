defmodule KbTest do
  use ExUnit.Case
  doctest Kb

  test "version returns a string" do
    assert is_binary(Kb.version())
  end
end
