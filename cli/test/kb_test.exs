defmodule KbTest do
  use ExUnit.Case
  doctest Kb

  test "greets the world" do
    assert Kb.hello() == :world
  end
end
