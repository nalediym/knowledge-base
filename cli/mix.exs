defmodule Kb.MixProject do
  use Mix.Project

  def project do
    [
      app: :kb,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      test_ignore_filters: [&String.starts_with?(&1, "test/support/")]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :xmerl],
      mod: {Kb.Application, []}
    ]
  end

  defp escript do
    [main_module: Kb.CLI]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.11"},
      # Bare SQLite driver (no Ecto overhead). Needed for FTS5 hybrid retrieval.
      {:exqlite, "~> 0.36"},
      {:plug, "~> 1.16"},
      {:plug_cowboy, "~> 2.7"}
    ]
  end
end
