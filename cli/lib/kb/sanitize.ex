defmodule Kb.Sanitize do
  @moduledoc """
  Content sanitization for ingested sources.

  Prevents injection attacks through the wiki layer:
  - Escapes the human-notes marker to prevent page splitting
  - Strips dangerous URI schemes
  - Strips raw HTML tags
  """

  @marker "<!-- human notes below -->"
  @escaped_marker "<!-- human notes below (escaped) -->"

  @dangerous_schemes ~r/(javascript|data|vbscript):/i

  @doc """
  Sanitize markdown content before storing in kb/raw/ or wiki/sources/.
  """
  def sanitize(content) when is_binary(content) do
    content
    |> escape_marker()
    |> strip_dangerous_uris()
    |> strip_html_tags()
  end

  @doc "Escape the edit protection marker in source content."
  def escape_marker(content) do
    String.replace(content, @marker, @escaped_marker)
  end

  @doc "Remove javascript:, data:, vbscript: URI schemes from links."
  def strip_dangerous_uris(content) do
    # Match markdown links with dangerous schemes
    Regex.replace(
      ~r/\[([^\]]*)\]\((?:javascript|data|vbscript):[^)]*\)/i,
      content,
      "[\\1](removed-dangerous-uri)"
    )
  end

  @doc "Strip HTML tags from content."
  def strip_html_tags(content) do
    Regex.replace(~r/<[^>]+>/, content, "")
  end
end
