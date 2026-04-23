defmodule KB.Sessions.Adapters.GeminiCli do
  @moduledoc """
  Stub adapter for Gemini CLI. Session store layout under `~/.gemini/` is not
  yet normalised. Returns `:not_installed` when the directory is missing and
  a clean `{:error, :not_implemented}` when asked to parse.
  """

  @behaviour KB.Sessions.Adapter

  alias KB.Sessions.SessionDoc

  @store Path.join([System.user_home!() || "", ".gemini"])

  @impl true
  def agent_name, do: "gemini_cli"

  @impl true
  def detect do
    if File.dir?(@store) do
      {:ok, []}
    else
      :not_installed
    end
  end

  @impl true
  def parse(_path), do: {:error, :not_implemented}

  @impl true
  def redact(%SessionDoc{} = doc), do: doc
end
