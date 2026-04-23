defmodule Kb.Watch do
  @moduledoc """
  Debounced filesystem poller.

  Polls configured directories (defaults: `kb/raw/` + any `watch.paths` in
  `kb.config.json`). When a file's mtime changes or a new file appears, it is
  queued. After the debounce window elapses with no further changes, each
  queued file is ingested via `kb ingest <path>`.

  Implemented as a `GenServer` so it can run foreground (blocking on a
  monitor ref) or be reused programmatically in tests. Uses mtime polling —
  no `:file_system` dep — keeping the binary portable.

  ## Options

    * `:paths` — list of directories to watch. Required.
    * `:poll_ms` — polling interval in ms. Default `500`.
    * `:debounce_ms` — settle window in ms. Default `:poll_ms`.
    * `:ingest` — 1-arity fn called with a file path when debounce settles.
      Defaults to a function that runs `kb ingest <path>` via `System.cmd/3`.
    * `:include` — list of glob patterns to include. Default `["**/*"]`.
    * `:on_batch` — optional 1-arity fn called with the batched list of paths
      after ingest (useful for tests).
  """

  use GenServer
  require Logger

  @default_poll_ms 500

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Start a watcher GenServer linked to the caller."
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  @doc "Force a poll cycle now (sync). Returns the number of detected changes."
  def poll_now(server) do
    GenServer.call(server, :poll_now)
  end

  @doc "Force flushing any pending queue now (sync)."
  def flush(server) do
    GenServer.call(server, :flush)
  end

  @doc "Return the current queue (paths awaiting ingest)."
  def queue(server) do
    GenServer.call(server, :queue)
  end

  @doc """
  Foreground entrypoint used by `kb watch`. Blocks until SIGINT.

  Reads config, starts a watcher, and traps exits so Ctrl-C triggers a
  clean shutdown. This is the function wired into the CLI.
  """
  def run(args \\ []) do
    poll_ms = parse_int(args, "--poll-ms", @default_poll_ms)
    install_hook? = "--hook" in args

    if install_hook? do
      Kb.Watch.Hook.install()
    end

    config = read_watch_config()
    paths = resolve_paths(config)

    if paths == [] do
      IO.puts("No watch paths configured. Set watch.paths in kb.config.json.")
      System.halt(1)
    end

    IO.puts("kb watch")
    IO.puts("  poll:     #{poll_ms}ms")
    IO.puts("  debounce: #{poll_ms}ms")
    Enum.each(paths, &IO.puts("  path:     #{&1}"))
    IO.puts("  Ctrl-C to stop.")

    {:ok, pid} =
      start_link(
        paths: paths,
        poll_ms: poll_ms,
        debounce_ms: poll_ms,
        ingest: &invoke_ingest/1
      )

    # Trap SIGINT cleanly.
    Process.flag(:trap_exit, true)
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, _, reason} ->
        IO.puts("watcher exited: #{inspect(reason)}")
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    paths = Keyword.fetch!(opts, :paths)
    poll_ms = Keyword.get(opts, :poll_ms, @default_poll_ms)
    debounce_ms = Keyword.get(opts, :debounce_ms, poll_ms)
    include = Keyword.get(opts, :include, ["**/*"])
    ingest_fn = Keyword.get(opts, :ingest, &default_ingest/1)
    on_batch = Keyword.get(opts, :on_batch)

    state = %{
      paths: paths,
      poll_ms: poll_ms,
      debounce_ms: debounce_ms,
      include: include,
      ingest: ingest_fn,
      on_batch: on_batch,
      baseline: scan(paths, include),
      queue: MapSet.new(),
      last_change_ms: nil
    }

    schedule_poll(poll_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = tick(state)
    schedule_poll(state.poll_ms)
    {:noreply, state}
  end

  @impl true
  def handle_call(:poll_now, _from, state) do
    before_q = MapSet.size(state.queue)
    state = tick(state)
    {:reply, MapSet.size(state.queue) - before_q, state}
  end

  def handle_call(:flush, _from, state) do
    state = flush_queue(state)
    {:reply, :ok, state}
  end

  def handle_call(:queue, _from, state) do
    {:reply, MapSet.to_list(state.queue), state}
  end

  # ---------------------------------------------------------------------------
  # Internal
  # ---------------------------------------------------------------------------

  defp tick(state) do
    current = scan(state.paths, state.include)

    changed =
      for {path, mtime} <- current,
          Map.get(state.baseline, path) != mtime,
          into: MapSet.new(),
          do: path

    state =
      if MapSet.size(changed) > 0 do
        %{
          state
          | queue: MapSet.union(state.queue, changed),
            last_change_ms: now_ms(),
            baseline: current
        }
      else
        %{state | baseline: current}
      end

    if MapSet.size(state.queue) > 0 and
         state.last_change_ms != nil and
         now_ms() - state.last_change_ms >= state.debounce_ms do
      flush_queue(state)
    else
      state
    end
  end

  defp flush_queue(%{queue: q} = state) do
    paths = MapSet.to_list(q)

    Enum.each(paths, fn p ->
      try do
        state.ingest.(p)
      rescue
        e -> Logger.warning("ingest failed for #{p}: #{inspect(e)}")
      end
    end)

    if is_function(state.on_batch, 1), do: state.on_batch.(paths)

    %{state | queue: MapSet.new(), last_change_ms: nil}
  end

  defp scan(paths, include) do
    for dir <- paths,
        File.dir?(dir),
        pattern <- include,
        path <- Path.wildcard(Path.join(dir, pattern)),
        File.regular?(path),
        into: %{} do
      {path, file_mtime(path)}
    end
  end

  defp file_mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: m}} -> m
      _ -> 0
    end
  end

  defp schedule_poll(ms), do: Process.send_after(self(), :poll, ms)

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp default_ingest(path), do: invoke_ingest(path)

  defp invoke_ingest(path) do
    IO.puts("==> kb ingest #{path}")
    # Invoke via the module directly to avoid shelling out / escript overhead.
    try do
      Kb.Ingest.run(path)
    rescue
      e -> IO.puts("  ingest error: #{Exception.message(e)}")
    end
  end

  defp parse_int(args, flag, default) do
    case Enum.find_index(args, &(&1 == flag)) do
      nil ->
        default

      idx ->
        case Enum.at(args, idx + 1) do
          nil -> default
          v -> String.to_integer(v)
        end
    end
  end

  defp read_watch_config do
    case File.read("kb.config.json") do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, cfg} -> Map.get(cfg, "watch", %{})
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp resolve_paths(config) do
    paths = Map.get(config, "paths") || ["kb/raw"]

    paths
    |> Enum.map(&Path.expand/1)
    |> Enum.filter(&File.dir?/1)
  end
end
