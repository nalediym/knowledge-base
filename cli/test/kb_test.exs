defmodule KbTest do
  use ExUnit.Case
  doctest Kb

  test "version/0 returns a semver-like string" do
    assert Kb.version() =~ ~r/^\d+\.\d+\.\d+/
  end
end
