defmodule Cerebros.MixProject do
  use Mix.Project

  def project do
    [
      app: :cerebros,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      dialyzer: dialyzer()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Cerebros.Application, []}
    ]
  end

  defp deps do
    [
      {:nx, "~> 0.9"},
      {:exla, "~> 0.9"},
      {:axon, "~> 0.7"},
      {:explorer, "~> 0.8"},
      {:scholar, "~> 0.2"},
      {:broadway, "~> 1.0"},
      {:flow, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:cubdb, "~> 2.0"},
      {:telemetry_metrics, "~> 0.6"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.1", only: :dev},
      {:vega_lite, "~> 0.1", only: :dev},
      {:kino, "~> 0.12", only: :dev}
    ]
  end

  defp docs do
    [
      main: "Cerebros",
      source_url: "https://github.com/Thunderblok/cerebros",
      homepage_url: "https://github.com/Thunderblok/cerebros"
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix, :ex_unit]
    ]
  end
end
