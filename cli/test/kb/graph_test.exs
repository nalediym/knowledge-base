defmodule Kb.GraphTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    wiki = Path.join(tmp_dir, "wiki")
    File.mkdir_p!(Path.join(wiki, "sources"))
    File.mkdir_p!(Path.join(wiki, "concepts"))

    File.write!(Path.join([wiki, "sources", "auth-design.md"]), """
    # Auth Design

    > **Status:** fresh

    See [jwt-authentication](../concepts/jwt-authentication.md)#c-70eb6658
    and [missing-concept](../concepts/missing-concept.md).
    """)

    File.write!(Path.join([wiki, "sources", "legacy.md"]), """
    # Legacy Doc

    > **Status:** stale
    """)

    File.write!(Path.join([wiki, "concepts", "jwt-authentication.md"]), """
    # JWT Authentication

    > **Status:** fresh

    From [auth-design](../sources/auth-design.md)#c-70eb6658.
    """)

    {:ok, wiki: wiki}
  end

  test "build/1 returns typed nodes for sources, concepts, candidates, and stale", %{wiki: wiki} do
    graph = Kb.Graph.build(wiki)
    kinds = Enum.group_by(graph.nodes, & &1.kind)

    assert length(kinds[:source] || []) == 1,
           "expected one fresh source, got #{inspect(kinds)}"
    assert length(kinds[:concept] || []) == 1
    assert length(kinds[:candidate] || []) == 1
    assert length(kinds[:stale] || []) == 1

    assert Enum.any?(graph.nodes, fn n -> n.id == "missing-concept" and n.kind == :candidate end)
    assert Enum.any?(graph.nodes, fn n -> n.id == "legacy" and n.kind == :stale end)
  end

  test "build/1 collects edges with chunk citations", %{wiki: wiki} do
    graph = Kb.Graph.build(wiki)

    edge =
      Enum.find(graph.edges, fn e ->
        e.from == "auth-design" and e.to == "jwt-authentication"
      end)

    assert edge, "expected edge auth-design -> jwt-authentication"
    assert "c-70eb6658" in edge.citations
  end
end
