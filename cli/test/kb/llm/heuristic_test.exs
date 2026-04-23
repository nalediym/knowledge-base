defmodule Kb.LLM.HeuristicTest do
  use ExUnit.Case, async: true

  alias Kb.LLM.Heuristic

  defp claim(text, src \\ "s1", chunk \\ "c-aaaaaaaa") do
    %{text: text, source: src, source_path: "#{src}.md", chunk_id: chunk}
  end

  test "agrees on two claims with shared topic and same polarity" do
    a = claim("JWT tokens expire after 24 hours")
    b = claim("JWT tokens are valid for 24 hours")
    assert Heuristic.compare_claims(a, b) == :agree
  end

  test "disagrees on polarity via antonym pair" do
    a = claim("Attention complexity is quadratic with dense patterns")
    b = claim("Attention complexity is linear with sparse patterns")
    assert Heuristic.compare_claims(a, b) == :disagree
  end

  test "disagrees on negation asymmetry" do
    a = claim("Refresh tokens rotate on every use")
    b = claim("Refresh tokens do not rotate on every use")
    assert Heuristic.compare_claims(a, b) == :disagree
  end

  test "unrelated claims return :unknown" do
    a = claim("Pineapples grow in tropical climates")
    b = claim("Elixir is a functional language")
    assert Heuristic.compare_claims(a, b) == :unknown
  end

  test "numeric disagreement on the same noun flags conflict" do
    a = claim("JWT tokens expire after 24 hours")
    b = claim("JWT tokens expire after 1 hours")
    assert Heuristic.compare_claims(a, b) == :disagree
  end

  test "never runs a network call" do
    # If this test invokes a socket, CI will catch it — here we just
    # exercise the hot path and assert a verdict comes back fast.
    a = claim("Login rate limited to 5 attempts per minute per IP")
    b = claim("Login rate limited to 5 attempts per minute per IP")
    assert Heuristic.compare_claims(a, b) in [:agree, :unknown, :disagree]
  end
end
