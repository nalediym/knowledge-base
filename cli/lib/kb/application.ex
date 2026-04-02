defmodule Kb.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Ingest worker pool — GenServer per source file
      {Task.Supervisor, name: Kb.IngestSupervisor}
    ]

    opts = [strategy: :one_for_one, name: Kb.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
