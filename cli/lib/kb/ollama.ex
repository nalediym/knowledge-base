defmodule Kb.Ollama do
  @moduledoc """
  Minimal Ollama embeddings client using `:httpc` from OTP stdlib (no new deps).

  Assumes Ollama is reachable at `http://localhost:11434`. All failures are
  returned as `{:error, reason}` so the caller can degrade gracefully.
  """

  @default_url "http://localhost:11434/api/embeddings"
  @default_model "nomic-embed-text"
  @timeout_ms 5_000

  @doc """
  Quick reachability check against an Ollama endpoint. Returns `:ok` or `{:error, reason}`.
  Uses the embeddings URL's origin so we can reuse the same config everywhere.
  """
  def ping(url \\ @default_url) do
    origin = origin_of(url)

    :inets.start()

request = {String.to_charlist(origin <> "/api/tags"), []}

    case :httpc.request(:get, request, [{:timeout, 1_000}, {:connect_timeout, 500}], []) do
      {:ok, {{_, status, _}, _headers, _body}} when status in 200..499 -> :ok
      {:ok, _} -> {:error, :bad_status}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Produce an embedding for `text`. Options:

    * `:url`   — embeddings endpoint (default `#{@default_url}`)
    * `:model` — model name (default `#{@default_model}`)
  """
  def embed(text, opts \\ []) when is_binary(text) do
    url = Keyword.get(opts, :url, @default_url)
    model = Keyword.get(opts, :model, @default_model)

    body = Jason.encode!(%{model: model, prompt: text})

    :inets.start()

request =
      {String.to_charlist(url), [{~c"content-type", ~c"application/json"}], ~c"application/json",
       body}

    case :httpc.request(
           :post,
           request,
           [{:timeout, @timeout_ms}, {:connect_timeout, 1_000}],
           []
         ) do
      {:ok, {{_, 200, _}, _headers, resp}} ->
        case Jason.decode(IO.iodata_to_binary(resp)) do
          {:ok, %{"embedding" => vec}} when is_list(vec) -> {:ok, vec}
          {:ok, other} -> {:error, {:unexpected_shape, other}}
          {:error, reason} -> {:error, {:decode, reason}}
        end

      {:ok, {{_, status, _}, _headers, body}} ->
        {:error, {:http, status, IO.iodata_to_binary(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp origin_of(url) do
    uri = URI.parse(url)
    scheme = uri.scheme || "http"
    port = if uri.port, do: ":#{uri.port}", else: ""
    "#{scheme}://#{uri.host || "localhost"}#{port}"
  end
end
