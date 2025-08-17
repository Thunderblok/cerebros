defmodule Mix.Tasks.Cerebros.Nas.Run do
  use Mix.Task
  @shortdoc "Run a Neural Architecture Search sweep"
  @moduledoc """
  Runs a NAS sweep from the command line without entering IEx.

  Examples:

      mix cerebros.nas.run \
        --architectures 3 \
        --trials 1 \
        --epochs 3 \
        --min-levels 1 --max-levels 3 \
        --min-neurons 4 --max-neurons 32

  Optional flags:
    --batch-size <int>
    --learning-rate <float>
    --merge-strategies concatenate,add,multiply
    --max-merge-width <int>
    --projection-after-merge true|false
    --early-stop <int>

  To output JSON results to a file:

      mix cerebros.nas.run --architectures 2 --trials 1 --epochs 2 --out results.json
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    opts = parse_args(args)

    config = %{
      input_shapes: [tuple_from_csv(Map.get(opts, :input_shapes, "10"))],
      output_shapes: [tuple_from_csv(Map.get(opts, :output_shapes, "1"))],
      number_of_architectures_to_try: Map.get(opts, :architectures, 2),
      number_of_trials_per_architecture: Map.get(opts, :trials, 1),
      minimum_levels: Map.get(opts, :min_levels, 1),
      maximum_levels: Map.get(opts, :max_levels, 3),
      minimum_units_per_level: Map.get(opts, :min_units_per_level, 1),
      maximum_units_per_level: Map.get(opts, :max_units_per_level, 3),
      minimum_neurons_per_unit: Map.get(opts, :min_neurons, 4),
      maximum_neurons_per_unit: Map.get(opts, :max_neurons, 32),
      epochs: Map.get(opts, :epochs, 5),
      batch_size: Map.get(opts, :batch_size, 32),
      learning_rate: Map.get(opts, :learning_rate, 0.001),
      merge_strategy_pool: Map.get(opts, :merge_strategies, [:concatenate]),
      max_merge_width: Map.get(opts, :max_merge_width, nil),
      projection_after_merge: Map.get(opts, :projection_after_merge, true),
      early_stop_patience: Map.get(opts, :early_stop, 10)
    }

    IO.puts("Running NAS sweep: #{inspect(config)}")
    {:ok, results} = Cerebros.test_full_nas_run(Enum.into(config, []))

    case Map.get(opts, :out) do
      nil -> :ok
      path -> File.write!(path, Jason.encode!(results, pretty: true))
    end

    print_summary(results)
  end

  defp print_summary(results) do
    losses =
      results
      |> Enum.map(& &1.validation_loss)
      |> Enum.reject(&is_nil/1)

    avg = if losses == [], do: 0.0, else: Enum.sum(losses)/length(losses)
    best = if losses == [], do: 0.0, else: Enum.min(losses)

    IO.puts("\nSummary:")
    IO.puts("  Trials: #{length(results)}")
    IO.puts("  Best Validation Loss: #{Float.round(best, 6)}")
    IO.puts("  Avg Validation Loss: #{Float.round(avg, 6)}")
    if avg > 0 do
      IO.puts("  Improvement: #{Float.round((avg - best)/avg * 100, 2)}%")
    end
  end

  defp parse_args(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: [
      architectures: :integer,
      trials: :integer,
      epochs: :integer,
      batch_size: :integer,
      learning_rate: :float,
      min_levels: :integer,
      max_levels: :integer,
      min_units_per_level: :integer,
      max_units_per_level: :integer,
      min_neurons: :integer,
      max_neurons: :integer,
      merge_strategies: :string,
      max_merge_width: :integer,
      projection_after_merge: :boolean,
      early_stop: :integer,
      input_shapes: :string,
      output_shapes: :string,
      out: :string
    ])

    opts
    |> Enum.map(fn
      {:merge_strategies, v} -> {:merge_strategies, parse_atoms_csv(v)}
      {:input_shapes, v} -> {:input_shapes, v}
      {:output_shapes, v} -> {:output_shapes, v}
      other -> other
    end)
    |> Map.new()
  end

  defp parse_atoms_csv(str) do
    str
    |> String.split([",", ":"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.to_atom/1)
  end

  defp tuple_from_csv(str) do
    parts = str |> String.split([","], trim: true) |> Enum.map(&String.to_integer/1)
    List.to_tuple(parts)
  end
end
