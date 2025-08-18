defmodule Cerebros.Connectivity.Builder do
  @moduledoc """
  Builds deterministic connectivity patterns for neural network architectures.

  This module replaces the Python connectivity logic with functional,
  deterministic connectivity generation using proper random number generation
  and immutable data structures.
  """

  alias Cerebros.Architecture.Spec

  @type connection :: {from_level :: non_neg_integer(), from_unit :: non_neg_integer()}
  @type unit_connections :: %{
    predecessors: [connection()],
    laterals: [connection()],
    gated_laterals: [connection()]
  }
  @type connectivity_map :: %{
    {level :: non_neg_integer(), unit :: non_neg_integer()} => unit_connections()
  }

  @doc """
  Builds the complete connectivity map for an architecture specification.

  Returns a deterministic connectivity pattern that respects all constraints
  and can be reproduced given the same seed.
  """
  @spec build_connectivity(Spec.t()) :: {:ok, connectivity_map()} | {:error, String.t()}
  def build_connectivity(%Spec{} = spec) do
    # Initialize deterministic RNG with spec seed (process dictionary PRNG).
    # Some legacy tests may omit :seed in the Spec; fall back to a hash-based seed.
    base_seed =
      case spec.seed do
        nil -> :erlang.phash2({spec.levels, spec.connectivity_config}, 1_000_000) + 1
        0 -> 1
        s when is_integer(s) and s > 0 -> s
        _ -> :erlang.phash2(spec.seed, 1_000_000) + 1
      end
    :rand.seed(:exsss, {base_seed, base_seed + 1, base_seed + 2})

    try do
      connectivity =
        spec.levels
        |> Enum.with_index()
        |> Enum.reduce(%{}, fn {level, level_idx}, acc ->
          if level.level_number == 0 do
            # Input level has no connections
            acc
          else
            build_level_connectivity(level, spec, acc, level_idx)
          end
        end)
        |> validate_connectivity(spec)
        |> repair_missing_connections(spec)

      {:ok, connectivity}
    rescue
      error -> {:error, Exception.message(error)}
    end
  end

  # Private functions

  defp build_level_connectivity(level, spec, connectivity_acc, level_idx) do
    # Only consider predecessor levels within configured skip depth window
    predecessor_levels =
      spec.levels
      |> Enum.take(level_idx)
      |> Enum.filter(fn pl ->
        depth = level.level_number - pl.level_number
        depth >= spec.connectivity_config.minimum_skip_connection_depth and
          depth <= spec.connectivity_config.maximum_skip_connection_depth
      end)

    level.units
    |> Enum.reduce(connectivity_acc, fn unit, acc ->
      unit_key = {level.level_number, unit.unit_id}

      # Build predecessor connections (fall back to input layer if none)
      predecessors = build_predecessor_connections(
        unit, level, predecessor_levels, spec.connectivity_config, spec
      )

      # Build lateral connections
      {laterals, gated_laterals} = build_lateral_connections(
        unit, level, spec.connectivity_config
      )

      connections = %{
        predecessors: predecessors,
        laterals: laterals,
        gated_laterals: gated_laterals
      }

      Map.put(acc, unit_key, connections)
    end)
  end

  defp build_predecessor_connections(_unit, level, predecessor_levels, config, spec) do
    conns =
      predecessor_levels
      |> Enum.with_index()
      |> Enum.flat_map(fn {pred_level, _pred_idx} ->
        connection_count = calculate_predecessor_connections(
          level.level_number, pred_level.level_number,
          length(pred_level.units), config
        )

        pred_level.units
        |> Enum.map(& &1.unit_id)
        |> sample_with_replacement(connection_count)
        |> Enum.map(&{pred_level.level_number, &1})
      end)

    # If no explicit predecessor levels (e.g. first hidden level numbers start at 1),
    # connect to synthetic input layer units keyed by {0, idx} matching input_specs.
    if conns == [] and level.level_number > 0 do
      input_count = length(spec.input_specs)
      # Determine how many connections we want from input using first affinity factor
      connection_count =
        config.predecessor_affinity_factor_first
        |> Kernel.*(input_count)
        |> round()
        |> max(1)

      0..(connection_count - 1)
      |> Enum.map(fn i -> {0, rem(i, input_count)} end)
    else
      conns
    end
  end

  defp calculate_predecessor_connections(current_level, pred_level, pred_unit_count, config) do
    depth = current_level - pred_level

    base_factor = case pred_level do
      0 -> config.predecessor_affinity_factor_first  # Input level
      _ -> config.predecessor_affinity_factor_main   # Hidden levels
    end

    decay_factor = if pred_level == 0 do
      1.0  # No decay for input connections
    else
      config.predecessor_affinity_factor_decay.(depth)
    end

    raw_count = base_factor * decay_factor * pred_unit_count
    max(1, round(raw_count))  # Ensure at least one connection
  end

  defp build_lateral_connections(unit, level, config) do
    potential_laterals =
      level.units
      |> Enum.filter(&(&1.unit_id < unit.unit_id))
      |> Enum.map(& &1.unit_id)

    max_consecutive = Map.get(config, :max_consecutive_lateral_connections, 9_999)

    {laterals, gated, _consecutive} =
      Enum.reduce_while(potential_laterals, {[], [], 0}, fn lateral_unit_id, {lat, gated, consecutive} ->
        # Stop early if we already hit max consecutive laterals
        if consecutive >= max_consecutive do
          {:halt, {lat, gated, consecutive}}
        else
          distance = unit.unit_id - lateral_unit_id
          connection_prob = config.lateral_connection_probability * config.lateral_connection_decay.(distance)

          if :rand.uniform() <= connection_prob do
            connection = {level.level_number, lateral_unit_id}
            new_consecutive = consecutive + 1
            should_gate =
              new_consecutive > 0 and
                rem(new_consecutive, config.gate_after_n_lateral_connections) == 0

            if should_gate do
              {:cont, {lat, [connection | gated], new_consecutive}}
            else
              {:cont, {[connection | lat], gated, new_consecutive}}
            end
          else
            # Break the streak – reset consecutive count
            {:cont, {lat, gated, 0}}
          end
        end
      end)

    {Enum.reverse(laterals), Enum.reverse(gated)}
  end

  defp sample_with_replacement(_items, count) when count <= 0, do: []
  defp sample_with_replacement([], _count), do: []
  defp sample_with_replacement(items, count) do
    1..count
    |> Enum.map(fn _ -> Enum.random(items) end)
  end

  defp validate_connectivity(connectivity, spec) do
    # Validate that every non-input unit has at least one predecessor
    spec.levels
    |> Enum.filter(&(&1.level_number > 0))
    |> Enum.each(fn level ->
      Enum.each(level.units, fn unit ->
        unit_key = {level.level_number, unit.unit_id}
        connections = Map.get(connectivity, unit_key, %{})
        predecessors = Map.get(connections, :predecessors, [])

        if Enum.empty?(predecessors) do
          raise "Unit #{inspect(unit_key)} has no predecessor connections"
        end
      end)
    end)

    connectivity
  end

  defp repair_missing_connections(connectivity, _spec) do
    # This is a placeholder - in practice, the validation above should catch
    # missing connections and we should fix the generation logic instead
    # of post-hoc repair to maintain determinism
    connectivity
  end

  @doc """
  Exports connectivity to a JSON-serializable format for analysis.
  """
  @spec to_json(connectivity_map()) :: map()
  def to_json(connectivity) do
    connectivity
    |> Enum.map(fn {{level, unit}, connections} ->
      %{
        "unit" => %{"level" => level, "unit_id" => unit},
        "predecessors" => Enum.map(connections.predecessors, fn {l, u} -> %{"level" => l, "unit_id" => u} end),
        "laterals" => Enum.map(connections.laterals, fn {l, u} -> %{"level" => l, "unit_id" => u} end),
        "gated_laterals" => Enum.map(connections.gated_laterals, fn {l, u} -> %{"level" => l, "unit_id" => u} end)
      }
    end)
  end

  # Backwards-compatible JSON export wrapper expected by legacy tests
  def connectivity_to_json(connectivity) do
    %{
      "connectivity_map" =>
        connectivity
        |> Enum.into(%{}, fn {{l, u}, conns} ->
          key = "#{l}:#{u}"
          value = %{
            "predecessors" => Enum.map(conns.predecessors, &Tuple.to_list/1),
            "laterals" => Enum.map(conns.laterals, &Tuple.to_list/1),
            "gated_laterals" => Enum.map(conns.gated_laterals, &Tuple.to_list/1)
          }
          {key, value}
        end),
      "metadata" => %{"version" => 1}
    }
  end

  @doc """
  Validates that connectivity respects DAG properties and skip depth constraints.
  """
  @spec validate_dag_properties(connectivity_map(), Spec.t()) :: :ok | {:error, [String.t()]}
  def validate_dag_properties(connectivity, spec) do
    # Check DAG ordering
    dag_errors = validate_dag_ordering(connectivity)

    # Check skip depth constraints
    skip_errors = validate_skip_depths(connectivity, spec.connectivity_config)

    # Check for unreachable units
    reachability_errors = validate_reachability(connectivity, spec)

    all_errors = dag_errors ++ skip_errors ++ reachability_errors

    case all_errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp validate_dag_ordering(connectivity) do
    connectivity
    |> Enum.flat_map(fn {{to_level, to_unit}, connections} ->
      # Check predecessor connections
      pred_errors =
        connections.predecessors
        |> Enum.filter(fn {from_level, from_unit} ->
          from_level > to_level or
          (from_level == to_level and from_unit >= to_unit)
        end)
        |> Enum.map(fn {from_level, from_unit} ->
          "Invalid predecessor: ({#{from_level}, #{from_unit}}) -> ({#{to_level}, #{to_unit}})"
        end)

      # Check lateral connections
      lateral_errors =
        connections.laterals
        |> Enum.filter(fn {from_level, from_unit} ->
          from_level != to_level or from_unit >= to_unit
        end)
        |> Enum.map(fn {from_level, from_unit} ->
          "Invalid lateral: ({#{from_level}, #{from_unit}}) -> ({#{to_level}, #{to_unit}})"
        end)

      pred_errors ++ lateral_errors
    end)
  end

  defp validate_skip_depths(connectivity, config) do
    connectivity
    |> Enum.flat_map(fn {{to_level, _to_unit}, connections} ->
      connections.predecessors
      |> Enum.map(fn {from_level, _from_unit} -> to_level - from_level end)
      |> Enum.filter(fn depth ->
        depth < config.minimum_skip_connection_depth or
        depth > config.maximum_skip_connection_depth
      end)
      |> Enum.map(fn depth ->
        "Skip depth #{depth} violates constraints [#{config.minimum_skip_connection_depth}, #{config.maximum_skip_connection_depth}]"
      end)
    end)
  end

  defp validate_reachability(connectivity, spec) do
    # Check that every non-final unit is used as a predecessor somewhere
    all_units =
      spec.levels
      |> Enum.flat_map(fn level ->
        Enum.map(level.units, &{level.level_number, &1.unit_id})
      end)

    used_units =
      connectivity
      |> Enum.flat_map(fn {_unit, connections} ->
        connections.predecessors ++ connections.laterals
      end)
      |> MapSet.new()

    final_level_num = spec.levels |> List.last() |> Map.get(:level_number)

    all_units
    |> Enum.filter(fn {level, _unit} -> level < final_level_num end)
    |> Enum.reject(&MapSet.member?(used_units, &1))
    |> Enum.map(fn {level, unit} ->
      "Unit ({#{level}, #{unit}}) is not used by any successor"
    end)
  end

  # Simplified DAG validator retained for legacy tests. The richer
  # validate_dag_properties/2 supersedes this.
  def validate_dag(connectivity) do
    # Detect cycles via DFS
    graph = connectivity
    visit = fn node, stack, visited, rec_stack, fun ->
      cond do
        MapSet.member?(rec_stack, node) -> {:cycle, node}
        MapSet.member?(visited, node) -> {:ok, visited, rec_stack}
        true ->
          rec_stack = MapSet.put(rec_stack, node)
          visited = MapSet.put(visited, node)
          neighbors =
            case Map.get(graph, node) do
              nil -> []
              %{predecessors: preds, laterals: lats} -> preds ++ lats
            end
          Enum.reduce_while(neighbors, {:ok, visited, rec_stack}, fn nbr, {:ok, v, r} ->
            case fun.(nbr, [nbr | stack], v, r, fun) do
              {:cycle, n} -> {:halt, {:cycle, n}}
              {:ok, v2, r2} -> {:cont, {:ok, v2, r2}}
            end
          end)
          |> case do
            {:cycle, n} -> {:cycle, n}
            {:ok, v_final, _r_final} -> {:ok, v_final, MapSet.delete(rec_stack, node)}
          end
      end
    end
    result =
      Enum.reduce_while(Map.keys(graph), {:ok, MapSet.new(), MapSet.new()}, fn node, {:ok, v, r} ->
        case visit.(node, [node], v, r, visit) do
          {:cycle, _} = cyc -> {:halt, cyc}
          {:ok, v2, r2} -> {:cont, {:ok, v2, r2}}
        end
      end)
    case result do
      {:cycle, _n} -> {:error, "Cycle detected"}
      _ -> :ok
    end
  end
end
