defmodule Kb.LLM.Ollama do
  @moduledoc """
  Ollama provider. POSTs to http://localhost:11434/api/generate with a
  templated prompt and parses yes/no/unknown out of the response.

  Config precedence:
    1. KB_OLLAMA_URL env var
    2. default http://localhost:11434
  Model defaults to `llama3.1` but can be overridden with KB_OLLAMA_MODEL.
  """

  @behaviour Kb.LLM

  @default_url "http://localhost:11434"
  @default_model "llama3.1"

  @impl Kb.LLM
  def compare_claims(a, b) do
    url = (System.get_env("KB_OLLAMA_URL") || @default_url) <> "/api/generate"
    model = System.get_env("KB_OLLAMA_MODEL") || @default_model

    prompt = build_prompt(a.text, b.text)

    body = Jason.encode!(%{
      "model" => model,
      "prompt" => prompt,
      "stream" => false,
      "options" => %{"temperature" => 0}
    })

    case http_post(url, body) do
      {:ok, response_body} ->
        response_body
        |> extract_response()
        |> parse_verdict()

      {:error, _reason} ->
        :unknown
    end
  end

  defp build_prompt(a, b) do
    """
    You are checking whether two claims contradict each other.

    Claim A: #{a}
    Claim B: #{b}

    Answer with exactly one word: "agree" if both claims can be true
    simultaneously, "disagree" if they contradict each other, or
    "unknown" if there is not enough context to decide.
    """
  end

  defp http_post(url, body) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    request = {
      String.to_charlist(url),
      [{~c"content-type", ~c"application/json"}],
      ~c"application/json",
      body
    }

    case :httpc.request(:post, request, [{:timeout, 30_000}], []) do
      {:ok, {{_, 200, _}, _headers, resp_body}} ->
        {:ok, List.to_string(resp_body)}

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_response(body) do
    case Jason.decode(body) do
      {:ok, %{"response" => text}} -> text
      _ -> ""
    end
  end

  def parse_verdict(text) do
    lowered = text |> String.downcase() |> String.trim()

    cond do
      String.contains?(lowered, "disagree") -> :disagree
      String.contains?(lowered, "contradict") -> :disagree
      String.contains?(lowered, "agree") -> :agree
      String.contains?(lowered, "consistent") -> :agree
      String.contains?(lowered, "compatible") -> :agree
      true -> :unknown
    end
  end
end
