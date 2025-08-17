defmodule Cerebros.Architecture.SpecDeterminismTest do
  use ExUnit.Case, async: true

  alias Cerebros.Architecture.Spec

  # Provide named (remote) functions so we can reference them in the connectivity config
  defp decay_0_9(d), do: :math.pow(0.9, d)
  defp decay_0_95(d), do: :math.pow(0.95, d)

  defp connectivity_config do
    %{
      minimum_skip_connection_depth: 1,
      maximum_skip_connection_depth: 5,
      predecessor_affinity_factor_first: 5.0,
      predecessor_affinity_factor_main: 0.7,
      predecessor_affinity_factor_decay: &__MODULE__.decay_0_9/1,
      lateral_connection_probability: 0.2,
      lateral_connection_decay: &__MODULE__.decay_0_95/1,
      max_consecutive_lateral_connections: 3,
      gate_after_n_lateral_connections: 2
    }
  end

  test "Spec.random/2 produces identical structure for same seed + trial_id (excluding timestamp)" do
    cfg = connectivity_config()
    seed = 123_456
    fixed_trial_id = "fixed_trial"

    spec1 = Spec.random(cfg, seed: seed, trial_id: fixed_trial_id)
    spec2 = Spec.random(cfg, seed: seed, trial_id: fixed_trial_id)

    assert sanitize(spec1) == sanitize(spec2)
  end

  test "all levels have at least one unit" do
    cfg = connectivity_config()
    spec = Spec.random(cfg, seed: 999, trial_id: "t")

    Enum.each(spec.levels, fn level ->
      assert is_list(level.units)
      assert length(level.units) > 0
    end)
  end

  defp sanitize(%Spec{} = spec) do
    %{spec | metadata: Map.put(spec.metadata, :generated_at, nil)}
  end
end
