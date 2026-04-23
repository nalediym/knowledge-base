defmodule Kb.Graph.Server do
  @moduledoc """
  Runs the `kb graph serve` HTTP server backed by `Plug.Cowboy`.

  `start/1` is used by the CLI (prints URL, optionally opens browser, then
  blocks on SIGINT). `start_link/1` is used by tests; it starts the server
  under a supervisor and returns the actual bound port.
  """

  require Logger

  @doc """
  CLI entrypoint. Blocks until the VM receives SIGINT / SIGTERM.

  Options:
    * `:port`     — TCP port (default 4000; 0 = ephemeral)
    * `:open?`    — open default browser on start (default true)
    * `:wiki_root` — override wiki root (default `kb/wiki`)
  """
  def start(opts \\ []) do
    port = Keyword.get(opts, :port, 4000)
    open? = Keyword.get(opts, :open?, true)
    wiki_root = Keyword.get(opts, :wiki_root, "kb/wiki")

    Application.put_env(:kb, :wiki_root, wiki_root)

    case start_link(port: port, wiki_root: wiki_root) do
      {:ok, _pid, bound_port} ->
        url = "http://localhost:#{bound_port}"
        IO.puts("kb graph serve — #{url}")
        IO.puts("  wiki:  #{Path.expand(wiki_root)}")
        IO.puts("  press ctrl-c to stop")
        if open?, do: open_browser(url)
        await_shutdown()

      {:error, reason} ->
        IO.puts(:stderr, "kb graph serve: failed to start: #{inspect(reason)}")
        System.halt(1)
    end
  end

  @doc """
  Start the server for tests / embedded use.
  Returns `{:ok, pid, port}`.
  """
  def start_link(opts) do
    port = Keyword.get(opts, :port, 0)
    wiki_root = Keyword.get(opts, :wiki_root, "kb/wiki")
    Application.put_env(:kb, :wiki_root, wiki_root)

    case Plug.Cowboy.http(Kb.Graph.Router, [], port: port, ref: ref()) do
      {:ok, pid} ->
        bound = :ranch.get_port(ref())
        {:ok, pid, bound}

      {:error, {:already_started, pid}} ->
        bound = :ranch.get_port(ref())
        {:ok, pid, bound}

      err ->
        err
    end
  end

  @doc false
  def stop do
    try do
      Plug.Cowboy.shutdown(ref())
    catch
      :exit, _ -> :ok
    end

    :ok
  end

  defp ref, do: Kb.Graph.Router.HTTP

  defp open_browser(url) do
    opener =
      case :os.type() do
        {:unix, :darwin} -> "open"
        _ -> "xdg-open"
      end

    spawn(fn ->
      try do
        System.cmd(opener, [url], stderr_to_stdout: true)
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    end)

    :ok
  end

  defp await_shutdown do
    # Block forever. The BEAM translates SIGINT -> clean shutdown of the VM
    # by default, which tears down the Cowboy listener.
    Process.flag(:trap_exit, true)
    Process.sleep(:infinity)
  end
end
