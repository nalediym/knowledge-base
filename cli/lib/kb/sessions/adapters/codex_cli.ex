defmodule KB.Sessions.Adapters.CodexCli do
  @moduledoc """
  Adapter for OpenAI Codex CLI session transcripts.

  Codex writes JSONL sessions under both:

      ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
      ~/.codex/projects/**/*.jsonl          (alternate layout)

  The schema wraps records in `response_item` / `session_meta` / `turn_context`
  envelopes. We normalise them into the same user/assistant messages shape
  used by `KB.Sessions.Adapters.ClaudeCode`.
  """

  @behaviour KB.Sessions.Adapter

  alias KB.Sessions.{Redactor, SessionDoc}

  @roots [
    Path.join([System.user_home!() || "", ".codex", "sessions"]),
    Path.join([System.user_home!() || "", ".codex", "projects"])
  ]

  @impl true
  def agent_name, do: "codex_cli"

  @impl true
  def detect do
    found =
      @roots
      |> Enum.filter(&File.dir?/1)

    case found do
      [] ->
        :not_installed

      roots ->
        files =
          roots
          |> Enum.flat_map(fn root -> Path.wildcard(Path.join(root, "**/*.jsonl")) end)
          |> Enum.uniq()
          |> Enum.sort()

        {:ok, files}
    end
  end

  @impl true
  def parse(path) do
    with {:ok, raw} <- File.read(path) do
      records =
        raw
        |> String.split("\n", trim: true)
        |> Enum.flat_map(&decode_line/1)

      meta = Enum.find(records, %{}, &(&1["type"] == "session_meta"))
      meta_payload = Map.get(meta, "payload", %{})

      session_id = meta_payload["id"] || uuid_from_path(path)
      cwd = meta_payload["cwd"] || ""
      started_at = meta["timestamp"] || find_first_ts(records)
      model = extract_model(records)

      messages = Enum.flat_map(records, &record_to_messages/1)

      doc = %SessionDoc{
        agent: agent_name(),
        project: project_slug(cwd, path),
        session_id: session_id,
        source_path: path,
        started_at: started_at,
        model: model,
        messages: messages,
        metadata: %{record_count: length(records)}
      }

      {:ok, doc}
    end
  end

  @impl true
  def redact(%SessionDoc{} = doc) do
    opts = redact_opts()

    %SessionDoc{
      doc
      | messages:
          Enum.map(doc.messages, fn m ->
            Map.update!(m, :content, &Redactor.redact(&1, opts))
          end)
    }
  end

  # ─── parsing helpers ──────────────────────────────────────────────────

  defp decode_line(""), do: []

  defp decode_line(line) do
    case Jason.decode(line) do
      {:ok, %{} = record} -> [record]
      _ -> []
    end
  end

  defp find_first_ts(records) do
    Enum.find_value(records, fn r -> r["timestamp"] end)
  end

  defp extract_model(records) do
    Enum.find_value(records, fn
      %{"type" => "turn_context", "payload" => %{"model" => m}} when is_binary(m) -> m
      _ -> nil
    end)
  end

  defp record_to_messages(%{"type" => "response_item", "payload" => payload} = r) do
    role = Map.get(payload, "role", "")
    item_type = Map.get(payload, "type", "")
    content = Map.get(payload, "content", [])
    ts = r["timestamp"]

    cond do
      role == "user" and item_type == "message" ->
        text = codex_content_text(content, "input_text")
        if text == "", do: [], else: [%{role: "user", content: text, timestamp: ts}]

      role == "assistant" and item_type == "message" ->
        text = codex_content_text(content, "output_text")
        if text == "", do: [], else: [%{role: "assistant", content: text, timestamp: ts}]

      item_type == "web_search_call" ->
        query = Map.get(payload, "query", "")
        [%{role: "assistant", content: "`[tool: WebSearch]` #{query}", timestamp: ts}]

      true ->
        []
    end
  end

  defp record_to_messages(_), do: []

  defp codex_content_text(blocks, expected_type) when is_list(blocks) do
    blocks
    |> Enum.map(fn
      %{"type" => ^expected_type, "text" => t} when is_binary(t) -> t
      t when is_binary(t) -> t
      _ -> ""
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
    |> String.trim()
  end

  defp codex_content_text(blob, _expected) when is_binary(blob), do: String.trim(blob)
  defp codex_content_text(_, _), do: ""

  defp project_slug(cwd, _path) when is_binary(cwd) and cwd != "" do
    cwd |> Path.basename() |> slugify()
  end

  defp project_slug(_cwd, path) do
    path |> Path.dirname() |> Path.basename() |> slugify()
  end

  defp slugify(nil), do: "unknown-project"
  defp slugify(""), do: "unknown-project"

  defp slugify(s) do
    s
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "unknown-project"
      slug -> slug
    end
  end

  defp uuid_from_path(path), do: path |> Path.basename() |> Path.rootname()

  defp redact_opts do
    case File.read("kb.config.json") do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, config} ->
            extras = get_in(config, ["ingest", "redaction", "extra_patterns"]) || []
            [extra_patterns: extras]

          _ ->
            []
        end

      _ ->
        []
    end
  end
end
