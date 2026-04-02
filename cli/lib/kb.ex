defmodule Kb do
  @moduledoc """
  LLM-compiled knowledge base CLI.

  Ingest raw sources, compile them into an interlinked markdown wiki,
  then query, lint, and output against it.
  """

  @version "0.1.0"

  def version, do: @version
end
