defmodule KB.Sessions.Redactor do
  @moduledoc """
  Redaction pipeline for session transcripts.

  Strips common secrets and PII before writing transcripts to disk:

  - API keys matching `sk-[A-Za-z0-9]{20,}`          -> `[REDACTED_API_KEY]`
  - GitHub tokens matching `ghp_[A-Za-z0-9]{36}`     -> `[REDACTED_GH_TOKEN]`
  - Named credentials (api_key, secret, token, ...)  -> `[REDACTED_CREDENTIAL]`
  - Email addresses                                  -> `[REDACTED_EMAIL]`
  - The literal value of `System.get_env("USER")`    -> `USER`
  - Any extra patterns configured under
    `kb.config.json: ingest.redaction.extra_patterns: [...]`
  """

  @api_key_re ~r/sk-[A-Za-z0-9]{20,}/
  @gh_token_re ~r/ghp_[A-Za-z0-9]{36}/
  # Match `api_key: ...`, `api-key = ...`, `token: "..."` etc.
  # The negative lookahead on `[REDACTED_` prevents re-consuming values we've
  # already scrubbed in an earlier pipeline stage.
  @named_cred_re ~r/(?i)(api[_-]?key|secret|token|bearer|password)[\"'\s:=]+(?!\[REDACTED_)[^\s\"']+/
  # Simple, liberal email regex. Matches foo.bar+baz@sub.example.co
  @email_re ~r/[\w.+\-]+@[\w\-]+\.[\w.\-]+/

  @type opts :: [extra_patterns: [String.t()], username: String.t() | nil]

  @doc """
  Apply the redaction pipeline to a binary.

  Accepts an opts keyword list:

  - `:extra_patterns` — list of regex strings (merged from config)
  - `:username`       — the current OS username; replaced with the literal
    string `USER`. Defaults to `System.get_env("USER")`.
  """
  @spec redact(String.t(), opts()) :: String.t()
  def redact(content, opts \\ []) when is_binary(content) do
    extra = Keyword.get(opts, :extra_patterns, [])
    username = Keyword.get(opts, :username, System.get_env("USER"))

    content
    |> replace(@api_key_re, "[REDACTED_API_KEY]")
    |> replace(@gh_token_re, "[REDACTED_GH_TOKEN]")
    |> replace(@named_cred_re, "[REDACTED_CREDENTIAL]")
    |> replace(@email_re, "[REDACTED_EMAIL]")
    |> replace_username(username)
    |> apply_extra_patterns(extra)
  end

  defp replace(content, re, replacement) do
    Regex.replace(re, content, replacement)
  end

  defp replace_username(content, nil), do: content
  defp replace_username(content, ""), do: content

  defp replace_username(content, username) when is_binary(username) do
    # Only replace standalone occurrences of the username — avoid clobbering
    # e.g. "username" or "user_naledi_dev". Use a word-boundary guard.
    re = Regex.compile!("\\b" <> Regex.escape(username) <> "\\b")
    Regex.replace(re, content, "USER")
  end

  defp apply_extra_patterns(content, []), do: content

  defp apply_extra_patterns(content, patterns) when is_list(patterns) do
    Enum.reduce(patterns, content, fn pattern, acc ->
      case Regex.compile(pattern) do
        {:ok, re} -> Regex.replace(re, acc, "[REDACTED_CUSTOM]")
        {:error, _} -> acc
      end
    end)
  end
end
