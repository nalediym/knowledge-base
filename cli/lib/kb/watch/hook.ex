defmodule Kb.Watch.Hook do
  @moduledoc """
  Idempotent Claude Code SessionStart hook installer.

  Upserts a `SessionStart` entry in `~/.claude/settings.json` that runs
  `kb ingest --sessions` (with graceful degradation to `kb ingest kb/raw`
  if the `--sessions` flag isn't available — see note in install report).

  Guarantees:

    * Creates `~/.claude/settings.json` if missing.
    * Backs up the existing file once to `settings.json.bak` before writing.
    * Running this multiple times does not duplicate the entry (matched by
      the hook's `command` string).
  """

  @hook_command "kb ingest --sessions"
  @hook_matcher "kb-watch"

  @doc """
  Install (or verify) the SessionStart hook. Returns `{:ok, :installed}` on
  first install, `{:ok, :already_present}` on subsequent runs.

  Options:

    * `:settings_path` — override path (for tests). Defaults to
      `~/.claude/settings.json`.
    * `:command` — override the command to run.
  """
  def install(opts \\ []) do
    path = Keyword.get(opts, :settings_path, default_settings_path())
    command = Keyword.get(opts, :command, @hook_command)

    File.mkdir_p!(Path.dirname(path))

    current =
      case File.read(path) do
        {:ok, ""} -> %{}
        {:ok, json} -> Jason.decode!(json)
        {:error, :enoent} -> %{}
      end

    if File.exists?(path), do: backup_once(path)

    {updated, status} = upsert_hook(current, command)

    if status == :installed do
      File.write!(path, Jason.encode!(updated, pretty: true) <> "\n")
      IO.puts("Installed SessionStart hook → #{path}")
    else
      IO.puts("SessionStart hook already present → #{path}")
    end

    {:ok, status}
  end

  @doc "Remove any hook entries matching our command. Used in tests."
  def uninstall(opts \\ []) do
    path = Keyword.get(opts, :settings_path, default_settings_path())
    command = Keyword.get(opts, :command, @hook_command)

    case File.read(path) do
      {:ok, json} ->
        data = Jason.decode!(json)
        data = remove_hook(data, command)
        File.write!(path, Jason.encode!(data, pretty: true) <> "\n")
        :ok

      _ ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Internal
  # ---------------------------------------------------------------------------

  # Shape (per Claude Code hooks docs):
  #   { "hooks": { "SessionStart": [ { "matcher": "...", "hooks": [
  #       { "type": "command", "command": "..." } ] } ] } }
  defp upsert_hook(settings, command) do
    hooks = Map.get(settings, "hooks", %{})
    session_start = Map.get(hooks, "SessionStart", [])

    present? =
      Enum.any?(session_start, fn entry ->
        entry
        |> Map.get("hooks", [])
        |> Enum.any?(&(Map.get(&1, "command") == command))
      end)

    if present? do
      {settings, :already_present}
    else
      new_entry = %{
        "matcher" => @hook_matcher,
        "hooks" => [%{"type" => "command", "command" => command}]
      }

      updated = Map.put(settings, "hooks", Map.put(hooks, "SessionStart", session_start ++ [new_entry]))
      {updated, :installed}
    end
  end

  defp remove_hook(settings, command) do
    hooks = Map.get(settings, "hooks", %{})
    session_start = Map.get(hooks, "SessionStart", [])

    filtered =
      session_start
      |> Enum.map(fn entry ->
        sub = Enum.reject(Map.get(entry, "hooks", []), &(Map.get(&1, "command") == command))
        Map.put(entry, "hooks", sub)
      end)
      |> Enum.reject(&(Map.get(&1, "hooks", []) == []))

    Map.put(settings, "hooks", Map.put(hooks, "SessionStart", filtered))
  end

  defp backup_once(path) do
    bak = path <> ".bak"

    if not File.exists?(bak) do
      File.cp!(path, bak)
    end
  end

  defp default_settings_path do
    Path.expand("~/.claude/settings.json")
  end
end
