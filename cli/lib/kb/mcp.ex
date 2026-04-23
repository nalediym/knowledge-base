defmodule Kb.MCP do
  @moduledoc """
  Model Context Protocol (MCP) stdio server for `kb`.

  Launched via `kb mcp`. Reads JSON-RPC 2.0 messages line-by-line from stdin,
  writes responses to stdout, logs to stderr. No SDK dependency — hand-rolled
  protocol on top of Jason.

  Methods implemented:
    * `initialize`
    * `initialized` (notification)
    * `tools/list`
    * `tools/call`
    * `ping`
    * `shutdown`

  Tools registered (v1, 9 tools):
    kb_query, kb_search, kb_list_sources, kb_read_page, kb_lint,
    kb_ingest, kb_compile, kb_export, kb_dashboard

  Path arguments to file-reading tools are validated against `$KB_ROOT`
  (defaults to `File.cwd!/0`). Paths containing `..`, absolute paths, or
  paths that escape the root after expansion are rejected.

  Reference: https://modelcontextprotocol.io/
  """

  alias Kb.MCP.Tools

  @protocol_version "2024-11-05"
  @server_name "kb"
  @jsonrpc_version "2.0"

  # ─── Entry point ────────────────────────────────────────────────────────

  @doc """
  Run the stdio MCP loop. Blocks until stdin is closed.
  """
  def run do
    log("kb MCP server starting (pid=#{System.pid()}, kb_root=#{kb_root()})")
    loop()
  end

  defp loop do
    case IO.read(:stdio, :line) do
      :eof ->
        log("stdin closed; exiting")
        :ok

      {:error, reason} ->
        log("stdin read error: #{inspect(reason)}")
        :ok

      line when is_binary(line) ->
        line
        |> String.trim()
        |> handle_line()

        loop()
    end
  end

  @doc """
  Handle a single JSON-RPC line. Public for test harness use; in production
  it is called only from the stdio read loop.
  """
  def handle_line(""), do: :ok

  def handle_line(line) do
    case Jason.decode(line) do
      {:ok, req} ->
        handle_request(req)

      {:error, _} ->
        send_message(error_response(nil, -32700, "Parse error"))
    end
  end

  defp handle_request(req) do
    method = Map.get(req, "method", "")
    id = Map.get(req, "id")
    params = Map.get(req, "params") || %{}

    case dispatch(method, params) do
      :notification ->
        :ok

      {:ok, result} ->
        if id != nil do
          send_message(%{"jsonrpc" => @jsonrpc_version, "id" => id, "result" => result})
        end

      {:error, code, message} ->
        if id != nil do
          send_message(error_response(id, code, message))
        end
    end
  rescue
    e ->
      log("handler crash: #{Exception.message(e)}")

      if Map.get(req, "id") != nil do
        send_message(error_response(req["id"], -32603, "Internal error: #{Exception.message(e)}"))
      end
  end

  # ─── Dispatch ───────────────────────────────────────────────────────────

  defp dispatch("initialize", _params) do
    {:ok,
     %{
       "protocolVersion" => @protocol_version,
       "serverInfo" => %{"name" => @server_name, "version" => Kb.version()},
       "capabilities" => %{"tools" => %{}}
     }}
  end

  defp dispatch("initialized", _params), do: :notification
  defp dispatch("notifications/initialized", _params), do: :notification
  defp dispatch("ping", _params), do: {:ok, %{}}
  defp dispatch("shutdown", _params), do: {:ok, %{}}

  defp dispatch("tools/list", _params) do
    {:ok, %{"tools" => Tools.list()}}
  end

  defp dispatch("tools/call", params) do
    name = Map.get(params, "name", "")
    args = Map.get(params, "arguments") || %{}

    case Tools.call(name, args) do
      {:ok, text} when is_binary(text) ->
        {:ok, %{"content" => [%{"type" => "text", "text" => text}], "isError" => false}}

      {:error, msg} when is_binary(msg) ->
        {:ok, %{"content" => [%{"type" => "text", "text" => msg}], "isError" => true}}

      {:unknown_tool, name} ->
        {:error, -32602, "Unknown tool: #{name}"}
    end
  end

  defp dispatch(method, _params) do
    {:error, -32601, "Method not found: #{method}"}
  end

  # ─── Transport helpers ──────────────────────────────────────────────────

  defp send_message(message) do
    json = Jason.encode!(message)
    IO.write(:stdio, json <> "\n")
  end

  defp error_response(id, code, message) do
    %{
      "jsonrpc" => @jsonrpc_version,
      "id" => id,
      "error" => %{"code" => code, "message" => message}
    }
  end

  # ─── Path guard ─────────────────────────────────────────────────────────

  @doc """
  Returns the KB root.

  Resolution order:
    1. `$KB_ROOT` if set and non-empty — used verbatim (no walk-up).
    2. Walk up from `File.cwd!/0` looking for `kb/.kb-manifest.json`.
       Stops at the filesystem root or `$HOME`.
    3. Falls back to `File.cwd!/0` if nothing found.

  Use `kb_root_with_status/0` when you need to know whether a KB was
  actually discovered.
  """
  def kb_root do
    {root, _status} = kb_root_with_status()
    root
  end

  @doc """
  Returns `{root, :found | :not_found}`. `:not_found` means we fell back
  to cwd without discovering a `.kb-manifest.json` anywhere above.

  Tool handlers should treat `:not_found` as a hard error rather than
  operating on a synthesized KB root.
  """
  def kb_root_with_status do
    case System.get_env("KB_ROOT") do
      path when is_binary(path) and path != "" ->
        expanded = Path.expand(path)
        status = if kb_present?(expanded), do: :found, else: :not_found
        {expanded, status}

      _ ->
        cwd = File.cwd!()

        case walk_up_for_manifest(cwd) do
          {:ok, root} -> {root, :found}
          :not_found -> {cwd, :not_found}
        end
    end
  end

  @doc "True if `root` contains `kb/.kb-manifest.json`."
  def kb_present?(root) do
    File.exists?(Path.join([root, "kb", ".kb-manifest.json"]))
  end

  defp walk_up_for_manifest(dir) do
    dir = Path.expand(dir)

    cond do
      kb_present?(dir) ->
        {:ok, dir}

      dir == "/" or dir == "" ->
        :not_found

      # Don't walk past $HOME — avoids accidentally picking up a KB in a
      # parent workspace the user didn't intend.
      (home = System.get_env("HOME")) && dir == Path.expand(home) ->
        :not_found

      true ->
        parent = Path.dirname(dir)
        if parent == dir, do: :not_found, else: walk_up_for_manifest(parent)
    end
  end

  @doc """
  Validate that `path` (as provided by a tool caller) resolves to a file or
  directory inside `$KB_ROOT`. Rejects:

    * absolute paths outside the root
    * relative paths containing `..` that escape the root
    * any path that, once expanded, is not a prefix of the root

  Returns `{:ok, absolute_path}` or `{:error, reason}`.
  """
  def safe_path(path) when is_binary(path) do
    root = kb_root()

    cond do
      path == "" ->
        {:error, "path must not be empty"}

      String.contains?(path, "\0") ->
        {:error, "path contains null byte"}

      true ->
        abs =
          if Path.type(path) == :absolute do
            Path.expand(path)
          else
            Path.expand(path, root)
          end

        if inside?(abs, root) do
          {:ok, abs}
        else
          {:error, "path escapes KB_ROOT (#{root}): #{path}"}
        end
    end
  end

  def safe_path(_), do: {:error, "path must be a string"}

  defp inside?(abs, root) do
    abs == root or String.starts_with?(abs, root <> "/")
  end

  # ─── Logging (stderr) ───────────────────────────────────────────────────

  defp log(msg) do
    IO.write(:stderr, "[kb-mcp] #{msg}\n")
  end
end
