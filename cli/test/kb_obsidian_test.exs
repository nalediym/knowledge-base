defmodule Kb.ObsidianTest do
  use ExUnit.Case, async: true

  alias Kb.Obsidian

  describe "detect_cli/1" do
    test "returns {:ok, path} when finder locates the binary" do
      finder = fn "obsidian" -> "/usr/local/bin/obsidian" end
      assert {:ok, "/usr/local/bin/obsidian"} = Obsidian.detect_cli(finder: finder)
    end

    test "returns {:error, :not_found} when finder returns nil" do
      finder = fn "obsidian" -> nil end
      assert {:error, :not_found} = Obsidian.detect_cli(finder: finder)
    end

    test "returns {:error, :unsupported_os} on windows without touching finder" do
      finder = fn _ -> flunk("finder should not be called on windows") end
      assert {:error, :unsupported_os} = Obsidian.detect_cli(finder: finder, os: :windows)
    end

    test "works on linux" do
      finder = fn "obsidian" -> "/home/me/.local/bin/obsidian" end
      assert {:ok, "/home/me/.local/bin/obsidian"} =
               Obsidian.detect_cli(finder: finder, os: :linux)
    end
  end

  describe "build_command/2" do
    test "builds shell command for daily:append" do
      finder = fn "obsidian" -> "/opt/obsidian/obsidian" end

      assert {:ok, {"/opt/obsidian/obsidian", ["daily:append", "hello world"]}} =
               Obsidian.build_command(["daily:append", "hello world"], finder: finder)
    end

    test "builds shell command for base:query" do
      finder = fn "obsidian" -> "/usr/local/bin/obsidian" end

      assert {:ok, {"/usr/local/bin/obsidian", ["base:query", "MyBase"]}} =
               Obsidian.build_command(["base:query", "MyBase"], finder: finder)
    end

    test "propagates detect errors" do
      finder = fn _ -> nil end
      assert {:error, :not_found} = Obsidian.build_command(["daily:append", "x"], finder: finder)
    end
  end

  describe "invoke/2" do
    test "daily_append forwards to runner with correct args and returns :ok on exit 0" do
      parent = self()
      finder = fn "obsidian" -> "/usr/local/bin/obsidian" end

      runner = fn path, args ->
        send(parent, {:cmd, path, args})
        {"", 0}
      end

      assert :ok = Obsidian.daily_append("KB: compiled 3 pages", finder: finder, runner: runner)
      assert_receive {:cmd, "/usr/local/bin/obsidian", ["daily:append", "KB: compiled 3 pages"]}
    end

    test "base_query forwards base:query subcommand" do
      parent = self()
      finder = fn "obsidian" -> "/usr/local/bin/obsidian" end

      runner = fn path, args ->
        send(parent, {:cmd, path, args})
        {"ok", 0}
      end

      assert :ok = Obsidian.base_query("Projects", finder: finder, runner: runner)
      assert_receive {:cmd, "/usr/local/bin/obsidian", ["base:query", "Projects"]}
    end

    test "returns {:error, {:nonzero_exit, code, out}} on non-zero exit" do
      finder = fn "obsidian" -> "/bin/obsidian" end
      runner = fn _p, _a -> {"boom", 2} end

      assert {:error, {:nonzero_exit, 2, "boom"}} =
               Obsidian.daily_append("x", finder: finder, runner: runner)
    end

    test "swallows runner exceptions into {:error, ...}" do
      finder = fn "obsidian" -> "/bin/obsidian" end
      runner = fn _p, _a -> raise "kaboom" end

      assert {:error, {:exception, _msg}} =
               Obsidian.daily_append("x", finder: finder, runner: runner)
    end

    test "returns the detect error when binary is missing" do
      finder = fn _ -> nil end
      assert {:error, :not_found} = Obsidian.daily_append("x", finder: finder)
    end
  end

  describe "running?/1 and status/1" do
    test "running? returns true when --version exits 0" do
      finder = fn "obsidian" -> "/usr/local/bin/obsidian" end
      runner = fn _, ["--version"] -> {"1.12.4\n", 0} end
      assert Obsidian.running?(finder: finder, runner: runner)
    end

    test "running? returns false when --version exits non-zero" do
      finder = fn "obsidian" -> "/usr/local/bin/obsidian" end
      runner = fn _, ["--version"] -> {"err", 1} end
      refute Obsidian.running?(finder: finder, runner: runner)
    end

    test "running? returns false when binary missing" do
      finder = fn _ -> nil end
      runner = fn _, _ -> flunk("runner should not be called") end
      refute Obsidian.running?(finder: finder, runner: runner)
    end

    test "status returns version map when running" do
      finder = fn "obsidian" -> "/usr/local/bin/obsidian" end
      runner = fn _, ["--version"] -> {"1.12.4\n", 0} end

      assert {:ok, %{binary: "/usr/local/bin/obsidian", running: true, version: "1.12.4"}} =
               Obsidian.status(finder: finder, runner: runner)
    end

    test "status reports unsupported_os on windows" do
      assert {:error, :unsupported_os} = Obsidian.status(os: :windows)
    end
  end
end
