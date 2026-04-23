defmodule KbTest do
  use ExUnit.Case

  test "version is a string" do
    assert is_binary(Kb.version())
  end
end
