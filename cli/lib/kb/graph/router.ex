defmodule Kb.Graph.Router do
  @moduledoc """
  HTTP router for `kb graph serve`. Serves:

    * GET  /            — single-page graph viewer (static HTML)
    * GET  /assets/*    — vendored JS (no CDN)
    * GET  /graph.json  — current graph snapshot
    * GET  /events      — Server-Sent Events stream of graph deltas
    * POST /open        — open a wiki file via `open` / `xdg-open`
    * GET  /healthz     — liveness probe
  """

  use Plug.Router

  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason, pass: ["*/*"])
  plug(:dispatch)

  @priv_root Application.app_dir(:kb, "priv/graph_web")

  get "/healthz" do
    send_resp(conn, 200, "ok")
  end

  get "/" do
    index_path = Path.join(@priv_root, "index.html")

    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, index_path)
  end

  get "/assets/:file" do
    safe = Path.basename(file)
    path = Path.join([@priv_root, "assets", safe])

    cond do
      not File.exists?(path) ->
        send_resp(conn, 404, "not found")

      String.ends_with?(safe, ".js") ->
        conn
        |> put_resp_content_type("application/javascript")
        |> send_file(200, path)

      String.ends_with?(safe, ".css") ->
        conn
        |> put_resp_content_type("text/css")
        |> send_file(200, path)

      true ->
        send_resp(conn, 415, "unsupported media type")
    end
  end

  get "/graph.json" do
    wiki_root = opts_wiki_root(conn)
    graph = Kb.Graph.build(wiki_root)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(graph))
  end

  get "/events" do
    Kb.Graph.SSE.call(conn, [])
  end

  post "/open" do
    %{"id" => id} = conn.body_params
    wiki_root = opts_wiki_root(conn)
    graph = Kb.Graph.build(wiki_root)

    case Enum.find(graph.nodes, fn n -> n.id == id end) do
      %{path: path} when is_binary(path) ->
        opener =
          case :os.type() do
            {:unix, :darwin} -> "open"
            _ -> "xdg-open"
          end

        _ = System.cmd(opener, [path], stderr_to_stdout: true)
        send_resp(conn, 200, "ok")

      _ ->
        send_resp(conn, 404, "not found")
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp opts_wiki_root(_conn) do
    Application.get_env(:kb, :wiki_root, "kb/wiki")
  end
end
