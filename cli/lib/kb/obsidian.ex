defmodule Kb.Obsidian do
  @moduledoc """
  Integration with the Obsidian Official CLI (v1.12.0+, Feb 2026).

  The binary `obsidian` ships with Obsidian Desktop and lands on PATH on
  macOS and Linux. It communicates via IPC with the running desktop app, so
  running Obsidian is required for most commands to succeed.

  On Windows v1, Obsidian ships a `.com` redirector stub instead of a native
  binary — unsupported here; detect returns `{:error, :unsupported_os}`.

  Design notes:
  - All shell outs go through this module so `System.find_executable/1`
    (and the resolved binary path) can be mocked in tests.
  - `obsidian_cli: true` in `kb.config.json` is the toggle. Absent/`false`
    means "fall back to `obsidian://` URL scheme" (handled elsewhere).
  - Calls MUST never crash the caller. Errors are swallowed with a warning.
  """

  @binary "obsidian"

  @doc """
  Detect the Obsidian CLI binary on PATH.

  Returns:
  - `{:ok, path}` when `obsidian` is found
  - `{:error, :not_found}` when `obsidian` is not on PATH
  - `{:error, :unsupported_os}` on Windows (no native binary)

  The executable finder is pluggable for tests — pass `:finder` to override
  `System.find_executable/1`.
  """
  def detect_cli(opts \\ []) do
    finder = Keyword.get(opts, :finder, &System.find_executable/1)
    os = Keyword.get(opts, :os, os_type())

    case os do
      :windows ->
        {:error, :unsupported_os}

      _ ->
        case finder.(@binary) do
          nil -> {:error, :not_found}
          path when is_binary(path) -> {:ok, path}
        end
    end
  end

  @doc """
  Probe whether Obsidian is reachable via the CLI (desktop app running).

  Tries `obsidian --version`; exit status 0 means yes.
  """
  def running?(opts \\ []) do
    runner = Keyword.get(opts, :runner, &default_cmd/2)

    case detect_cli(opts) do
      {:ok, path} ->
        case runner.(path, ["--version"]) do
          {_out, 0} -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  @doc """
  Append a line to today's daily note via `obsidian daily:append`.
  Never raises. Returns `:ok | {:error, reason}`.
  """
  def daily_append(message, opts \\ []) when is_binary(message) do
    invoke(["daily:append", message], opts)
  end

  @doc """
  Query an Obsidian Base (1.9+ table-view primitive) via `obsidian base:query`.
  """
  def base_query(query, opts \\ []) when is_binary(query) do
    invoke(["base:query", query], opts)
  end

  @doc """
  Report status: binary path, reachable, version string.
  """
  def status(opts \\ []) do
    runner = Keyword.get(opts, :runner, &default_cmd/2)

    case detect_cli(opts) do
      {:ok, path} ->
        case runner.(path, ["--version"]) do
          {out, 0} -> {:ok, %{binary: path, running: true, version: String.trim(out)}}
          {_out, _code} -> {:ok, %{binary: path, running: false, version: nil}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Build (but don't execute) the command tuple that `invoke/2` would run.
  Useful for tests and for debugging.
  """
  def build_command(args, opts \\ []) when is_list(args) do
    case detect_cli(opts) do
      {:ok, path} -> {:ok, {path, args}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Low-level shell out. Swallows all errors (never breaks the caller).
  Returns `:ok | {:error, reason}`.
  """
  def invoke(args, opts \\ []) when is_list(args) do
    runner = Keyword.get(opts, :runner, &default_cmd/2)

    case detect_cli(opts) do
      {:ok, path} ->
        try do
          case runner.(path, args) do
            {_out, 0} -> :ok
            {out, code} -> {:error, {:nonzero_exit, code, String.trim(to_string(out))}}
          end
        rescue
          e -> {:error, {:exception, Exception.message(e)}}
        catch
          kind, reason -> {:error, {kind, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- internals ---

  defp default_cmd(path, args) do
    System.cmd(path, args, stderr_to_stdout: true)
  end

  defp os_type do
    case :os.type() do
      {:win32, _} -> :windows
      {:unix, :darwin} -> :macos
      {:unix, _} -> :linux
      _ -> :unknown
    end
  end
end
