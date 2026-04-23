defmodule Kb.WatchTest do
  use ExUnit.Case, async: false

  setup do
    tmp = Path.join(System.tmp_dir!(), "kb-watch-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  test "detects a new file within the debounce window", %{tmp: tmp} do
    parent = self()
    ingested = self()

    {:ok, pid} =
      Kb.Watch.start_link(
        paths: [tmp],
        poll_ms: 50,
        debounce_ms: 50,
        ingest: fn path -> send(ingested, {:ingested, path}) end,
        on_batch: fn paths -> send(parent, {:batch, paths}) end
      )

    # Write a file after starting the watcher.
    Process.sleep(60)
    target = Path.join(tmp, "hello.md")
    File.write!(target, "hi")

    # Wait for poll (50ms) + debounce (50ms) + slack.
    assert_receive {:ingested, ^target}, 1_000
    assert_receive {:batch, [^target]}, 1_000

    GenServer.stop(pid)
  end

  test "coalesces many writes within debounce window into one batch", %{tmp: tmp} do
    parent = self()

    {:ok, pid} =
      Kb.Watch.start_link(
        paths: [tmp],
        poll_ms: 100,
        debounce_ms: 200,
        ingest: fn _ -> :ok end,
        on_batch: fn paths -> send(parent, {:batch, paths}) end
      )

    Process.sleep(30)

    # Create 10 files across a small interval (all within debounce window).
    for i <- 1..10 do
      File.write!(Path.join(tmp, "f-#{i}.md"), "x")
      Process.sleep(5)
    end

    assert_receive {:batch, paths}, 2_000
    assert length(paths) == 10

    # Ensure no second batch immediately follows.
    refute_receive {:batch, _}, 300

    GenServer.stop(pid)
  end

  test "ignores unchanged files on subsequent polls", %{tmp: tmp} do
    parent = self()
    File.write!(Path.join(tmp, "stable.md"), "1")

    {:ok, pid} =
      Kb.Watch.start_link(
        paths: [tmp],
        poll_ms: 40,
        debounce_ms: 40,
        ingest: fn _ -> :ok end,
        on_batch: fn paths -> send(parent, {:batch, paths}) end
      )

    # No writes → no batch should fire.
    refute_receive {:batch, _}, 300

    GenServer.stop(pid)
  end
end
