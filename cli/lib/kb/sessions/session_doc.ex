defmodule KB.Sessions.SessionDoc do
  @moduledoc """
  Canonical representation of a parsed agent session transcript.

  Adapters return `%SessionDoc{}` from `parse/1`. The renderer turns them
  into a markdown file under `kb/raw/sessions/<project>/YYYY-MM-DD-<slug>.md`.

  A `message` is a map shaped like:

      %{role: "user" | "assistant" | "tool" | "system",
        content: String.t(),
        timestamp: String.t() | nil}
  """

  @enforce_keys [:agent, :project, :session_id, :source_path, :messages]
  defstruct [
    :agent,
    :project,
    :session_id,
    :source_path,
    :started_at,
    :model,
    messages: [],
    metadata: %{}
  ]

  @type message :: %{
          required(:role) => String.t(),
          required(:content) => String.t(),
          optional(:timestamp) => String.t() | nil
        }

  @type t :: %__MODULE__{
          agent: String.t(),
          project: String.t(),
          session_id: String.t(),
          source_path: String.t(),
          started_at: String.t() | nil,
          model: String.t() | nil,
          messages: [message()],
          metadata: map()
        }
end
