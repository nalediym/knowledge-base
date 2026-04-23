defmodule KbTest do
  use ExUnit.Case
  doctest Kb

  test "version is a string" do
    assert is_binary(Kb.version())
  end
end
