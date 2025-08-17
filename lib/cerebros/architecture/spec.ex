defmodule Cerebros.Architecture.Spec do
  @moduledoc """
  Architecture specification structure and validation.

  This module defines the core data structures for representing neural network
  architectures in Cerebros, replacing the Python dictionary-based approach
  with proper Elixir structs and validation.
  """

  alias __MODULE__

  @type unit_type :: :dense | :real_neuron
  @type activation :: :relu | :elu | :tanh | :sigmoid | :leaky_relu | :gelu | :swish
  @type merge_strategy :: :concatenate | :add | :multiply

  @type connectivity_config :: %{
    required(:minimum_skip_connection_depth) => pos_integer(),
    required(:maximum_skip_connection_depth) => pos_integer(),
    required(:predecessor_affinity_factor_first) => float(),
    required(:predecessor_affinity_factor_main) => float(),
    required(:predecessor_affinity_factor_decay) => (non_neg_integer() -> float()),
    required(:lateral_connection_probability) => float(),
    required(:lateral_connection_decay) => (non_neg_integer() -> float()),
    required(:max_consecutive_lateral_connections) => pos_integer(),
    required(:gate_after_n_lateral_connections) => pos_integer(),
  optional(:gate_activation) => (number() -> number()),
  optional(:gating_mode) => :activation | :multiplicative
  }

  @type level_spec :: %{
    level_number: non_neg_integer(),
    unit_type: unit_type(),
    units: [unit_spec()],
    is_final: boolean()
  }

  @type unit_spec :: %{
    unit_id: non_neg_integer(),
    neurons: pos_integer(),
    activation: activation(),
    dendrites: pos_integer() | nil,  # Only for real_neuron type
    dendrite_activation: activation() | nil  # Only for real_neuron type
  }

  @type input_spec :: %{
    shape: tuple(),
    dtype: atom()
  }

  @derive {Jason.Encoder, only: [
    :trial_id,
    :seed,
    :input_specs,
    :output_shapes,
    :levels,
    :training_config,
    :metadata
  ]}
  defstruct [
    :trial_id,
    :seed,
    :input_specs,
    :output_shapes,
    :levels,
    :connectivity_config,
    :merge_config,
    :training_config,
    metadata: %{}
  ]

  @type t :: %Spec{
    trial_id: String.t(),
    seed: integer(),
    input_specs: [input_spec()],
    output_shapes: [pos_integer()],
    levels: [level_spec()],
    connectivity_config: connectivity_config(),
    merge_config: map() | nil,
    training_config: map(),
    metadata: map()
  }
  def new(opts) do
    with {:ok, validated_opts} <- validate_opts(opts) do
      spec = struct(Spec, validated_opts)
      {:ok, spec}
    end
  end

  @doc """
  Validates an architecture specification.
  """
  @spec validate(t()) :: :ok | {:error, [String.t()]}
  def validate(%Spec{} = spec) do
    errors = []

    errors =
      errors
      |> validate_connectivity_config(spec.connectivity_config)
      |> validate_levels(spec.levels)
      |> validate_level_ordering(spec.levels)
      |> validate_skip_depths(spec.levels, spec.connectivity_config)

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc """
  Generates a random architecture specification.
  """
  @spec random(connectivity_config(), keyword()) :: t()
  def random(connectivity_config, opts \\ []) do
    seed = Keyword.get(opts, :seed, :rand.uniform(1_000_000))
    _rng = :rand.seed(:exsss, {seed, seed + 1, seed + 2})

    min_levels = Keyword.get(opts, :min_levels, 2)
    max_levels = Keyword.get(opts, :max_levels, 6)
    min_units = Keyword.get(opts, :min_units_per_level, 1)
    max_units = Keyword.get(opts, :max_units_per_level, 4)
    min_neurons = Keyword.get(opts, :min_neurons_per_unit, 8)
    max_neurons = Keyword.get(opts, :max_neurons_per_unit, 256)

    num_levels = :rand.uniform(max_levels - min_levels + 1) + min_levels - 1

    rounding_strategy =
      opts
      |> Keyword.get(:round_neurons, :none)
      |> Cerebros.Architecture.Rounding.parse()

    unit_type = Keyword.get(opts, :unit_type, :dense)

    levels =
      0..(num_levels - 1)
      |> Enum.map(fn level_index ->
        is_final = level_index == num_levels - 1
        unit_count = :rand.uniform(max_units - min_units + 1) + min_units - 1

        units =
          0..(unit_count - 1)
          |> Enum.map(fn unit_id ->
            raw_neurons = :rand.uniform(max_neurons - min_neurons + 1) + min_neurons - 1
            neurons = Cerebros.Architecture.Rounding.round_neurons(raw_neurons, rounding_strategy)
            activation = random_activation()

            case unit_type do
              :dense ->
                %{
                  unit_id: unit_id,
                  neurons: neurons,
                  activation: activation,
                  dendrites: nil,
                  dendrite_activation: nil
                }
              :real_neuron ->
                dendrites = :rand.uniform(5) + 1
                %{
                  unit_id: unit_id,
                  neurons: neurons,
                  activation: activation,
                  dendrites: dendrites,
                  dendrite_activation: random_activation()
                }
            end
          end)

        %{
          level_number: level_index,
          unit_type: unit_type,
          units: units,
          is_final: is_final
        }
      end)

    %Spec{
      trial_id: Keyword.get(opts, :trial_id, generate_id()),
      seed: seed,
      input_specs: Keyword.get(opts, :input_specs, [%{shape: {784}, dtype: :f32}]),
      output_shapes: Keyword.get(opts, :output_shapes, [10]),
      levels: levels,
      connectivity_config: connectivity_config,
      merge_config: Keyword.get(opts, :merge_config, nil),
      training_config: Keyword.get(opts, :training_config, %{}),
      metadata: %{generated_at: DateTime.utc_now(), rounding_strategy: rounding_strategy}
    }
  end

  @doc """
  Convenience wrapper used by higher-level search code (CLI / Orchestrator)
  to generate a random Spec directly from a search param map. Mirrors the
  original Python API's generate_random(search_params) entry point while
  delegating to `random/2` for the actual generation.

  Recognised map keys (with defaults) – any others are forwarded as opts:
    :minimum_skip_connection_depth (1)
    :maximum_skip_connection_depth (7)
    :predecessor_affinity_factor_first (5.0)
    :predecessor_affinity_factor_main (0.7)
    :predecessor_affinity_factor_decay (fn depth -> :math.pow(0.9, depth) end)
    :lateral_connection_probability (0.2)
    :lateral_connection_decay (fn d -> :math.pow(0.95, d) end)
    :max_consecutive_lateral_connections (7)
    :gate_after_n_lateral_connections (3)
    :gate_activation (nil | atom() | fun)
  :gating_mode (:activation | :multiplicative) defaults to :activation
    :merge_strategy_pool ([:concatenate])
    :max_merge_width (nil)
    :projection_after_merge (true)
    :projection_activation (:relu)
  """
  @spec generate_random(map()) :: t()
  def generate_random(params) when is_map(params) do
    # Build connectivity config from provided map or defaults
    min_skip = Map.get(params, :minimum_skip_connection_depth, 1)
    max_skip = Map.get(params, :maximum_skip_connection_depth, 7)
    pre_first = Map.get(params, :predecessor_affinity_factor_first, 5.0)
    pre_main = Map.get(params, :predecessor_affinity_factor_main, 0.7)

    pre_decay_raw = Map.get(params, :predecessor_affinity_factor_decay,
      fn depth -> :math.pow(0.9, depth) end)
    pre_decay = Cerebros.Functions.Decay.resolve_decay(pre_decay_raw)

    lateral_prob = Map.get(params, :lateral_connection_probability, 0.2)
  lateral_decay_raw = Map.get(params, :lateral_connection_decay, fn d -> :math.pow(0.95, d) end)
  lateral_decay = Cerebros.Functions.Decay.resolve_decay(lateral_decay_raw)

    max_lat = Map.get(params, :max_consecutive_lateral_connections, 7)
    gate_after = Map.get(params, :gate_after_n_lateral_connections, 3)
  gate_activation = Map.get(params, :gate_activation, nil)
  gating_mode = Map.get(params, :gating_mode, :activation)

    connectivity_config = %{
      minimum_skip_connection_depth: min_skip,
      maximum_skip_connection_depth: max_skip,
      predecessor_affinity_factor_first: pre_first,
      predecessor_affinity_factor_main: pre_main,
  predecessor_affinity_factor_decay: pre_decay,
      lateral_connection_probability: lateral_prob,
      lateral_connection_decay: lateral_decay,
      max_consecutive_lateral_connections: max_lat,
      gate_after_n_lateral_connections: gate_after,
      gate_activation: normalize_gate_activation(gate_activation)
  |> ensure_not_nil_default(),
  gating_mode: gating_mode
    }

    # Merge config (width / merge strategy controls)
    merge_config = %{
      strategy_pool: Map.get(params, :merge_strategy_pool, [:concatenate]),
      max_merge_width: Map.get(params, :max_merge_width, nil),
      projection_after_merge: Map.get(params, :projection_after_merge, true),
      projection_activation: Map.get(params, :projection_activation, :relu)
    }

    seed = Map.get(params, :seed, :rand.uniform(1_000_000))

    # Forward remaining sizing / level params as opts to random/2
    random(connectivity_config,
      seed: seed,
      min_levels: Map.get(params, :minimum_levels, 1),
      max_levels: Map.get(params, :maximum_levels, 3),
      min_units_per_level: Map.get(params, :minimum_units_per_level, 1),
      max_units_per_level: Map.get(params, :maximum_units_per_level, 3),
      min_neurons_per_unit: Map.get(params, :minimum_neurons_per_unit, 4),
      max_neurons_per_unit: Map.get(params, :maximum_neurons_per_unit, 32),
      input_specs: build_input_specs(params),
      output_shapes: build_output_shapes(params),
      merge_config: merge_config,
      round_neurons: Map.get(params, :round_neurons, :none),
      unit_type: Map.get(params, :unit_type, :dense)
    )
  end

  defp build_input_specs(params) do
    case Map.get(params, :input_shapes, [{10}]) do
      shapes when is_list(shapes) -> Enum.map(shapes, &%{shape: &1, dtype: :f32})
      tuple when is_tuple(tuple) -> [%{shape: tuple, dtype: :f32}]
    end
  end

  defp build_output_shapes(params) do
    case Map.get(params, :output_shapes, [1]) do
      list when is_list(list) -> list
      single -> [single]
    end
  end

  defp normalize_gate_activation(nil), do: nil
  defp normalize_gate_activation(fun) when is_function(fun, 1), do: fun
  defp normalize_gate_activation(atom) when is_atom(atom) do
    case atom do
      :sigmoid -> &Axon.sigmoid/1
      :tanh -> &Axon.tanh/1
      :relu -> &Axon.relu/1
      :gelu -> &Axon.gelu/1
      :identity -> &Function.identity/1
      _ -> &Axon.sigmoid/1
    end
  end

  defp ensure_not_nil_default(nil), do: &Axon.sigmoid/1
  defp ensure_not_nil_default(fun) when is_function(fun, 1), do: fun

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  # Private functions

  defp validate_opts(opts) do
    required = [:input_specs, :output_shapes, :connectivity_config]

    case Enum.find(required, &(not Keyword.has_key?(opts, &1))) do
      nil -> {:ok, opts}
      missing -> {:error, "Missing required option: #{missing}"}
    end
  end

  defp validate_connectivity_config(errors, config) do
    cond do
      config.minimum_skip_connection_depth >= config.maximum_skip_connection_depth ->
        ["minimum_skip_connection_depth must be < maximum_skip_connection_depth" | errors]

      config.predecessor_affinity_factor_first <= 0 ->
        ["predecessor_affinity_factor_first must be positive" | errors]

      config.predecessor_affinity_factor_main <= 0 ->
        ["predecessor_affinity_factor_main must be positive" | errors]

      true -> errors
    end
  end

  defp validate_levels(errors, levels) do
    if Enum.empty?(levels) do
      ["Architecture must have at least one level" | errors]
    else
      errors
    end
  end

  defp validate_level_ordering(errors, levels) do
    level_numbers = Enum.map(levels, & &1.level_number)
    expected = Enum.sort(level_numbers)

    if level_numbers == expected do
      errors
    else
      ["Level numbers must be in ascending order" | errors]
    end
  end

  defp validate_skip_depths(errors, levels, config) do
    max_level = length(levels)

    if config.maximum_skip_connection_depth >= max_level do
      ["maximum_skip_connection_depth must be less than total levels" | errors]
    else
      errors
    end
  end

  defp random_activation do
    activations = [:relu, :elu, :tanh, :sigmoid, :leaky_relu, :gelu, :swish]
    Enum.random(activations)
  end
end
