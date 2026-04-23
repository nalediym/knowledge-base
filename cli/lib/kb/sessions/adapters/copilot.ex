defmodule KB.Sessions.Adapters.Copilot do
  @moduledoc """
  Stub adapter for GitHub Copilot Chat / CLI. Storage locations vary across
  VS Code extension storage and the Copilot CLI — TBD. Always reports
  `:not_installed` until a concrete path is wired in.
  """

  @behaviour KB.Sessions.Adapter

  alias KB.Sessions.SessionDoc

  @impl true
  def agent_name, do: "copilot"

  @impl true
  def detect, do: :not_installed

  @impl true
  def parse(_path), do: {:error, :not_implemented}

  @impl true
  def redact(%SessionDoc{} = doc), do: doc
end
