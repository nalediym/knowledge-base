defmodule Kb.LLM.OllamaTest do
  use ExUnit.Case, async: true

  alias Kb.LLM.Ollama

  test "parse_verdict recognizes disagree" do
    assert Ollama.parse_verdict("disagree") == :disagree
    assert Ollama.parse_verdict("These claims contradict each other.") == :disagree
  end

  test "parse_verdict recognizes agree" do
    assert Ollama.parse_verdict("agree") == :agree
    assert Ollama.parse_verdict("They are consistent.") == :agree
    assert Ollama.parse_verdict("Compatible.") == :agree
  end

  test "parse_verdict falls back to unknown" do
    assert Ollama.parse_verdict("") == :unknown
    assert Ollama.parse_verdict("maybe") == :unknown
  end
end
