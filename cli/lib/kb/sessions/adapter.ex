defmodule KB.Sessions.Adapter do
  @moduledoc """
  Behaviour for agent session-transcript adapters.

  Each adapter knows three things about one coding agent:

    1. `detect/0` — whether the agent is installed on this machine, and if so
       which session files are available.
    2. `parse/1` — how to read one session file into a canonical `SessionDoc`.
    3. `redact/1` — how to strip secrets / PII from a `SessionDoc` before it
       gets written to `kb/raw/`.

  Adapters should be pure: no I/O outside `detect/0` and `parse/1`. Keep parse
  resilient — log and skip unknown record types rather than crashing the run.
  """

  alias KB.Sessions.SessionDoc

  @type session_path :: Path.t()

  @doc """
  Detect whether this agent's session store is available on this machine.

  Returns `{:ok, [session_path]}` with a (possibly empty) list of session
  files, or `:not_installed` if the agent's store directory does not exist.
  """
  @callback detect() :: {:ok, [session_path()]} | :not_installed

  @doc """
  Parse one session file into a `SessionDoc`.
  """
  @callback parse(session_path()) :: {:ok, SessionDoc.t()} | {:error, term()}

  @doc """
  Redact secrets and PII from a `SessionDoc`. Called after `parse/1` and
  before rendering to disk.
  """
  @callback redact(SessionDoc.t()) :: SessionDoc.t()

  @doc """
  Agent name (e.g. `"claude_code"`, `"codex_cli"`). Used for manifest
  entries and output paths.
  """
  @callback agent_name() :: String.t()
end
