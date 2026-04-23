defmodule KB.Sessions.Adapters.ClaudeCode do
  @moduledoc """
  Adapter for Claude Code session transcripts.

  Claude Code writes one JSONL per session to:

      ~/.claude/projects/<encoded-project-dir>/<session-uuid>.jsonl

  Encoded project dir names are the absolute cwd with `/` replaced by `-`,
  e.g. `-Users-naledi-Projects-hypha`. We strip to the last segment as the
  project slug.

  Sub-agent runs may live under `.../subagents/agent-*.jsonl` — we include
  them but mark them in metadata.
  """

  @behaviour KB.Sessions.Adapter

  alias KB.Sessions.{Redactor, SessionDoc}

  @store Path.join([System.user_home!() || "", ".claude", "projects"])

  @impl true
  def agent_name, do: "claude_code"

  @impl true
  def detect do
    if File.dir?(@store) do
      files =
        @store
        |> Path.join("**/*.jsonl")
        |> Path.wildcard()
        |> Enum.sort()

      {:ok, files}
    else
      :not_installed
    end
  end

  @impl true
  def parse(path) do
    with {:ok, raw} <- File.read(path) do
      records =
        raw
        |> String.split("\n", trim: true)
        |> Enum.flat_map(&decode_line/1)

      session_id = find_first(records, "sessionId") || uuid_from_path(path)
      cwd = find_first(records, "cwd") || ""
      started_at = find_first(records, "timestamp")
      model = find_model(records)

      messages = Enum.flat_map(records, &record_to_messages/1)

      doc = %SessionDoc{
        agent: agent_name(),
        project: project_slug_from_path(path, cwd),
        session_id: session_id,
        source_path: path,
        started_at: started_at,
        model: model,
        messages: messages,
        metadata: %{
          subagent: subagent?(path),
          record_count: length(records)
        }
      }

      {:ok, doc}
    end
  end

  @impl true
  def redact(%SessionDoc{} = doc) do
    opts = redact_opts()

    redacted_messages =
      Enum.map(doc.messages, fn m ->
        Map.update!(m, :content, &Redactor.redact(&1, opts))
      end)

    %SessionDoc{doc | messages: redacted_messages}
  end

  # ─── helpers ──────────────────────────────────────────────────────────

  defp decode_line(""), do: []

  defp decode_line(line) do
    case Jason.decode(line) do
      {:ok, %{} = record} -> [record]
      _ -> []
    end
  end

  defp find_first(records, key) do
    Enum.find_value(records, fn r -> Map.get(r, key) end)
  end

  defp find_model(records) do
    Enum.find_value(records, fn
      %{"message" => %{"model" => model}} when is_binary(model) -> model
      _ -> nil
    end)
  end

  # Claude Code emits user / assistant records with a `message` field
  # shaped like `%{"role" => "user", "content" => string | [blocks]}`.
  defp record_to_messages(%{"type" => "user", "message" => %{"content" => content} = msg} = r) do
    text = extract_text(content)

    if text == "" do
      []
    else
      [%{role: "user", content: text, timestamp: r["timestamp"], model: msg["model"]}]
    end
  end

  defp record_to_messages(
         %{"type" => "assistant", "message" => %{"content" => content} = msg} = r
       ) do
    text = extract_text(content)

    if text == "" do
      []
    else
      [%{role: "assistant", content: text, timestamp: r["timestamp"], model: msg["model"]}]
    end
  end

  # Tool results / side-channel records — skip by default.
  defp record_to_messages(_), do: []

  defp extract_text(content) when is_binary(content), do: String.trim(content)

  defp extract_text(content) when is_list(content) do
    content
    |> Enum.map(&block_to_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
    |> String.trim()
  end

  defp extract_text(_), do: ""

  defp block_to_text(%{"type" => "text", "text" => t}) when is_binary(t), do: t
  defp block_to_text(%{"type" => "thinking"}), do: ""

  defp block_to_text(%{"type" => "tool_use", "name" => name, "input" => input}) do
    "`[tool: #{name}]` `#{Jason.encode!(input)}`"
  end

  defp block_to_text(%{"type" => "tool_result", "content" => c}) when is_binary(c) do
    "```tool-result\n#{c}\n```"
  end

  defp block_to_text(%{"type" => "tool_result", "content" => c}) when is_list(c) do
    extract_text(c)
  end

  defp block_to_text(%{"text" => t}) when is_binary(t), do: t
  defp block_to_text(_), do: ""

  defp project_slug_from_path(path, cwd) do
    cond do
      is_binary(cwd) and cwd != "" -> cwd |> Path.basename() |> slugify()
      true -> path |> Path.dirname() |> Path.basename() |> decode_project_dir() |> slugify()
    end
  end

  # `-Users-naledi-Projects-hypha` -> `hypha`
  defp decode_project_dir("-" <> rest), do: rest |> String.split("-") |> List.last() |> to_string()
  defp decode_project_dir(other), do: other

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

  defp subagent?(path) do
    String.contains?(path, "subagents/") or String.starts_with?(Path.basename(path), "agent-")
  end

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
