defmodule Cerebros.ConnectivityBuilderTest do
  use ExUnit.Case

  alias Cerebros.Architecture.Spec
  alias Cerebros.Connectivity.Builder

  describe "connectivity building" do
    test "builds connectivity for simple linear architecture" do
      spec = %Spec{
        input_specs: [%{shape: {10,}, name: "input"}],
        levels: [
          %{
            level_number: 1,
            unit_type: :dense,
            units: [%{unit_id: 0, neurons: 5, activation: :relu}],
            is_final: false
          },
          %{
            level_number: 2,
            unit_type: :dense,
            units: [%{unit_id: 0, neurons: 1, activation: nil}],
            is_final: true
          }
        ],
        connectivity_config: %{
          predecessor_prob: 1.0,  # Always connect to predecessors
          lateral_prob: 0.0,      # No lateral connections
          skip_prob: 0.0,         # No skip connections
          gated_lateral_prob: 0.0
        }
      }

      {:ok, connectivity} = Builder.build_connectivity(spec)

      # Level 1 should connect to input (level 0)
      level_1_unit_0 = {1, 0}
      assert Map.has_key?(connectivity, level_1_unit_0)

      connections = connectivity[level_1_unit_0]
      assert {0, 0} in connections.predecessors
      assert Enum.empty?(connections.laterals)
      assert Enum.empty?(connections.gated_laterals)

      # Level 2 should connect to level 1
      level_2_unit_0 = {2, 0}
      assert Map.has_key?(connectivity, level_2_unit_0)

      connections = connectivity[level_2_unit_0]
      assert {1, 0} in connections.predecessors
    end

    test "respects lateral connectivity probability" do
      spec = %Spec{
        input_specs: [%{shape: {10,}, name: "input"}],
        levels: [
          %{
            level_number: 1,
            unit_type: :dense,
            units: [
              %{unit_id: 0, neurons: 5, activation: :relu},
              %{unit_id: 1, neurons: 5, activation: :relu},
              %{unit_id: 2, neurons: 5, activation: :relu}
            ],
            is_final: false
          },
          %{
            level_number: 2,
            unit_type: :dense,
            units: [%{unit_id: 0, neurons: 1, activation: nil}],
            is_final: true
          }
        ],
        connectivity_config: %{
          predecessor_prob: 1.0,
          lateral_prob: 1.0,  # Always connect laterally
          skip_prob: 0.0,
          gated_lateral_prob: 0.0
        }
      }

      {:ok, connectivity} = Builder.build_connectivity(spec)

      # Check that lateral connections exist within level 1
      level_1_units = [{1, 0}, {1, 1}, {1, 2}]

      Enum.each(level_1_units, fn unit_key ->
        connections = connectivity[unit_key]
        other_units = level_1_units -- [unit_key]

        # Should have lateral connections to other units in same level
        assert length(connections.laterals) > 0
        Enum.each(connections.laterals, fn lateral ->
          assert lateral in other_units
        end)
      end)
    end

    test "validates DAG property" do
      spec = %Spec{
        input_specs: [%{shape: {10,}, name: "input"}],
        levels: [
          %{
            level_number: 1,
            unit_type: :dense,
            units: [%{unit_id: 0, neurons: 5, activation: :relu}],
            is_final: false
          },
          %{
            level_number: 2,
            unit_type: :dense,
            units: [%{unit_id: 0, neurons: 1, activation: nil}],
            is_final: true
          }
        ],
        connectivity_config: %{
          predecessor_prob: 1.0,
          lateral_prob: 0.0,
          skip_prob: 0.0,
          gated_lateral_prob: 0.0
        }
      }

      {:ok, connectivity} = Builder.build_connectivity(spec)

      # Should pass DAG validation
      assert Builder.validate_dag(connectivity) == :ok
    end

    test "detects cycles in invalid connectivity" do
      # Manually create invalid connectivity with a cycle
      invalid_connectivity = %{
        {1, 0} => %{predecessors: [{1, 1}], laterals: [], gated_laterals: []},
        {1, 1} => %{predecessors: [{1, 0}], laterals: [], gated_laterals: []}
      }

      assert {:error, "Cycle detected"} = Builder.validate_dag(invalid_connectivity)
    end

    test "produces deterministic results with same seed" do
      spec = %Spec{
        input_specs: [%{shape: {10,}, name: "input"}],
        levels: [
          %{
            level_number: 1,
            unit_type: :dense,
            units: [
              %{unit_id: 0, neurons: 5, activation: :relu},
              %{unit_id: 1, neurons: 5, activation: :relu}
            ],
            is_final: false
          },
          %{
            level_number: 2,
            unit_type: :dense,
            units: [%{unit_id: 0, neurons: 1, activation: nil}],
            is_final: true
          }
        ],
        connectivity_config: %{
          predecessor_prob: 0.7,
          lateral_prob: 0.5,
          skip_prob: 0.3,
          gated_lateral_prob: 0.2
        }
      }

      # Build connectivity twice with same seed
      :rand.seed(:exsplus, {1, 2, 3})
      {:ok, connectivity1} = Builder.build_connectivity(spec)

      :rand.seed(:exsplus, {1, 2, 3})
      {:ok, connectivity2} = Builder.build_connectivity(spec)

      # Should be identical
      assert connectivity1 == connectivity2
    end
  end

  describe "connectivity repair" do
    test "repairs disconnected components" do
      # Create a spec that might generate disconnected components
      spec = %Spec{
        input_specs: [%{shape: {10,}, name: "input"}],
        levels: [
          %{
            level_number: 1,
            unit_type: :dense,
            units: [
              %{unit_id: 0, neurons: 5, activation: :relu},
              %{unit_id: 1, neurons: 5, activation: :relu}
            ],
            is_final: false
          },
          %{
            level_number: 2,
            unit_type: :dense,
            units: [%{unit_id: 0, neurons: 1, activation: nil}],
            is_final: true
          }
        ],
        connectivity_config: %{
          predecessor_prob: 0.0,  # Very low probability
          lateral_prob: 0.0,
          skip_prob: 0.0,
          gated_lateral_prob: 0.0
        }
      }

      {:ok, connectivity} = Builder.build_connectivity(spec)

      # All units should have some path to input
      all_units = [{1, 0}, {1, 1}, {2, 0}]

      Enum.each(all_units, fn unit_key ->
        connections = connectivity[unit_key]
        # Should have at least one connection (due to repair mechanism)
        total_connections = length(connections.predecessors) +
                           length(connections.laterals) +
                           length(connections.gated_laterals)
        assert total_connections > 0
      end)
    end
  end

  describe "JSON export" do
    test "exports connectivity to valid JSON" do
      spec = %Spec{
        input_specs: [%{shape: {10,}, name: "input"}],
        levels: [
          %{
            level_number: 1,
            unit_type: :dense,
            units: [%{unit_id: 0, neurons: 5, activation: :relu}],
            is_final: false
          },
          %{
            level_number: 2,
            unit_type: :dense,
            units: [%{unit_id: 0, neurons: 1, activation: nil}],
            is_final: true
          }
        ],
        connectivity_config: %{
          predecessor_prob: 1.0,
          lateral_prob: 0.0,
          skip_prob: 0.0,
          gated_lateral_prob: 0.0
        }
      }

      {:ok, connectivity} = Builder.build_connectivity(spec)
      json_data = Builder.connectivity_to_json(connectivity)

      # Should be valid JSON
      json_string = Jason.encode!(json_data)
      assert is_binary(json_string)

      # Should contain expected structure
      assert Map.has_key?(json_data, "connectivity_map")
      assert Map.has_key?(json_data, "metadata")

      # Connectivity map should have string keys (JSON requirement)
      connectivity_map = json_data["connectivity_map"]
      assert is_map(connectivity_map)

      # Check that all keys are strings
      Enum.each(Map.keys(connectivity_map), fn key ->
        assert is_binary(key)
      end)
    end
  end
end
