defmodule KB.Sessions.Renderer do
  @moduledoc """
  Render a `SessionDoc` to markdown with frontmatter.
  Output shape matches the acceptance criteria:

      ---
      source_type: session
      agent: "claude_code"
      project: "hypha"
      session_id: "..."
      started_at: "..."
      model: "..."
      ---

      # Session: <project> / <date>

      ## 1. user (timestamp)
      ...

      ## 2. assistant (timestamp)
      ...
  """

  alias KB.Sessions.SessionDoc

  @spec render(SessionDoc.t()) :: String.t()
  def render(%SessionDoc{} = doc) do
    frontmatter = build_frontmatter(doc)
    body = build_body(doc)
    frontmatter <> "\n" <> body
  end

  defp build_frontmatter(doc) do
    fields = [
      {"source_type", "session"},
      {"agent", doc.agent},
      {"project", doc.project},
      {"session_id", doc.session_id},
      {"started_at", doc.started_at || ""},
      {"model", doc.model || ""},
      {"source_path", doc.source_path}
    ]

    lines =
      fields
      |> Enum.map(fn {k, v} -> "#{k}: #{yaml_string(v)}" end)
      |> Enum.join("\n")

    "---\n" <> lines <> "\n---\n"
  end

  defp build_body(doc) do
    title = "# Session: #{doc.project} / #{date_stamp(doc.started_at)}\n\n"

    turns =
      doc.messages
      |> Enum.with_index(1)
      |> Enum.map(&render_turn/1)
      |> Enum.join("\n\n")

    footer =
      "\n\n---\n> **Agent:** #{doc.agent} · **Session:** `#{doc.session_id}` · " <>
        "**Turns:** #{length(doc.messages)}\n"

    title <> turns <> footer
  end

  defp render_turn({%{role: role, content: content} = msg, idx}) do
    ts_fragment =
      case Map.get(msg, :timestamp) do
        nil -> ""
        "" -> ""
        ts -> " _(#{ts})_"
      end

    "## #{idx}. #{role}#{ts_fragment}\n\n#{content}"
  end

  @doc """
  Build the output path for a session under `kb/raw/sessions/`.
  """
  @spec output_path(String.t(), SessionDoc.t()) :: Path.t()
  def output_path(base \\ "kb/raw/sessions", %SessionDoc{} = doc) do
    dir = Path.join(base, doc.project)
    filename = "#{date_stamp(doc.started_at)}-#{session_slug(doc)}.md"
    Path.join(dir, filename)
  end

  @doc """
  Short, filename-safe slug for a session. Uses the first 8 chars of the
  session id when available.
  """
  def session_slug(%SessionDoc{session_id: id}) when is_binary(id) and id != "" do
    id
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]/, "")
    |> String.slice(0, 8)
    |> case do
      "" -> "session"
      s -> s
    end
  end

  def session_slug(_), do: "session"

  defp date_stamp(nil), do: Date.to_iso8601(Date.utc_today())
  defp date_stamp(""), do: Date.to_iso8601(Date.utc_today())

  defp date_stamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> Date.to_iso8601(DateTime.to_date(dt))
      _ -> String.slice(ts, 0, 10)
    end
  end

  defp yaml_string(v) when is_binary(v) do
    # Quote to be safe; escape embedded quotes.
    escaped = String.replace(v, "\"", "\\\"")
    "\"" <> escaped <> "\""
  end

  defp yaml_string(v), do: yaml_string(to_string(v))
end
