defmodule Kb.LLM.OpenAI do
  @moduledoc """
  OpenAI provider stub. Gated behind OPENAI_API_KEY. Returns :unknown
  and prints a hint if the key is missing. Implemented as a thin wrapper
  around :httpc to avoid new deps; wire this up fully when needed.
  """

  @behaviour Kb.LLM

  @impl Kb.LLM
  def compare_claims(_a, _b) do
    case System.get_env("OPENAI_API_KEY") do
      nil ->
        IO.puts(:stderr, "OpenAI provider requested but OPENAI_API_KEY is unset. Returning :unknown.")
        :unknown

      _key ->
        IO.puts(:stderr, "OpenAI provider is a stub — not yet implemented. Returning :unknown.")
        :unknown
    end
  end
end
