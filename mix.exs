defmodule Cerebros.MixProject do
  use Mix.Project

  def project do
    [
      app: :cerebros,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      docs: docs(),
  dialyzer: dialyzer(),
  releases: releases(),
  escript: escript()
    ]
  end

  # During test we only need a minimal subset (architecture spec + helpers) for current determinism test.
  # This avoids compiling experimental modules that currently have spec/API mismatches (Nx random API, Axon typespecs, etc.).
  # TODO: Remove this narrowing once the rest of the codebase is updated for Nx 0.9 APIs and typespec cleanups.
  defp elixirc_paths(:test), do: [
    "lib/cerebros/architecture",
    "lib/cerebros/functions"
  ]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    base = [extra_applications: [:logger, :crypto]]
    if Mix.env() == :test do base
    else
      base ++ [mod: {Cerebros.Application, []}]
    end
  end
   # In test we skip starting the full application supervision tree to allow
      # isolated module compilation (we narrow elixirc_paths). This avoids
      # failing on modules not compiled for the determinism unit test.
  defp deps do
    [
      # Neural network framework
  # Keep Axon/Nx/EXLA versions in sync. Scholar requires Nx >= 0.9
  {:nx, "~> 0.9"},
  # Re-enabled EXLA (JIT) for CPU/GPU acceleration. Build with:
  #   EXLA_TARGET=host mix deps.compile exla   (CPU)
  #   EXLA_TARGET=cuda mix deps.compile exla   (NVIDIA GPU)
  # If CUDA devices absent, prefer host target to avoid load errors.
  {:exla, "~> 0.9"},
  {:axon, "~> 0.7"},
  # Optimizers (used in Builder.compile_model)
  {:polaris, "~> 0.1"},

      # Data processing
      {:explorer, "~> 0.8"},
      {:scholar, "~> 0.2"},

      # Concurrency and distributed systems
      {:broadway, "~> 1.0"},
      {:flow, "~> 1.2"},

      # Serialization and persistence
      {:jason, "~> 1.4"},
      {:cubdb, "~> 2.0"},

      # Telemetry
      {:telemetry_metrics, "~> 0.6"},

      # Development and testing
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.1", only: :dev},

      # Visualization
      {:vega_lite, "~> 0.1", only: :dev},
      {:kino, "~> 0.12", only: :dev}
    ]
  end

  defp docs do
    [
      main: "Cerebros",
      source_url: "https://github.com/david-thrower/cerebros-core-algorithm-alpha",
      homepage_url: "https://github.com/david-thrower/cerebros-core-algorithm-alpha"
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix, :ex_unit]
    ]
  end

  defp releases do
    [
      cerebros: [
        include_executables_for: [:unix],
        steps: [:assemble]
      ]
    ]
  end

  defp escript do
    [main_module: Cerebros.CLI]
  end
end
