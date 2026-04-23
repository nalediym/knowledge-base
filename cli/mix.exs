defmodule Kb.MixProject do
  use Mix.Project

  def project do
    [
      app: :kb,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript()
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
      {:yaml_elixir, "~> 2.11"}
    ]
  end
end
