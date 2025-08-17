defmodule Cerebros.Application do
  @moduledoc """
  Main application supervisor for Cerebros neural architecture search.

  Starts the supervision tree with fault-tolerant processes for:
  - Search coordination
  - Trial worker pool management
  - Telemetry collection
  - Result persistence
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Core workers and supervisors
      # {Cerebros.Training.Orchestrator, []},
      # {Cerebros.Results.Collector, []},

      # Telemetry - disabled for now
      # {Telemetry.Supervisor, telemetry_config()},
    ]

    opts = [strategy: :one_for_one, name: Cerebros.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp telemetry_config do
    [
      # For now, we'll disable telemetry metrics to get the system running
      # metrics: metrics(),
      # reporter: :console
    ]
  end

  defp metrics do
    [
      # Trial metrics
      Telemetry.Metrics.counter("cerebros.trial.started"),
      Telemetry.Metrics.counter("cerebros.trial.completed"),
      Telemetry.Metrics.counter("cerebros.trial.failed"),
      Telemetry.Metrics.distribution("cerebros.trial.duration"),

      # Architecture metrics
      Telemetry.Metrics.distribution("cerebros.architecture.levels"),
      Telemetry.Metrics.distribution("cerebros.architecture.units_per_level"),
      Telemetry.Metrics.distribution("cerebros.architecture.total_parameters"),

      # Training metrics
      Telemetry.Metrics.distribution("cerebros.training.loss"),
      Telemetry.Metrics.distribution("cerebros.training.accuracy"),
      Telemetry.Metrics.distribution("cerebros.training.epochs")
    ]
  end
end
