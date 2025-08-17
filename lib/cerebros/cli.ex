defmodule Cerebros.CLI do
  @moduledoc """
  Command-line interface for the Cerebros neural architecture search system.

  Provides a user-friendly way to run experiments, monitor progress,
  and analyze results from the command line.
  """

  alias Cerebros.Architecture.Spec
  alias Cerebros.Training.Orchestrator
  alias Cerebros.Results.Collector
  alias Cerebros.Data.Loader

  @doc """
  Main entry point for CLI commands.
  """
  def main(args) do
    case parse_args(args) do
      {:help} ->
        print_help()

      {:version} ->
        print_version()

      {:run_search, opts} ->
        run_search(opts)

      {:analyze, opts} ->
        analyze_results(opts)

      {:export, format, file_path} ->
        export_results(format, file_path)

      {:validate_spec, spec_file} ->
        validate_spec_file(spec_file)

      {:generate_spec, opts} ->
        generate_spec(opts)

      {:error, message} ->
        IO.puts(:stderr, "Error: #{message}")
        print_help()
        System.halt(1)
    end
  end

  defp parse_args(args) do
    case args do
      [] -> {:help}
      ["--help"] -> {:help}
      ["-h"] -> {:help}
      ["--version"] -> {:version}
      ["-v"] -> {:version}

      ["search" | search_args] ->
        parse_search_args(search_args)

      ["analyze" | analyze_args] ->
        parse_analyze_args(analyze_args)

      ["export", format, file_path] ->
        {:export, format, file_path}

      ["validate", spec_file] ->
        {:validate_spec, spec_file}

      ["generate" | gen_args] ->
        parse_generate_args(gen_args)

      [unknown | _] ->
        {:error, "Unknown command: #{unknown}"}
    end
  end

  defp parse_search_args(args) do
    opts = %{
      num_trials: 10,
      max_concurrent: 4,
      dataset: :cifar10,
      epochs: 50,
      batch_size: 32,
      learning_rate: 0.001,
      early_stop_patience: 10,
      output_dir: "./results"
    }

    parsed_opts = parse_key_value_args(args, opts)
    {:run_search, parsed_opts}
  end

  defp parse_analyze_args(args) do
    opts = %{
      results_dir: "./results",
      output_format: :table,
      top_n: 10,
      metric: "accuracy"
    }

    parsed_opts = parse_key_value_args(args, opts)
    {:analyze, parsed_opts}
  end

  defp parse_generate_args(args) do
    opts = %{
      num_specs: 1,
      output_file: nil,
      min_levels: 2,
      max_levels: 6,
      min_units: 1,
      max_units: 5
    }

    parsed_opts = parse_key_value_args(args, opts)
    {:generate_spec, parsed_opts}
  end

  defp parse_key_value_args([], opts), do: opts
  defp parse_key_value_args([key, value | rest], opts) do
    updated_opts =
      case key do
        "--num-trials" -> Map.put(opts, :num_trials, String.to_integer(value))
        "--max-concurrent" -> Map.put(opts, :max_concurrent, String.to_integer(value))
        "--dataset" -> Map.put(opts, :dataset, String.to_atom(value))
        "--epochs" -> Map.put(opts, :epochs, String.to_integer(value))
        "--batch-size" -> Map.put(opts, :batch_size, String.to_integer(value))
        "--learning-rate" -> Map.put(opts, :learning_rate, String.to_float(value))
        "--patience" -> Map.put(opts, :early_stop_patience, String.to_integer(value))
        "--output-dir" -> Map.put(opts, :output_dir, value)
        "--results-dir" -> Map.put(opts, :results_dir, value)
        "--format" -> Map.put(opts, :output_format, String.to_atom(value))
        "--top-n" -> Map.put(opts, :top_n, String.to_integer(value))
        "--metric" -> Map.put(opts, :metric, value)
        "--output-file" -> Map.put(opts, :output_file, value)
        "--min-levels" -> Map.put(opts, :min_levels, String.to_integer(value))
        "--max-levels" -> Map.put(opts, :max_levels, String.to_integer(value))
        "--min-units" -> Map.put(opts, :min_units, String.to_integer(value))
        "--max-units" -> Map.put(opts, :max_units, String.to_integer(value))
        "--num-specs" -> Map.put(opts, :num_specs, String.to_integer(value))
        _ -> opts
      end

    parse_key_value_args(rest, updated_opts)
  end

  defp run_search(opts) do
    IO.puts("🧠 Starting Cerebros Neural Architecture Search")
    IO.puts("================================================")

    # Print configuration
    print_search_config(opts)

    # Start the application components
    {:ok, _} = Application.ensure_all_started(:cerebros)

    # Start orchestrator and collector
    {:ok, orchestrator} = Orchestrator.start_link(
      max_concurrent: opts.max_concurrent,
      search_config: opts
    )

    {:ok, collector} = Collector.start_link(
      storage_backend: :file,
      storage_path: opts.output_dir
    )

    # Setup search parameters
    search_params = %{
      num_trials: opts.num_trials,
      training_config: %{
        dataset: opts.dataset,
        epochs: opts.epochs,
        batch_size: opts.batch_size,
        learning_rate: opts.learning_rate,
        early_stop_patience: opts.early_stop_patience
      },
      min_levels: opts[:min_levels] || 2,
      max_levels: opts[:max_levels] || 6,
      min_units_per_level: opts[:min_units] || 1,
      max_units_per_level: opts[:max_units] || 5
    }

    # Start the search
    IO.puts("\n🚀 Starting random search with #{opts.num_trials} trials...")
    :ok = Orchestrator.start_random_search(orchestrator, search_params)

    # Monitor progress
    monitor_search_progress(orchestrator, collector, opts.num_trials)

    # Final analysis
    IO.puts("\n📊 Search completed! Analyzing results...")
    analysis = Collector.analyze_results(collector)
    print_final_analysis(analysis)

    # Export results
    export_path = Path.join(opts.output_dir, "results_#{DateTime.utc_now() |> DateTime.to_unix()}.json")
    :ok = Collector.export_results(collector, "json", export_path)
    IO.puts("\n💾 Results exported to: #{export_path}")

    IO.puts("\n✅ Search completed successfully!")
  end

  defp analyze_results(opts) do
    IO.puts("📊 Analyzing Cerebros Results")
    IO.puts("============================")

    # Start collector to load existing results
    {:ok, collector} = Collector.start_link(
      storage_backend: :file,
      storage_path: opts.results_dir
    )

    # Get and analyze results
    analysis = Collector.analyze_results(collector)

    case opts.output_format do
      :table -> print_analysis_table(analysis, opts)
      :json -> print_analysis_json(analysis)
      :summary -> print_analysis_summary(analysis)
    end
  end

  defp export_results(format, file_path) do
    IO.puts("💾 Exporting Results")
    IO.puts("===================")

    {:ok, collector} = Collector.start_link(storage_backend: :file)

    case Collector.export_results(collector, format, file_path) do
      :ok ->
        IO.puts("✅ Results exported successfully to: #{file_path}")

      {:error, reason} ->
        IO.puts(:stderr, "❌ Export failed: #{reason}")
        System.halt(1)
    end
  end

  defp validate_spec_file(spec_file) do
    IO.puts("🔍 Validating Architecture Specification")
    IO.puts("========================================")

    case File.read(spec_file) do
      {:ok, content} ->
        try do
          spec_data = Jason.decode!(content)
          spec = struct(Spec, spec_data)

          case Spec.validate(spec) do
            :ok ->
              IO.puts("✅ Specification is valid!")
              print_spec_summary(spec)

            {:error, errors} ->
              IO.puts("❌ Specification validation failed:")
              Enum.each(errors, fn error -> IO.puts("  - #{error}") end)
              System.halt(1)
          end
        rescue
          error ->
            IO.puts(:stderr, "❌ Failed to parse specification: #{Exception.message(error)}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts(:stderr, "❌ Failed to read file: #{reason}")
        System.halt(1)
    end
  end

  defp generate_spec(opts) do
    IO.puts("🎲 Generating Random Architecture Specifications")
    IO.puts("===============================================")

    search_params = %{
      min_levels: opts.min_levels,
      max_levels: opts.max_levels,
      min_units_per_level: opts.min_units,
      max_units_per_level: opts.max_units
    }

    specs =
      1..opts.num_specs
      |> Enum.map(fn _ -> Spec.generate_random(search_params) end)

    case opts.output_file do
      nil ->
        # Print to stdout
        specs
        |> Enum.with_index(1)
        |> Enum.each(fn {spec, idx} ->
          IO.puts("\n--- Specification #{idx} ---")
          print_spec_summary(spec)
        end)

      file_path ->
        # Write to file
        content =
          if opts.num_specs == 1 do
            Jason.encode!(List.first(specs), pretty: true)
          else
            Jason.encode!(specs, pretty: true)
          end

        File.write!(file_path, content)
        IO.puts("✅ Generated #{opts.num_specs} specification(s) and saved to: #{file_path}")
    end
  end

  defp print_help do
    IO.puts("""
    🧠 Cerebros - Neural Architecture Search

    USAGE:
        cerebros <command> [options]

    COMMANDS:
        search              Run neural architecture search
        analyze             Analyze existing results
        export <format> <file>  Export results to file
        validate <spec>     Validate architecture specification
        generate            Generate random specifications

    SEARCH OPTIONS:
        --num-trials <n>        Number of trials to run (default: 10)
        --max-concurrent <n>    Maximum concurrent trials (default: 4)
        --dataset <name>        Dataset to use (cifar10, mnist, synthetic)
        --epochs <n>           Training epochs per trial (default: 50)
        --batch-size <n>       Batch size (default: 32)
        --learning-rate <f>    Learning rate (default: 0.001)
        --patience <n>         Early stopping patience (default: 10)
        --output-dir <path>    Output directory (default: ./results)

    ANALYZE OPTIONS:
        --results-dir <path>   Results directory (default: ./results)
        --format <fmt>         Output format (table, json, summary)
        --top-n <n>           Number of top results (default: 10)
        --metric <name>       Metric to rank by (default: accuracy)

    GENERATE OPTIONS:
        --num-specs <n>       Number of specs to generate (default: 1)
        --output-file <path>  Save to file instead of printing
        --min-levels <n>      Minimum levels (default: 2)
        --max-levels <n>      Maximum levels (default: 6)
        --min-units <n>       Minimum units per level (default: 1)
        --max-units <n>       Maximum units per level (default: 5)

    EXAMPLES:
        cerebros search --num-trials 20 --dataset cifar10
        cerebros analyze --format table --top-n 5
        cerebros export json results.json
        cerebros generate --num-specs 5 --output-file specs.json
    """)
  end

  defp print_version do
    {:ok, vsn} = :application.get_key(:cerebros, :vsn)
    IO.puts("Cerebros version #{vsn}")
  end

  defp print_search_config(opts) do
    IO.puts("Configuration:")
    IO.puts("  Trials: #{opts.num_trials}")
    IO.puts("  Max Concurrent: #{opts.max_concurrent}")
    IO.puts("  Dataset: #{opts.dataset}")
    IO.puts("  Epochs: #{opts.epochs}")
    IO.puts("  Batch Size: #{opts.batch_size}")
    IO.puts("  Learning Rate: #{opts.learning_rate}")
    IO.puts("  Early Stop Patience: #{opts.early_stop_patience}")
    IO.puts("  Output Directory: #{opts.output_dir}")
  end

  defp monitor_search_progress(orchestrator, collector, total_trials) do
    # Simple progress monitoring
    monitor_loop(orchestrator, collector, total_trials, 0)
  end

  defp monitor_loop(orchestrator, collector, total_trials, last_completed) do
    Process.sleep(5000)  # Check every 5 seconds

    trials = Orchestrator.list_trials(orchestrator)
    completed = Enum.count(trials, fn trial -> trial.status == :completed end)
    failed = Enum.count(trials, fn trial -> trial.status == :failed end)
    running = Enum.count(trials, fn trial -> trial.status == :running end)

    if completed > last_completed do
      # Get latest results for progress display
      results = Collector.get_all_results(collector)
      best_accuracy =
        case results do
          [] -> 0.0
          _ ->
            results
            |> Enum.map(fn r -> Map.get(r.final_metrics || %{}, "accuracy", 0.0) end)
            |> Enum.max()
        end

      progress_bar = create_progress_bar(completed + failed, total_trials)
      IO.puts("\r#{progress_bar} #{completed}/#{total_trials} completed (#{running} running) | Best: #{:erlang.float_to_binary(best_accuracy, decimals: 3)}")
    end

    if completed + failed < total_trials do
      monitor_loop(orchestrator, collector, total_trials, completed)
    end
  end

  defp create_progress_bar(current, total) do
    percentage = current / total
    bar_length = 30
    filled_length = round(percentage * bar_length)

    bar = String.duplicate("█", filled_length) <> String.duplicate("░", bar_length - filled_length)
    "[#{bar}] #{round(percentage * 100)}%"
  end

  defp print_final_analysis(analysis) do
    IO.puts("\n📈 Final Analysis")
    IO.puts("================")

    summary = analysis.performance_summary
    IO.puts("Total Trials: #{summary.total_trials}")
    IO.puts("Completed: #{summary.completed_trials}")

    if Map.has_key?(summary, :metric_statistics) do
      accuracy_stats = get_in(summary, [:metric_statistics, "accuracy"])

      if accuracy_stats do
        IO.puts("Best Accuracy: #{:erlang.float_to_binary(accuracy_stats.max, decimals: 4)}")
        IO.puts("Average Accuracy: #{:erlang.float_to_binary(accuracy_stats.mean, decimals: 4)}")
      end
    end

    IO.puts("\n🏆 Top Architectures:")
    analysis.best_architectures
    |> Enum.take(3)
    |> Enum.with_index(1)
    |> Enum.each(fn {arch, idx} ->
      accuracy = get_in(arch, [:final_metrics, "accuracy"]) || 0.0
      levels = get_in(arch, [:architecture, :num_levels]) || 0
      IO.puts("  #{idx}. Trial #{arch.trial_id}: #{:erlang.float_to_binary(accuracy, decimals: 4)} accuracy, #{levels} levels")
    end)

    IO.puts("\n💡 Recommendations:")
    analysis.recommendations
    |> Enum.take(3)
    |> Enum.each(fn rec -> IO.puts("  • #{rec}") end)
  end

  defp print_analysis_table(analysis, opts) do
    # Print top architectures in table format
    IO.puts("Top #{opts.top_n} Architectures by #{opts.metric}:")
    IO.puts(String.duplicate("=", 80))

    header = String.pad_trailing("Trial ID", 15) <>
             String.pad_trailing("Accuracy", 12) <>
             String.pad_trailing("Loss", 12) <>
             String.pad_trailing("Time(ms)", 12) <>
             String.pad_trailing("Levels", 8) <>
             "Model Size"

    IO.puts(header)
    IO.puts(String.duplicate("-", 80))

    analysis.best_architectures
    |> Enum.take(opts.top_n)
    |> Enum.each(fn arch ->
      trial_id = String.pad_trailing(arch.trial_id, 15)
      accuracy = arch.final_metrics["accuracy"] || 0.0
      accuracy_str = String.pad_trailing(:erlang.float_to_binary(accuracy, decimals: 4), 12)

      loss = arch.final_metrics["loss"] || 0.0
      loss_str = String.pad_trailing(:erlang.float_to_binary(loss, decimals: 4), 12)

      time_str = String.pad_trailing(Integer.to_string(arch.training_time_ms), 12)
      levels_str = String.pad_trailing(Integer.to_string(arch.architecture.num_levels), 8)
      size_str = Integer.to_string(arch.model_size)

      IO.puts("#{trial_id}#{accuracy_str}#{loss_str}#{time_str}#{levels_str}#{size_str}")
    end)
  end

  defp print_analysis_json(analysis) do
    IO.puts(Jason.encode!(analysis, pretty: true))
  end

  defp print_analysis_summary(analysis) do
    summary = analysis.performance_summary

    IO.puts("Search Summary:")
    IO.puts("  Total Trials: #{summary.total_trials}")
    IO.puts("  Completed: #{summary.completed_trials}")
    IO.puts("  Average Training Time: #{round(summary.average_training_time)}ms")

    if Map.has_key?(summary, :metric_statistics) do
      Enum.each(summary.metric_statistics, fn {metric, stats} ->
        IO.puts("  #{String.capitalize(metric)}:")
        IO.puts("    Best: #{:erlang.float_to_binary(stats.max, decimals: 4)}")
        IO.puts("    Average: #{:erlang.float_to_binary(stats.mean, decimals: 4)}")
        IO.puts("    Std Dev: #{:erlang.float_to_binary(stats.std, decimals: 4)}")
      end)
    end
  end

  defp print_spec_summary(spec) do
    IO.puts("Levels: #{length(spec.levels)}")

    total_units = Enum.sum(Enum.map(spec.levels, &length(&1.units)))
    IO.puts("Total Units: #{total_units}")

    unit_types = spec.levels |> Enum.map(& &1.unit_type) |> Enum.uniq()
    IO.puts("Unit Types: #{Enum.join(unit_types, ", ")}")

    IO.puts("Connectivity:")
    IO.puts("  Predecessor Prob: #{spec.connectivity_config.predecessor_prob}")
    IO.puts("  Lateral Prob: #{spec.connectivity_config.lateral_prob}")
    IO.puts("  Skip Prob: #{spec.connectivity_config.skip_prob}")
  end
end
