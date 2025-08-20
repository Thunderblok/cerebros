defmodule Cerebros.Presets do
  @moduledoc """
  Convenience preset configurations migrated from legacy / experimental runs.

  These presets are intended to accelerate reproducing known-good search settings
  (e.g. from the original Python Cerebros / AutoML notebooks) while allowing callers
  to selectively override any individual option.

  Usage:
      iex> opts = Cerebros.Presets.preset(:ames_legacy_optima)
      iex> Cerebros.test_ames_housing_example(opts)

  Or merging into an existing keyword list:
      iex> my_opts = Cerebros.Presets.apply_preset([search_profile: :balanced], :ames_legacy_optima)
      iex> Cerebros.test_full_nas_run(my_opts)

  NOTES:
  * Very large connectivity affinity factors (e.g. 15.0) may bias skip/lateral connection density.
    Adjust downward if graphs become oversized for CPU-only environments.
  * Batch size 93 from legacy run is kept for fidelity; you may round to nearest power of two (e.g. 96/128)
    if you prefer more regular memory alignment – especially on GPU.
  * Presets do not force a specific :search_profile; you can still supply one which will further
    shape breadth/depth unless you explicitly override those knobs post-merge.
  """

  @type preset_name :: :ames_legacy_optima

  @doc """
  Return keyword list for a named preset.
  Raises on unknown preset.
  """
  @spec preset(preset_name) :: keyword
  def preset(:ames_legacy_optima) do
    [
      # Architecture scale
      minimum_levels: 2,
      maximum_levels: 7,
      minimum_units_per_level: 1,
      maximum_units_per_level: 4,
      minimum_neurons_per_unit: 1,
      maximum_neurons_per_unit: 4,
      minimum_skip_connection_depth: 1,
      maximum_skip_connection_depth: 7,
      # Connectivity affinity factors
      predecessor_affinity_factor_first: 15.0313,
      predecessor_affinity_factor_main: 10.046,
      # Lateral connectivity dynamics
      max_consecutive_lateral_connections: 23,
      lateral_connection_probability: 0.19668,
      num_lateral_connection_tries_per_unit: 20,
      gate_after_n_lateral_connections: 3,
      gate_activation: :sigmoid,
      gating_mode: :multiplicative,
      # Training hyperparameters
      activation: :elu,
      learning_rate: 0.0664,
      epochs: 96,
      batch_size: 93,
      # Ranking / objective context
      direction: :minimize,
      metric_to_rank_by: :validation_loss
    ]
  end

  def preset(other), do: raise(ArgumentError, "Unknown preset #{inspect(other)}")

  @doc """
  Merge a preset into an existing keyword options list.

  Existing keys in `opts` take precedence unless `override: true` provided.
  """
  @spec apply_preset(keyword, preset_name, keyword) :: keyword
  def apply_preset(opts, name, opts2 \\ []) do
    override? = Keyword.get(opts2, :override, false)
    base = preset(name)
    if override? do
      Keyword.merge(base, opts, fn _k, _v1, v2 -> v2 end)
    else
      Keyword.merge(opts, base, fn _k, v1, _v2 -> v1 end)
    end
  end
end
