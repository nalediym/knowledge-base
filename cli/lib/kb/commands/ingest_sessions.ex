defmodule KB.Commands.IngestSessions do
  @moduledoc """
  Orchestrator for `kb ingest --sessions [--agent claude|codex|all]`.

  Walks each installed adapter, parses every session it reports, redacts,
  renders to markdown under `kb/raw/sessions/<project>/YYYY-MM-DD-<slug>.md`,
  and updates the manifest with `source_type: "session"` entries.
  """

  alias KB.Sessions.{Adapters, Renderer, SessionDoc}

  @all_adapters [
    Adapters.ClaudeCode,
    Adapters.CodexCli,
    Adapters.GeminiCli,
    Adapters.Cursor,
    Adapters.Copilot
  ]

  @agent_aliases %{
    "claude" => Adapters.ClaudeCode,
    "claude_code" => Adapters.ClaudeCode,
    "codex" => Adapters.CodexCli,
    "codex_cli" => Adapters.CodexCli,
    "gemini" => Adapters.GeminiCli,
    "cursor" => Adapters.Cursor,
    "copilot" => Adapters.Copilot
  }

  @doc """
  Entry point invoked by `Kb.CLI`.

  Options:

    * `agent: "claude" | "codex" | "all"` — filter to one agent. Default `"all"`.
    * `output_base: Path.t()`            — override output directory. Default `kb/raw/sessions`.
    * `dry_run: bool`                    — don't write files or touch manifest.
  """
  def run(opts \\ []) do
    agent_filter = Keyword.get(opts, :agent, "all")
    output_base = Keyword.get(opts, :output_base, "kb/raw/sessions")
    dry_run = Keyword.get(opts, :dry_run, false)

    adapters = filter_adapters(agent_filter)
    installed = detect_installed(adapters)

    if installed == [] do
      IO.puts("No matching agent session stores found on this machine.")
      {:ok, []}
    else
      entries =
        installed
        |> Enum.flat_map(fn {adapter, files} ->
          IO.puts("[#{adapter.agent_name()}] #{length(files)} session(s)")
          Enum.flat_map(files, fn path -> ingest_one(adapter, path, output_base, dry_run) end)
        end)

      unless dry_run, do: update_manifest(entries)

      IO.puts("Ingested #{length(entries)} session transcript(s).")
      {:ok, entries}
    end
  end

  @doc "Return `[{adapter_module, [path]}]` for all installed adapters."
  def detect_installed(adapters \\ @all_adapters) do
    adapters
    |> Enum.map(fn mod ->
      case mod.detect() do
        {:ok, files} -> {mod, files}
        :not_installed -> {mod, :not_installed}
      end
    end)
    |> Enum.filter(fn
      {_mod, :not_installed} -> false
      {_mod, _files} -> true
    end)
  end

  defp filter_adapters("all"), do: @all_adapters
  defp filter_adapters(nil), do: @all_adapters

  defp filter_adapters(name) when is_binary(name) do
    case Map.fetch(@agent_aliases, String.downcase(name)) do
      {:ok, mod} -> [mod]
      :error -> []
    end
  end

  defp ingest_one(adapter, path, output_base, dry_run) do
    with {:ok, doc} <- adapter.parse(path) do
      redacted = adapter.redact(doc)
      rendered = Renderer.render(redacted)
      out_path = Renderer.output_path(output_base, redacted)

      unless dry_run do
        File.mkdir_p!(Path.dirname(out_path))
        File.write!(out_path, rendered)
      end

      [build_manifest_entry(redacted, out_path, rendered)]
    else
      {:error, :not_implemented} ->
        []

      {:error, reason} ->
        IO.puts("  skip: #{path} (#{inspect(reason)})")
        []
    end
  end

  defp build_manifest_entry(%SessionDoc{} = doc, out_path, rendered) do
    %{
      "path" => out_path,
      "slug" => Path.relative_to(out_path, "kb/raw") |> String.replace("/", "--"),
      "hash" => :crypto.hash(:sha256, rendered) |> Base.encode16(case: :lower),
      "ingested" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source_type" => "session",
      "agent" => doc.agent,
      "project" => doc.project,
      "session_id" => doc.session_id,
      "source_path" => doc.source_path,
      "turns" => length(doc.messages)
    }
  end

  defp update_manifest([]), do: :ok

  defp update_manifest(entries) do
    case Kb.Manifest.update("session-ingest", fn manifest ->
           Enum.reduce(entries, manifest, &Kb.Manifest.add_source(&2, &1))
         end) do
      {:ok, _} ->
        :ok

      {:error, :no_manifest} ->
        IO.puts("No KB found. Run `kb init` first.")

      {:error, :locked} ->
        IO.puts("KB is locked by another session. Try again later.")
    end
  end
end
