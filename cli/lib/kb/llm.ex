defmodule Kb.LLM do
  @moduledoc """
  Provider-agnostic LLM behaviour for claim comparison.

  Providers implement `compare_claims/2` returning `:agree | :disagree | :unknown`.

  Ships with a heuristic default (no network), an Ollama HTTP client, and
  stubs for OpenAI and Anthropic (gated behind env vars).
  """

  @type verdict :: :agree | :disagree | :unknown
  @type claim :: %{text: String.t(), source: String.t(), chunk_id: String.t()}

  @callback compare_claims(claim_a :: claim(), claim_b :: claim()) :: verdict()

  @doc """
  Resolve the provider atom from a string name (from CLI or config).
  """
  def resolve("heuristic"), do: Kb.LLM.Heuristic
  def resolve("ollama"), do: Kb.LLM.Ollama
  def resolve("openai"), do: Kb.LLM.OpenAI
  def resolve("anthropic"), do: Kb.LLM.Anthropic
  def resolve(nil), do: Kb.LLM.Heuristic
  def resolve(other) when is_atom(other), do: other
  def resolve(other), do: raise(ArgumentError, "Unknown LLM provider: #{inspect(other)}")

  @doc """
  Dispatch to the provider's compare_claims/2.
  """
  def compare_claims(provider, a, b) when is_atom(provider) do
    provider.compare_claims(a, b)
  end
end
