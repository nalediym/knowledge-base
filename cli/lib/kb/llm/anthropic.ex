defmodule Kb.LLM.Anthropic do
  @moduledoc """
  Anthropic provider stub. Gated behind ANTHROPIC_API_KEY. Returns :unknown
  and prints a hint if the key is missing. Wire up the Messages API here
  when a real implementation is needed.
  """

  @behaviour Kb.LLM

  @impl Kb.LLM
  def compare_claims(_a, _b) do
    case System.get_env("ANTHROPIC_API_KEY") do
      nil ->
        IO.puts(:stderr, "Anthropic provider requested but ANTHROPIC_API_KEY is unset. Returning :unknown.")
        :unknown

      _key ->
        IO.puts(:stderr, "Anthropic provider is a stub — not yet implemented. Returning :unknown.")
        :unknown
    end
  end
end
