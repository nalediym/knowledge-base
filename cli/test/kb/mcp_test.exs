defmodule Kb.MCPTest do
  use ExUnit.Case, async: false

  alias Kb.MCP
  alias Kb.MCP.Tools

  # ─── Path guard ─────────────────────────────────────────────────────────

  describe "safe_path/1" do
    setup do
      root = Path.join(System.tmp_dir!(), "kb-mcp-test-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(root, "kb/wiki"))
      File.write!(Path.join(root, "kb/wiki/ok.md"), "# ok\n")

      prev = System.get_env("KB_ROOT")
      System.put_env("KB_ROOT", root)

      on_exit(fn ->
        if prev, do: System.put_env("KB_ROOT", prev), else: System.delete_env("KB_ROOT")
        File.rm_rf!(root)
      end)

      %{root: Path.expand(root)}
    end

    test "accepts a relative path inside the root", %{root: root} do
      assert {:ok, abs} = MCP.safe_path("kb/wiki/ok.md")
      assert abs == Path.join(root, "kb/wiki/ok.md")
    end

    test "rejects ../../etc/passwd" do
      assert {:error, reason} = MCP.safe_path("../../etc/passwd")
      assert reason =~ "escapes KB_ROOT"
    end

    test "rejects deeper traversal" do
      assert {:error, reason} = MCP.safe_path("kb/../../../../etc/passwd")
      assert reason =~ "escapes KB_ROOT"
    end

    test "rejects absolute path outside root" do
      assert {:error, reason} = MCP.safe_path("/etc/passwd")
      assert reason =~ "escapes KB_ROOT"
    end

    test "rejects empty path" do
      assert {:error, "path must not be empty"} = MCP.safe_path("")
    end

    test "rejects null byte" do
      assert {:error, reason} = MCP.safe_path("kb/wiki/\0.md")
      assert reason =~ "null byte"
    end

    test "rejects non-string" do
      assert {:error, "path must be a string"} = MCP.safe_path(nil)
      assert {:error, "path must be a string"} = MCP.safe_path(123)
    end
  end

  # ─── Tool registry ──────────────────────────────────────────────────────

  describe "Tools.list/0" do
    test "registers exactly 9 tools" do
      tools = Tools.list()
      assert length(tools) == 9
    end

    test "every tool has name, description, inputSchema" do
      for tool <- Tools.list() do
        assert is_binary(tool["name"])
        assert is_binary(tool["description"])
        assert is_map(tool["inputSchema"])
        assert tool["inputSchema"]["type"] == "object"
        assert is_map(tool["inputSchema"]["properties"])
      end
    end

    test "required tool names are present" do
      names = Tools.list() |> Enum.map(& &1["name"]) |> MapSet.new()

      for expected <- ~w(kb_query kb_search kb_list_sources kb_read_page kb_lint kb_ingest kb_compile kb_export kb_dashboard) do
        assert expected in names, "missing tool: #{expected}"
      end
    end
  end

  # ─── Happy-path tool call ───────────────────────────────────────────────

  describe "Tools.call/2" do
    setup do
      root = Path.join(System.tmp_dir!(), "kb-mcp-happy-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(root, "kb/wiki/sources"))
      File.mkdir_p!(Path.join(root, "kb/wiki/concepts"))
      File.write!(Path.join(root, "kb/.kb-manifest.json"), Jason.encode!(%{
        "version" => 1,
        "name" => "test-kb",
        "created" => "2026-04-23T00:00:00Z",
        "last_compiled" => nil,
        "sources" => [
          %{"path" => "docs/a.md", "slug" => "docs--a.md", "hash" => "abc", "chunks" => 2, "ingested" => "2026-04-23T00:00:00Z"}
        ]
      }, pretty: true))
      File.write!(
        Path.join(root, "kb/wiki/sources/docs--a.md"),
        "# A\n\nJWT authentication is stateless.\n"
      )

      prev = System.get_env("KB_ROOT")
      System.put_env("KB_ROOT", root)

      on_exit(fn ->
        if prev, do: System.put_env("KB_ROOT", prev), else: System.delete_env("KB_ROOT")
        File.rm_rf!(root)
      end)

      %{root: Path.expand(root)}
    end

    test "kb_query finds a matching source" do
      assert {:ok, text} = Tools.call("kb_query", %{"question" => "JWT"})
      assert text =~ "docs--a.md"
      assert text =~ "JWT"
    end

    test "kb_read_page returns file contents" do
      assert {:ok, content} = Tools.call("kb_read_page", %{"path" => "kb/wiki/sources/docs--a.md"})
      assert content =~ "JWT authentication"
    end

    test "kb_read_page rejects path traversal" do
      assert {:error, reason} = Tools.call("kb_read_page", %{"path" => "../../etc/passwd"})
      assert reason =~ "escapes KB_ROOT"
    end

    test "kb_list_sources returns manifest payload" do
      assert {:ok, json} = Tools.call("kb_list_sources", %{})
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["project"] == "test-kb"
      assert decoded["count"] == 1
    end

    test "kb_dashboard returns counts" do
      assert {:ok, json} = Tools.call("kb_dashboard", %{})
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["sources"] == 1
      assert decoded["generated_sources"] == 0
      assert decoded["concepts"] == 0
      assert decoded["project"] == "test-kb"
    end

    test "unknown tool returns :unknown_tool" do
      assert {:unknown_tool, "kb_bogus"} = Tools.call("kb_bogus", %{})
    end
  end

  # ─── Protocol handshake ─────────────────────────────────────────────────
  #
  # We exercise the dispatcher indirectly by driving handle_line/1 through
  # a temporary group-leader and capturing stdout. This gives us a
  # protocol-level test without spawning a separate OS process.

  describe "protocol handshake" do
    test "initialize returns protocol version and server info" do
      out = dispatch_capture(~s({"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}))
      response = Jason.decode!(out)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"]["protocolVersion"] == "2024-11-05"
      assert response["result"]["serverInfo"]["name"] == "kb"
      assert is_binary(response["result"]["serverInfo"]["version"])
      assert is_map(response["result"]["capabilities"]["tools"])
    end

    test "tools/list returns the tool registry" do
      out = dispatch_capture(~s({"jsonrpc":"2.0","id":2,"method":"tools/list"}))
      response = Jason.decode!(out)

      assert response["id"] == 2
      tools = response["result"]["tools"]
      assert is_list(tools)
      assert length(tools) == 9
      names = Enum.map(tools, & &1["name"])
      assert "kb_query" in names
      assert "kb_read_page" in names
    end

    test "unknown method returns -32601" do
      out = dispatch_capture(~s({"jsonrpc":"2.0","id":3,"method":"does/not/exist"}))
      response = Jason.decode!(out)

      assert response["id"] == 3
      assert response["error"]["code"] == -32601
      assert response["error"]["message"] =~ "Method not found"
    end

    test "parse error on invalid json" do
      out = dispatch_capture("this is not json")
      response = Jason.decode!(out)

      assert response["error"]["code"] == -32700
      assert response["error"]["message"] == "Parse error"
    end

    test "initialized notification gets no response" do
      out = dispatch_capture(~s({"jsonrpc":"2.0","method":"notifications/initialized"}))
      assert out == ""
    end
  end

  # Invoke the private handle_line/1 via a small trick: we reimplement it
  # here using the public dispatch pathway. Actually, we invoke it via the
  # module's public loop by sending the line through a piped group leader.

  defp dispatch_capture(line) do
    # Capture stdout by swapping the group leader with a StringIO device.
    {:ok, dev} = StringIO.open("")
    prev = Process.group_leader()
    Process.group_leader(self(), dev)

    try do
      # handle_line/1 is private; invoke via apply on the module after
      # temporarily exposing it through :erlang.apply is impossible for
      # defp. Instead, we replicate the one-line dispatch: decode, route.
      apply_handle_line(line)
    after
      Process.group_leader(self(), prev)
    end

    {:ok, {_in, out}} = StringIO.close(dev)
    String.trim_trailing(out, "\n")
  end

  # Mirror Kb.MCP.handle_line/1 using the module's public dispatch flow.
  # We do this by encoding a request and calling the same Jason decode +
  # dispatch logic via a small helper. To avoid duplicating behaviour, we
  # use a public test hook.
  defp apply_handle_line(line) do
    Kb.MCP.handle_line(line)
  end
end
