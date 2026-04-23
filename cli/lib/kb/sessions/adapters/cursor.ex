defmodule KB.Sessions.Adapters.Cursor do
  @moduledoc """
  Stub adapter for Cursor. Cursor stores chat history in SQLite
  (`~/Library/Application Support/Cursor/User/workspaceStorage/**`) which
  requires a SQLite driver we do not yet ship. Declares availability so
  the user sees the adapter exists, but parsing returns `:not_implemented`.
  """

  @behaviour KB.Sessions.Adapter

  alias KB.Sessions.SessionDoc

  @store Path.join([
           System.user_home!() || "",
           "Library/Application Support/Cursor/User/workspaceStorage"
         ])

  @impl true
  def agent_name, do: "cursor"

  @impl true
  def detect do
    if File.dir?(@store), do: {:ok, []}, else: :not_installed
  end

  @impl true
  def parse(_path), do: {:error, :not_implemented}

  @impl true
  def redact(%SessionDoc{} = doc), do: doc
end
