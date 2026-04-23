defmodule Kb.GraphServerTest do
  use ExUnit.Case, async: false

  alias Kb.Test.HTTPClient

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    wiki = Path.join(tmp_dir, "wiki")
    File.mkdir_p!(Path.join(wiki, "sources"))
    File.mkdir_p!(Path.join(wiki, "concepts"))

    File.write!(Path.join([wiki, "sources", "auth-design.md"]), """
    # Auth Design
    > **Status:** fresh

    See [jwt-authentication](../concepts/jwt-authentication.md)#c-70eb6658.
    """)

    File.write!(Path.join([wiki, "concepts", "jwt-authentication.md"]), """
    # JWT Authentication
    > **Status:** fresh
    """)

    {:ok, _pid, port} = Kb.Graph.Server.start_link(port: 0, wiki_root: wiki)

    on_exit(fn -> Kb.Graph.Server.stop() end)

    {:ok, port: port, wiki: wiki}
  end

  test "serves index page at /", %{port: port} do
    %{status: status, body: body} = HTTPClient.get("http://localhost:#{port}/")

    assert status == 200
    assert body =~ "kb graph serve"
    assert body =~ "/assets/app.js"
  end

  test "serves vendored JS from /assets/app.js", %{port: port} do
    %{status: status, body: body} = HTTPClient.get("http://localhost:#{port}/assets/app.js")

    assert status == 200
    assert body =~ "KbForce"
  end

  test "/graph.json returns expected node and edge counts", %{port: port} do
    %{status: status, body: body} = HTTPClient.get("http://localhost:#{port}/graph.json")

    assert status == 200
    %{"nodes" => nodes, "edges" => edges} = Jason.decode!(body)

    assert length(nodes) == 2
    assert Enum.any?(nodes, &(&1["id"] == "auth-design" and &1["kind"] == "source"))
    assert Enum.any?(nodes, &(&1["id"] == "jwt-authentication" and &1["kind"] == "concept"))

    assert length(edges) == 1
    [edge] = edges
    assert edge["from"] == "auth-design"
    assert edge["to"] == "jwt-authentication"
    assert "c-70eb6658" in edge["citations"]
  end

  test "/healthz returns ok", %{port: port} do
    %{status: status, body: body} = HTTPClient.get("http://localhost:#{port}/healthz")

    assert status == 200
    assert body == "ok"
  end

  test "simulate_ingest publishes delta to connected subscriber" do
    Kb.Graph.PubSub.subscribe()

    delta = Kb.Graph.simulate_ingest_delta("new-source", :source)
    Kb.Graph.PubSub.broadcast(delta)

    assert_receive {:kb_graph_event, "kb:graph", payload}, 1_000
    assert [node] = payload.add_nodes
    assert node.id == "new-source"
    assert node.kind == :source
  end
end
