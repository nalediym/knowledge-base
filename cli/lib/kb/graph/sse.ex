defmodule Kb.Graph.SSE do
  @moduledoc """
  Server-Sent Events stream for the `kb:graph` PubSub topic. Clients connect
  to `/events` and receive `delta` events on every broadcast plus periodic
  `ping` keepalives.

  The first write flushes the HTTP headers (chunked transfer). Each event
  follows the SSE wire format: `event: <type>\\ndata: <json>\\n\\n`.
  """

  import Plug.Conn

  @keepalive_ms 15_000

  def init(opts), do: opts

  def call(conn, _opts) do
    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> send_chunked(200)

    Kb.Graph.PubSub.subscribe()

    # Send an initial snapshot so late-joining clients don't have to wait.
    snapshot = Kb.Graph.build(Application.get_env(:kb, :wiki_root, "kb/wiki"))

    conn =
      case write_event(conn, "replace", snapshot) do
        {:ok, c} -> c
        {:error, _} -> conn
      end

    Process.send_after(self(), :keepalive, @keepalive_ms)
    loop(conn)
  end

  defp loop(conn) do
    receive do
      {:kb_graph_event, _topic, payload} ->
        case write_event(conn, "delta", payload) do
          {:ok, conn} -> loop(conn)
          {:error, _} -> conn
        end

      :keepalive ->
        case chunk(conn, "event: ping\ndata: {}\n\n") do
          {:ok, conn} ->
            Process.send_after(self(), :keepalive, @keepalive_ms)
            loop(conn)

          {:error, _} ->
            conn
        end
    after
      60_000 ->
        # idle safety valve — send a ping and keep looping
        case chunk(conn, "event: ping\ndata: {}\n\n") do
          {:ok, conn} -> loop(conn)
          {:error, _} -> conn
        end
    end
  end

  defp write_event(conn, event, data) do
    body = "event: #{event}\ndata: #{Jason.encode!(data)}\n\n"
    chunk(conn, body)
  end
end
