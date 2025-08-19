defmodule Cerebros.Networks.Builder do
  @moduledoc """
  Builds Axon neural networks from architecture specifications and connectivity patterns.

  This module materializes the abstract architecture and connectivity into concrete
  Axon computational graphs, handling both Dense and RealNeuron variants through
  a unified interface.
  """

  alias Cerebros.Architecture.Spec
  require Logger
  alias Cerebros.Connectivity.Builder, as: ConnectivityBuilder

  @type axon_model :: Axon.t()
  @type layer_map :: %{
    {level :: non_neg_integer(), unit :: non_neg_integer()} => Axon.t()
  }

  @doc """
  Builds an Axon model from an architecture specification.
  """
  @spec build_model(Spec.t()) :: {:ok, axon_model()} | {:error, String.t()}
  def build_model(%Spec{} = spec) do
    with {:ok, connectivity} <- ConnectivityBuilder.build_connectivity(spec) do
      try do
        model = do_build_model(spec, connectivity)
        {:ok, model}
      rescue
        error ->
          stacktrace = __STACKTRACE__
          Logger.error("Model build failed: #{Exception.message(error)}\n" <>
                        Enum.map_join(stacktrace, "\n", &Exception.format_stacktrace_entry/1))
          {:error, Exception.message(error)}
      end
    end
  end

  # Private functions

  defp do_build_model(spec, connectivity) do
    # Stash gate activation function (if any) for downstream gather_input_layers.
    gate_activation =
      case Map.get(spec.connectivity_config, :gate_activation, nil) do
        fun when is_function(fun, 1) -> fun
        nil -> nil
        other when is_atom(other) ->
          # Map simple atom activations to Axon functions
          case other do
            :sigmoid -> &Axon.sigmoid/1
            :tanh -> &Axon.tanh/1
            :relu -> &Axon.relu/1
            :gelu -> &Axon.gelu/1
            :identity -> &Function.identity/1
            _ -> &Axon.sigmoid/1
          end
        _ -> nil
      end
    Process.put({:cerebros, :gate_activation}, gate_activation)
  Process.put({:cerebros, :gating_mode}, Map.get(spec.connectivity_config, :gating_mode, :activation))

    # Build input layers
    {input_layers, layer_map} = build_input_layers(spec)

    # Build hidden layers level by level
    {final_layers, _final_map} =
      spec.levels
      |> Enum.filter(&(&1.level_number > 0))
      |> Enum.reduce({input_layers, layer_map}, fn level, {layers, map} ->
        build_level(level, spec, connectivity, layers, map)
      end)

    # Handle multiple outputs if needed
    case final_layers do
      [] -> raise "No layers built for model"
      [single_output] -> ensure_output_shape(single_output, spec)
      multiple_outputs ->
        merged = merge_inputs(multiple_outputs, :concatenate)
        ensure_output_shape(merged, spec)
    end
  end

  defp build_input_layers(spec) do
    input_layers =
      spec.input_specs
      |> Enum.with_index()
      |> Enum.map(fn {input_spec, idx} ->
  shape = ensure_dynamic_batch(input_spec.shape)
  Axon.input("input_#{idx}", shape: shape)
      end)

    # Create initial layer map for input layers
    layer_map =
      input_layers
      |> Enum.with_index()
      |> Enum.into(%{}, fn {layer, idx} ->
        {{0, idx}, layer}
      end)

    {input_layers, layer_map}
  end

  # Ensure first dimension is dynamic (nil) so varying final batch sizes don't crash
  defp ensure_dynamic_batch(shape_tuple) when is_tuple(shape_tuple) do
    shape_list = Tuple.to_list(shape_tuple)
    case shape_list do
      [nil | _] -> shape_tuple
      _ -> List.to_tuple([nil | shape_list])
    end
  end
  defp ensure_dynamic_batch(other), do: other

  defp build_level(level, spec, connectivity, _prev_layers, layer_map) do
    # Build all units in this level
    {level_layers, updated_map} =
      level.units
      |> Enum.reduce({[], layer_map}, fn unit, {layers, map} ->
        unit_layer = build_unit(unit, level, spec, connectivity, map)
        unit_key = {level.level_number, unit.unit_id}

        {[unit_layer | layers], Map.put(map, unit_key, unit_layer)}
      end)

    {Enum.reverse(level_layers), updated_map}
  end

  defp build_unit(unit, level, spec, connectivity, layer_map) do
    unit_key = {level.level_number, unit.unit_id}
    connections = Map.get(connectivity, unit_key, %{})

    # Gather input layers from predecessors and laterals
    input_layers = gather_input_layers(connections, layer_map)

    if input_layers == [] do
      # Fallback: connect to all inputs (level 0) to avoid empty merge
      input_layers =
        layer_map
        |> Enum.filter(fn {{lvl, _uid}, _layer} -> lvl == 0 end)
        |> Enum.map(fn {_k, layer} -> layer end)

      if input_layers == [] do
        raise "No input layers available to build unit #{inspect(unit_key)}"
      end
    end

    # Determine merge strategy from spec.merge_config.strategy_pool (random pick for diversity)
    {strategy, merged_input, input_count} =
      case input_layers do
        [] -> raise "No input layers available for merge"
        [single] -> {:identity, single, 1}
        many ->
          merge_cfg = spec.merge_config || %{}
          pool = Map.get(merge_cfg, :strategy_pool, [:concatenate])
          chosen = Enum.random(pool)
          {chosen, merge_inputs(many, chosen), length(many)}
      end

    # Optionally cap width via projection layer only if multiple inputs actually merged
    merged_input = maybe_project_after_merge(merged_input, spec, strategy, input_count)

    # Apply batch normalization or dropout
  # Temporarily disable batch norm (issues on 1D inputs causing arithmetic errors)
  normalized = merged_input

  Logger.debug("Building unit #{inspect(unit_key)} neurons=#{unit.neurons} inputs=#{length(List.wrap(merged_input))}")

    # Build the unit based on type
    case level.unit_type do
      :dense -> build_dense_unit(normalized, unit, level)
      :real_neuron -> build_real_neuron_unit(normalized, unit, level)
      :positronic -> build_positronic_unit(normalized, unit, level)
    end
  end

  defp gather_input_layers(%{predecessors: _, laterals: _, gated_laterals: _} = connections, layer_map) do
    all_connections = connections.predecessors ++ connections.laterals

    base_layers =
      all_connections
      |> Enum.map(fn {lvl, uid} = key ->
        case Map.get(layer_map, key) do
          nil ->
            # Fallback: if referencing level 0 unit id that is not in map, map to existing input layer by index wrap
            if lvl == 0 do
              input_layers =
                layer_map
                |> Enum.filter(fn {{l, _}, _} -> l == 0 end)
                |> Enum.sort_by(fn {{_l, u}, _} -> u end)
                |> Enum.map(fn {_k, layer} -> layer end)

              case input_layers do
                [] -> nil
                inputs -> Enum.at(inputs, rem(uid, length(inputs)))
              end
            else
              nil
            end
          layer -> layer
        end
      end)
      |> Enum.reject(&is_nil/1)

    gate_fun = fetch_gate_activation(layer_map) || &Axon.sigmoid/1
    gating_mode = Process.get({:cerebros, :gating_mode}, :activation)

    gated_layers =
      connections.gated_laterals
      |> Enum.map(&Map.get(layer_map, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn lateral ->
        case gating_mode do
          :multiplicative ->
            gate = safe_gate(gate_fun, lateral)
            Axon.multiply(lateral, gate)
          _ -> safe_gate(gate_fun, lateral)
        end
      end)

    candidate_layers = base_layers ++ gated_layers

    if candidate_layers == [] do
      # Final fallback: use all input layers
      layer_map
      |> Enum.filter(fn {{lvl, _}, _} -> lvl == 0 end)
      |> Enum.map(fn {_k, layer} -> layer end)
    else
      candidate_layers
    end
  end
  defp gather_input_layers(_connections, _layer_map), do: []

  # Walk layer_map (which includes input layers) to locate a spec reference that was
  # captured earlier via process dictionary when building model. We store gate activation
  # in the process dictionary before building to avoid threading spec through all helpers.
  defp fetch_gate_activation(_layer_map) do
    Process.get({:cerebros, :gate_activation})
  end

  # Wrap gate function to guard against extreme numeric excursions. We insert an
  # Axon element-wise clamp prior to applying gate_fun when it's a standard
  # activation susceptible to overflow (e.g., sigmoid via large exp()). Since
  # Axon activations take tensors, we build a small anonymous wrapper.
  defp safe_gate(gate_fun, lateral) when is_function(gate_fun, 1) do
    # Apply a dense identity if lateral is not yet projected? For now just clamp.
  clamped = Axon.nx(lateral, fn x -> Nx.clip(x, -40.0, 40.0) end, name: :gate_clamp)
    gate_fun.(clamped)
  end
  defp safe_gate(_other, lateral), do: lateral

  defp merge_inputs([], _strategy), do: raise("Attempted to merge empty input set")
  defp merge_inputs([single_input], _strategy), do: single_input
  defp merge_inputs(inputs, :concatenate) do
    # Axon.concatenate expects two layers, so reduce pairwise
    [first | rest] = inputs
  Enum.reduce(rest, first, fn layer, acc -> Axon.concatenate(acc, layer, axis: -1) end)
  end
  defp merge_inputs(inputs, :add) do
    Enum.reduce(inputs, &Axon.add(&2, &1))
  end
  defp merge_inputs(inputs, :multiply) do
    Enum.reduce(inputs, &Axon.multiply(&2, &1))
  end
  defp merge_inputs(input, :identity), do: input

  # Insert projection if width exceeds max_merge_width
  defp maybe_project_after_merge(layer, spec, strategy, input_count) do
    merge_cfg = spec.merge_config || %{}
    max_width = Map.get(merge_cfg, :max_merge_width)
    project? = Map.get(merge_cfg, :projection_after_merge, true)
    activation = Map.get(merge_cfg, :projection_activation, :relu)

    cond do
      max_width == nil or strategy == :identity or not project? or input_count < 2 -> layer
      true ->
        # We can't know static width easily without introspecting Axon graph (not public),
        # so we optimistically always project when max_width is set and strategy produced >1 inputs.
        # This keeps parameter growth bounded.
        act = get_activation_fn(activation)
        try do
          layer |> Axon.dense(max_width, name: "merge_projection") |> act.()
        rescue e ->
          Logger.warning("Projection layer insertion failed: #{Exception.message(e)}")
          layer
        end
    end
  end

  # Normalization helpers kept for future use (currently disabled to reduce numerical issues on small tensors)
  # defp apply_normalization(input, :batch_norm), do: Axon.batch_norm(input)
  # defp apply_normalization(input, :layer_norm), do: Axon.layer_norm(input)
  # defp apply_normalization(input, :dropout), do: Axon.dropout(input, rate: 0.2)
  # defp apply_normalization(input, :none), do: input

  defp build_dense_unit(input, unit, level) do
    activation = get_activation_fn(unit.activation)

    if level.is_final do
      # Final layer typically has no activation or specific output activation
      try do
  Axon.dense(input, unit.neurons, name: "dense_#{level.level_number}_#{unit.unit_id}")
      rescue e ->
        raise "Failed to build FINAL dense unit #{level.level_number}:#{unit.unit_id} neurons=#{unit.neurons} reason=#{Exception.message(e)}"
      end
    else
      try do
  Logger.debug("Entering dense build l=#{level.level_number} u=#{unit.unit_id} neurons=#{unit.neurons}")
        input
        |> Axon.dense(unit.neurons, name: "dense_#{level.level_number}_#{unit.unit_id}")
        |> activation.()
      rescue e ->
        raise "Failed to build dense unit #{level.level_number}:#{unit.unit_id} neurons=#{unit.neurons} reason=#{Exception.message(e)}"
      end
    end
  end

  defp build_real_neuron_unit(input, unit, level) do
    # Build axon (main processing unit)
    axon_activation = get_activation_fn(unit.activation)

    axon =
      input
      |> Axon.dense(unit.neurons, name: "axon_#{level.level_number}_#{unit.unit_id}")
      |> axon_activation.()

    # Build dendrites (output terminals)
    dendrite_activation = get_activation_fn(unit.dendrite_activation || unit.activation)
    dendrite_count = unit.dendrites || 1

    if level.is_final do
      # For final layer, dendrites are the actual outputs
      dendrites =
        1..dendrite_count
        |> Enum.map(fn dendrite_id ->
          per_dendrite = max(1, div(unit.neurons + dendrite_count - 1, dendrite_count))
          Axon.dense(axon, per_dendrite,
                     name: "dendrite_#{level.level_number}_#{unit.unit_id}_#{dendrite_id}")
        end)

      case dendrites do
        [single_dendrite] -> single_dendrite
        multiple_dendrites ->
          [first | rest] = multiple_dendrites
          Enum.reduce(rest, first, fn layer, acc -> Axon.concatenate(acc, layer, axis: -1) end)
      end
    else
      # For hidden layers, dendrites feed into next level
      dendrites =
        1..dendrite_count
        |> Enum.map(fn dendrite_id ->
          per_dendrite = max(1, div(unit.neurons + dendrite_count - 1, dendrite_count))
          axon
          |> Axon.dense(per_dendrite,
                        name: "dendrite_#{level.level_number}_#{unit.unit_id}_#{dendrite_id}")
          |> dendrite_activation.()
        end)

      # Combine dendrites
      case dendrites do
        [single_dendrite] -> single_dendrite
        multiple_dendrites ->
          [first | rest] = multiple_dendrites
          Enum.reduce(rest, first, fn layer, acc -> Axon.concatenate(acc, layer, axis: -1) end)
      end
    end
  end

  defp build_positronic_unit(input, unit, level) do
    # Positronic: two-phase transform: core + resonance modulation over concatenated dendrites.
    activation = get_activation_fn(unit.activation)
    core =
      input
      |> Axon.dense(unit.neurons, name: "positronic_core_#{level.level_number}_#{unit.unit_id}")
      |> activation.()

    dendrite_count = unit.dendrites || 1
    dendrite_activation = get_activation_fn(unit.dendrite_activation || unit.activation)

    dendrites =
      1..dendrite_count
      |> Enum.map(fn d_id ->
        share = max(1, div(unit.neurons + dendrite_count - 1, dendrite_count))
        core
        |> Axon.dense(share, name: "positronic_branch_#{level.level_number}_#{unit.unit_id}_#{d_id}")
        |> dendrite_activation.()
      end)

    merged =
      case dendrites do
        [single] -> single
        many -> merge_inputs(many, :concatenate)
      end

    modulated = apply_resonance(merged, unit)

    if level.is_final do
      # Final projection remains as-is; Axon model builder will still enforce final output shape.
      modulated
    else
      modulated
    end
  end

  defp apply_resonance(layer, %{resonance: nil}), do: layer
  # Legacy resonance names (:phi_harmonics, :golden_gate) mapped to neutral terms
  defp apply_resonance(layer, %{resonance: :phi_harmonics}), do: apply_resonance(layer, %{resonance: :multi_scale_modulation})
  defp apply_resonance(layer, %{resonance: :golden_gate}), do: apply_resonance(layer, %{resonance: :gated_nonlinearity})
  defp apply_resonance(layer, %{resonance: :multi_scale_modulation}) do
    Axon.nx(layer, fn x ->
      base = (1 + :math.sqrt(5.0)) / 2.0
      scales = Nx.tensor([1.0, base, base * base])
      shape = Nx.shape(x)
      # flatten trailing dims except batch
      rank = tuple_size(shape)
  {_batch, flat_shape, restore} =
        case rank do
          2 -> {elem(shape, 0), {elem(shape, 0), elem(shape, 1)}, fn y -> y end}
          _ ->
            batch = elem(shape, 0)
            flat = Enum.reduce(1..(rank-1), 1, fn i, acc -> acc * elem(shape, i) end)
            {batch, {batch, flat}, fn y -> Nx.reshape(y, shape) end}
        end
      x2d = Nx.reshape(x, flat_shape)
      cols = elem(Nx.shape(x2d), 1)
      reps = div(cols + 2, 3)
      full = Nx.tile(scales, [reps]) |> Nx.slice_along_axis(0, cols)
      mod = Nx.sin(x2d * full)
      restore.(mod)
    end, name: :multi_scale_modulation)
  end
  defp apply_resonance(layer, %{resonance: :gated_nonlinearity}) do
    Axon.nx(layer, fn x ->
      # Fast GELU approx: 0.5 * x * (1 + erf(x / sqrt(2)))
      gelu = 0.5 * x * (1.0 + Nx.erf(x / :math.sqrt(2.0)))
      gate = Nx.sigmoid(gelu)
      gate * x
    end, name: :gated_nonlinearity)
  end
  defp apply_resonance(layer, %{resonance: fun}) when is_function(fun, 1) do
    Axon.nx(layer, fn x ->
      try do
        fun.(x)
      rescue _ -> x
      end
    end, name: :custom_resonance)
  end

  defp get_activation_fn(:relu), do: &Axon.relu/1
  defp get_activation_fn(:elu), do: &Axon.elu/1
  defp get_activation_fn(:tanh), do: &Axon.tanh/1
  defp get_activation_fn(:sigmoid), do: &Axon.sigmoid/1
  defp get_activation_fn(:leaky_relu), do: fn x -> Axon.leaky_relu(x, alpha: 0.01) end
  defp get_activation_fn(:gelu), do: &Axon.gelu/1
  # Swish may be renamed (e.g. to SiLU) in newer Axon versions; fall back gracefully
  defp get_activation_fn(:swish), do: &Axon.gelu/1
  defp get_activation_fn(nil), do: &Function.identity/1

  # Force final output shape to {batch, 1} for current regression NAS test
  defp ensure_output_shape(model, spec) do
    # If spec declares single output of size 1 we enforce a projection
    cond do
      match?([1], spec.output_shapes) ->
        Axon.dense(model, 1, name: "final_projection")
      true -> model
    end
  end

  @doc """
  Compiles an Axon model with specified training configuration.
  """
  @spec compile_model(axon_model(), map()) :: Axon.Loop.t()
  def compile_model(model, training_config \\ %{}) do
    optimizer = get_optimizer(training_config)
    loss_fn = get_loss_function(training_config)
  metrics = get_metrics(training_config)

  loop = Axon.Loop.trainer(model, loss_fn, optimizer)
  Enum.reduce(metrics, loop, fn metric, acc -> attach_metric(acc, metric) end)
  end

  defp get_optimizer(config) do
    lr = Map.get(config, :learning_rate, 0.001)
    case Map.get(config, :optimizer, :adam) do
      :adamw -> Polaris.Optimizers.adamw(learning_rate: lr)
      :adam -> Polaris.Optimizers.adam(learning_rate: lr)
      :sgd -> Polaris.Optimizers.sgd(learning_rate: lr)
      :rmsprop -> Polaris.Optimizers.rmsprop(learning_rate: lr)
      other -> raise "Unsupported optimizer #{inspect(other)}"
    end
  end

  defp get_loss_function(config) do
    case Map.get(config, :loss, :categorical_crossentropy) do
  # Always wrap losses with reduction: :mean so trainer gets scalar loss
  :categorical_crossentropy -> fn y_pred, y_true ->
    Axon.Losses.categorical_cross_entropy(y_pred, y_true, reduction: :mean)
  end
  :sparse_categorical_crossentropy -> fn y_pred, y_true ->
    Axon.Losses.categorical_cross_entropy(y_pred, y_true, reduction: :mean)
  end
  :mean_squared_error -> fn y_pred, y_true ->
    Axon.Losses.mean_squared_error(y_pred, y_true, reduction: :mean)
  end
  :binary_crossentropy -> fn y_pred, y_true ->
    Axon.Losses.binary_cross_entropy(y_pred, y_true, reduction: :mean)
  end
    end
  end

  defp get_metrics(config) do
    Map.get(config, :metrics, [])
  end

  # Attach a metric which may be:
  #   * an atom referencing Axon.Metrics.<metric>
  #   * :mean_squared_error (not provided by Axon.Metrics) -> wrap Axon.Losses.mean_squared_error
  #   * {name, fun} where fun is arity-2 (y_true, y_pred)
  defp attach_metric(loop, :mean_squared_error) do
    mse = fn y_true, y_pred -> Axon.Losses.mean_squared_error(y_true, y_pred, reduction: :mean) end
    Axon.Loop.metric(loop, mse, "mean_squared_error")
  end
  defp attach_metric(loop, {name, fun}) when is_function(fun, 2) do
    Axon.Loop.metric(loop, fun, to_string(name))
  end
  defp attach_metric(loop, metric_atom) when is_atom(metric_atom) do
    Axon.Loop.metric(loop, metric_atom)
  end
  defp attach_metric(loop, _unknown), do: loop

  # Custom metrics attachment (retained for future extension)
  # defp add_custom_metrics(loop, []), do: loop
  # defp add_custom_metrics(loop, [metric | rest]) do
  #   loop
  #   |> Axon.Loop.metric(metric)
  #   |> add_custom_metrics(rest)
  # end

  @doc """
  Visualizes the model architecture using Axon's built-in visualization.
  """
  @spec visualize_model(axon_model(), keyword()) :: String.t()
  def visualize_model(_model, _opts \\ []) do
    # This would generate a DOT representation of the graph
    # Axon doesn't have built-in visualization yet, but we can implement
    # a simple graph representation
    "Model visualization not yet implemented"
  end

  @doc """
  Exports model architecture to JSON for analysis.
  """
  @spec model_to_json(axon_model()) :: map()
  def model_to_json(model) do
    # This would inspect the Axon model structure and export to JSON
    # Implementation depends on Axon's internal structure
    %{
      "model_type" => "axon",
      "layers" => [],  # Would extract layer information
  "parameters" => Cerebros.Utils.ParamCount.parameter_count(model),
      "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
end
