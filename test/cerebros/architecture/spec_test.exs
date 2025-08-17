defmodule Cerebros.ArchitectureSpecTest do
  use ExUnit.Case

  alias Cerebros.Architecture.Spec

  describe "architecture specification validation" do
    test "validates a simple valid specification" do
      spec = %Spec{
        input_specs: [%{shape: {32, 32, 3}, name: "image_input"}],
        levels: [
          %{
            level_number: 1,
            unit_type: :dense,
            units: [
              %{unit_id: 0, neurons: 64, activation: :relu}
            ],
            is_final: false
          },
          %{
            level_number: 2,
            unit_type: :dense,
            units: [
              %{unit_id: 0, neurons: 10, activation: nil}
            ],
            is_final: true
          }
        ],
        connectivity_config: %{
          predecessor_prob: 0.8,
          lateral_prob: 0.3,
          skip_prob: 0.2,
          gated_lateral_prob: 0.1
        }
      }

      assert Spec.validate(spec) == :ok
    end

    test "validates RealNeuron specifications" do
      spec = %Spec{
        input_specs: [%{shape: {28, 28, 1}, name: "mnist_input"}],
        levels: [
          %{
            level_number: 1,
            unit_type: :real_neuron,
            units: [
              %{
                unit_id: 0,
                neurons: 32,
                activation: :relu,
                dendrites: 2,
                dendrite_activation: :sigmoid
              }
            ],
            is_final: false
          },
          %{
            level_number: 2,
            unit_type: :dense,
            units: [
              %{unit_id: 0, neurons: 10, activation: nil}
            ],
            is_final: true
          }
        ],
        connectivity_config: %{
          predecessor_prob: 0.9,
          lateral_prob: 0.0,
          skip_prob: 0.0,
          gated_lateral_prob: 0.0
        }
      }

      assert Spec.validate(spec) == :ok
    end

    test "rejects specification with invalid input shape" do
      spec = %Spec{
        input_specs: [%{shape: {}, name: "invalid_input"}],
        levels: [],
        connectivity_config: %{
          predecessor_prob: 0.8,
          lateral_prob: 0.3,
          skip_prob: 0.2,
          gated_lateral_prob: 0.1
        }
      }

      {:error, errors} = Spec.validate(spec)
      assert "Input shape cannot be empty" in errors
    end

    test "rejects specification with no final level" do
      spec = %Spec{
        input_specs: [%{shape: {32, 32, 3}, name: "image_input"}],
        levels: [
          %{
            level_number: 1,
            unit_type: :dense,
            units: [%{unit_id: 0, neurons: 64, activation: :relu}],
            is_final: false
          }
        ],
        connectivity_config: %{
          predecessor_prob: 0.8,
          lateral_prob: 0.3,
          skip_prob: 0.2,
          gated_lateral_prob: 0.1
        }
      }

      {:error, errors} = Spec.validate(spec)
      assert "Must have at least one final level" in errors
    end

    test "rejects specification with invalid probability values" do
      spec = %Spec{
        input_specs: [%{shape: {32, 32, 3}, name: "image_input"}],
        levels: [
          %{
            level_number: 1,
            unit_type: :dense,
            units: [%{unit_id: 0, neurons: 64, activation: :relu}],
            is_final: true
          }
        ],
        connectivity_config: %{
          predecessor_prob: 1.5,  # Invalid probability
          lateral_prob: -0.1,     # Invalid probability
          skip_prob: 0.2,
          gated_lateral_prob: 0.1
        }
      }

      {:error, errors} = Spec.validate(spec)
      assert Enum.any?(errors, &String.contains?(&1, "probability"))
    end
  end

  describe "random specification generation" do
    test "generates valid random specifications" do
      search_params = %{
        min_levels: 2,
        max_levels: 4,
        min_units_per_level: 1,
        max_units_per_level: 3,
        input_shape: {32, 32, 3},
        num_classes: 10
      }

      # Generate multiple specs to test randomness
      specs =
        1..10
        |> Enum.map(fn _ -> Spec.generate_random(search_params) end)

      # All should be valid
      Enum.each(specs, fn spec ->
        assert Spec.validate(spec) == :ok
      end)

      # Should have variety in level counts
      level_counts = Enum.map(specs, &length(&1.levels))
      assert Enum.uniq(level_counts) |> length() > 1
    end

    test "respects generation constraints" do
      search_params = %{
        min_levels: 3,
        max_levels: 3,  # Fixed number of levels
        min_units_per_level: 2,
        max_units_per_level: 2,  # Fixed units per level
        input_shape: {28, 28, 1},
        num_classes: 10
      }

      spec = Spec.generate_random(search_params)

      assert length(spec.levels) == 3
      Enum.each(spec.levels, fn level ->
        assert length(level.units) == 2
      end)
    end
  end

  describe "JSON export and import" do
    test "exports and imports specifications correctly" do
      original_spec = %Spec{
        input_specs: [%{shape: {32, 32, 3}, name: "test_input"}],
        levels: [
          %{
            level_number: 1,
            unit_type: :dense,
            units: [%{unit_id: 0, neurons: 64, activation: :relu}],
            is_final: false
          },
          %{
            level_number: 2,
            unit_type: :dense,
            units: [%{unit_id: 0, neurons: 10, activation: nil}],
            is_final: true
          }
        ],
        connectivity_config: %{
          predecessor_prob: 0.8,
          lateral_prob: 0.3,
          skip_prob: 0.2,
          gated_lateral_prob: 0.1
        }
      }

      # Export to JSON
      json_data = Spec.to_json(original_spec)
      assert is_map(json_data)

      # Should be valid JSON
      json_string = Jason.encode!(json_data)
      assert is_binary(json_string)

      # Import back from JSON
      parsed_data = Jason.decode!(json_string)
      imported_spec = Spec.from_json(parsed_data)

      # Should be equivalent
      assert imported_spec.input_specs == original_spec.input_specs
      assert length(imported_spec.levels) == length(original_spec.levels)
      assert imported_spec.connectivity_config == original_spec.connectivity_config
    end
  end
end
