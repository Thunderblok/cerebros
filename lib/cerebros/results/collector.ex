defmodule Cerebros.Results.Collector do
  @moduledoc """
  Collects, persists, and analyzes neural architecture search results.

  This module handles result storage, performance analysis, architecture
  ranking, and export functionality for completed trials.
  """

  use GenServer
  require Logger

  alias Cerebros.Architecture.Spec

  @type result :: %{
    trial_id: String.t(),
    architecture: map(),
    training_time_ms: non_neg_integer(),
    epochs_trained: non_neg_integer(),
    training_metrics: map(),
    final_metrics: map(),
    model_size: non_neg_integer(),
    spec_hash: String.t(),
    completed_at: String.t()
  }

  @type analysis_result :: %{
    best_architectures: [result()],
    performance_summary: map(),
    architecture_insights: map(),
    recommendations: [String.t()]
  }

  # Client API

  @doc """
  Starts the results collector.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Stores a trial result.
  """
  @spec store_result(GenServer.server(), result()) :: :ok
  def store_result(collector, result) do
    GenServer.cast(collector, {:store_result, result})
  end

  @doc """
  Retrieves all stored results.
  """
  @spec get_all_results(GenServer.server()) :: [result()]
  def get_all_results(collector) do
    GenServer.call(collector, :get_all_results)
  end

  @doc """
  Gets the top N performing architectures by specified metric.
  """
  @spec get_top_architectures(GenServer.server(), String.t(), pos_integer()) :: [result()]
  def get_top_architectures(collector, metric \\ "accuracy", top_n \\ 10) do
    GenServer.call(collector, {:get_top_architectures, metric, top_n})
  end

  @doc """
  Returns a single best trial by the provided metric (default: "accuracy").
  If metric is prefixed with '-', performs ascending sort (useful for loss).
  Returns {:ok, result} or :none if no completed results.
  """
  @spec best_trial(GenServer.server(), String.t()) :: {:ok, result()} | :none
  def best_trial(collector, metric \\ "accuracy") do
    GenServer.call(collector, {:best_trial, metric})
  end
  @doc """
  Heuristic ranking of results using `Cerebros.Search.Ranking`.

  Options:
    * :weights => override weight map
    * :limit   => integer limit or :all (default)
  Returns list of {score, result} sorted desc.
  """
  @spec rank_results(GenServer.server(), keyword()) :: [{float(), result()}]
  def rank_results(collector, opts \\ []) do
    GenServer.call(collector, {:rank_results, opts})
  end

  @doc """
  Analyzes all collected results and provides insights.
  """
  @spec analyze_results(GenServer.server()) :: analysis_result()
  def analyze_results(collector) do
    GenServer.call(collector, :analyze_results)
  end

  @doc """
  Exports results to various formats.
  """
  @spec export_results(GenServer.server(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def export_results(collector, format, file_path) do
    GenServer.call(collector, {:export_results, format, file_path})
  end

  @doc """
  Clears all stored results.
  """
  @spec clear_results(GenServer.server()) :: :ok
  def clear_results(collector) do
    GenServer.call(collector, :clear_results)
  end

  # GenServer Implementation

  @impl GenServer
  def init(opts) do
    storage_backend = Keyword.get(opts, :storage_backend, :memory)
    storage_path = Keyword.get(opts, :storage_path, "./results")

    state = %{
      results: [],
      storage_backend: storage_backend,
      storage_path: storage_path,
      analysis_cache: %{}
    }

    # Load existing results if using file storage
    state = if storage_backend == :file, do: load_existing_results(state), else: state

    Logger.info("Results collector started with #{length(state.results)} existing results")

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:store_result, result}, state) do
    Logger.info("Storing result for trial #{result.trial_id}")

    # Add result to collection
    new_results = [result | state.results]

    # Persist if using file storage
    new_state = %{state | results: new_results, analysis_cache: %{}}
    new_state = if state.storage_backend == :file, do: persist_results(new_state), else: new_state

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_call(:get_all_results, _from, state) do
    {:reply, state.results, state}
  end

  @impl GenServer
  def handle_call({:get_top_architectures, metric, top_n}, _from, state) do
    top_results =
      state.results
      |> filter_completed_results()
      |> sort_by_metric(metric)
      |> Enum.take(top_n)

    {:reply, top_results, state}
  end

  @impl GenServer
  def handle_call({:best_trial, metric}, _from, state) do
    completed = filter_completed_results(state.results)
    reply =
      case completed do
        [] -> :none
        _ ->
          [best | _] = sort_by_metric(completed, metric)
          {:ok, best}
      end
    {:reply, reply, state}
  end
  @impl GenServer
  def handle_call({:rank_results, opts}, _from, state) do
    weights = Keyword.get(opts, :weights, %{})
    limit = Keyword.get(opts, :limit, :all)

    ranked =
      state.results
      |> filter_completed_results()
      |> Cerebros.Search.Ranking.rank(weights)
      |> maybe_limit(limit)

    {:reply, ranked, state}
  end

  @impl GenServer
  def handle_call(:analyze_results, _from, state) do
    # Check cache first
    case Map.get(state.analysis_cache, :full_analysis) do
      nil ->
        analysis = perform_analysis(state.results)
        new_cache = Map.put(state.analysis_cache, :full_analysis, analysis)
        new_state = %{state | analysis_cache: new_cache}
        {:reply, analysis, new_state}

      cached_analysis ->
        {:reply, cached_analysis, state}
    end
  end

  @impl GenServer
  def handle_call({:export_results, format, file_path}, _from, state) do
    result = do_export_results(state.results, format, file_path)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:clear_results, _from, state) do
    new_state = %{state | results: [], analysis_cache: %{}}
    new_state = if state.storage_backend == :file, do: clear_persisted_results(new_state), else: new_state
    {:reply, :ok, new_state}
  end

  # Private functions

  defp filter_completed_results(results) do
    Enum.filter(results, fn result ->
      Map.has_key?(result, :final_metrics) and not is_nil(result.final_metrics)
    end)
  end

  defp sort_by_metric(results, metric) do
    {metric, order} =
      case String.starts_with?(metric, "-") do
        true -> {String.trim_leading(metric, "-"), :asc}
        false -> {metric, :desc}
      end

    sorter = fn result -> get_metric_value(result, metric) end
    Enum.sort_by(results, sorter, order)
  end

  defp get_metric_value(result, metric) do
    result.final_metrics
    |> Map.get(metric, 0.0)
    |> ensure_numeric()
  end

  defp ensure_numeric(value) when is_number(value), do: value
  defp ensure_numeric(_), do: 0.0

  defp perform_analysis(results) do
    completed_results = filter_completed_results(results)

    if Enum.empty?(completed_results) do
      %{
        best_architectures: [],
        performance_summary: %{total_trials: length(results), completed_trials: 0},
        architecture_insights: %{},
        recommendations: ["No completed trials available for analysis."]
      }
    else
      %{
        best_architectures: get_best_architectures(completed_results),
        performance_summary: compute_performance_summary(completed_results),
        architecture_insights: analyze_architecture_patterns(completed_results),
        recommendations: generate_recommendations(completed_results)
      }
    end
  end

  defp get_best_architectures(results) do
    # Get top performers across different metrics
    metrics = ["accuracy", "loss", "training_time_ms"]

    metrics
    |> Enum.flat_map(fn metric ->
      results
      |> sort_by_metric(metric)
      |> Enum.take(3)
      |> Enum.map(fn result -> Map.put(result, :best_for_metric, metric) end)
    end)
    |> Enum.uniq_by(& &1.trial_id)
  end

  defp compute_performance_summary(results) do
    metrics = extract_all_metrics(results)

    metric_stats =
      metrics
      |> Enum.into(%{}, fn metric ->
        values =
          results
          |> Enum.map(&get_metric_value(&1, metric))
          |> Enum.filter(&(&1 > 0))

        stats = if Enum.empty?(values) do
          %{mean: 0.0, std: 0.0, min: 0.0, max: 0.0, count: 0}
        else
          %{
            mean: Enum.sum(values) / length(values),
            std: standard_deviation(values),
            min: Enum.min(values),
            max: Enum.max(values),
            count: length(values)
          }
        end

        {metric, stats}
      end)

    %{
      total_trials: length(results),
      completed_trials: length(results),
      metric_statistics: metric_stats,
      average_training_time: compute_average_training_time(results),
      model_size_distribution: analyze_model_sizes(results)
    }
  end

  defp analyze_architecture_patterns(results) do
    # Analyze patterns in successful architectures
    architectures = Enum.map(results, & &1.architecture)

    %{
      level_count_distribution: analyze_level_counts(architectures),
      unit_type_preferences: analyze_unit_types(architectures),
      connectivity_patterns: analyze_connectivity_patterns(architectures),
      performance_correlations: find_performance_correlations(results)
    }
  end

  defp generate_recommendations(results) do
    recommendations = []

    # Analyze training time vs performance
    recommendations =
      case analyze_efficiency(results) do
        {:efficient_found, arch} ->
          ["Consider architectures similar to trial #{arch.trial_id} for good efficiency trade-offs" | recommendations]

        :need_more_trials ->
          ["Run more trials to identify efficiency patterns" | recommendations]
      end

    # Analyze architecture complexity
    recommendations =
      case analyze_complexity_trends(results) do
        {:sweet_spot, level_range} ->
          ["Optimal performance found with #{level_range} levels" | recommendations]
        :need_more_trials ->
          ["Need more trials to determine complexity trends" | recommendations]
      end

    # General recommendations
    recommendations = [
      "Monitor validation metrics to prevent overfitting",
      "Consider early stopping with patience=10-15",
      "Experiment with different activation functions"
      | recommendations
    ]

    recommendations
  end

  defp extract_all_metrics(results) do
    results
    |> Enum.flat_map(fn result ->
      Map.keys(result.final_metrics || %{})
    end)
    |> Enum.uniq()
  end

  defp standard_deviation(values) do
    mean = Enum.sum(values) / length(values)
    variance =
      values
      |> Enum.map(fn x -> :math.pow(x - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(values))

    :math.sqrt(variance)
  end

  defp compute_average_training_time(results) do
    times = Enum.map(results, & &1.training_time_ms)

    if Enum.empty?(times) do
      0
    else
      Enum.sum(times) / length(times)
    end
  end

  defp analyze_model_sizes(results) do
    sizes = Enum.map(results, & &1.model_size)

    %{
      min_size: Enum.min(sizes, fn -> 0 end),
      max_size: Enum.max(sizes, fn -> 0 end),
      avg_size: if(Enum.empty?(sizes), do: 0, else: Enum.sum(sizes) / length(sizes)),
      size_buckets: bucket_sizes(sizes)
    }
  end

  defp bucket_sizes(sizes) do
    # Create size distribution buckets
    max_size = Enum.max(sizes, fn -> 1 end)
    bucket_size = max(div(max_size, 5), 1)

    sizes
    |> Enum.group_by(fn size -> div(size, bucket_size) end)
    |> Enum.into(%{}, fn {bucket, size_list} ->
      range_start = bucket * bucket_size
      range_end = (bucket + 1) * bucket_size
      {"#{range_start}-#{range_end}", length(size_list)}
    end)
  end

  defp analyze_level_counts(architectures) do
    architectures
    |> Enum.map(& Map.get(&1, :num_levels, 0))
    |> Enum.frequencies()
  end

  defp analyze_unit_types(architectures) do
    architectures
    |> Enum.flat_map(& Map.get(&1, :unit_types, []))
    |> Enum.frequencies()
  end

  defp analyze_connectivity_patterns(architectures) do
    architectures
    |> Enum.map(& Map.get(&1, :connectivity_patterns, %{}))
    |> Enum.reduce(%{}, fn patterns, acc ->
      Map.merge(acc, patterns, fn _k, v1, v2 when is_number(v1) and is_number(v2) ->
        (v1 + v2) / 2
      end)
    end)
  end

  defp find_performance_correlations(_results) do
    # Simple correlation analysis between architecture features and performance
    # This would be more sophisticated in a real implementation
    %{
      "complexity_vs_accuracy" => "positive_correlation",
      "training_time_vs_accuracy" => "weak_correlation"
    }
  end

  defp analyze_efficiency(results) do
    # Find architectures with good accuracy/time trade-offs
    efficiency_scores =
      results
      |> Enum.map(fn result ->
        accuracy = get_metric_value(result, "accuracy")
        time = result.training_time_ms
        efficiency = if time > 0, do: accuracy / :math.log(time + 1), else: 0
        {efficiency, result}
      end)
      |> Enum.sort_by(fn {score, _} -> score end, :desc)

    case efficiency_scores do
      [{_score, best_arch} | _] when length(results) > 5 ->
        {:efficient_found, best_arch}

      _ ->
        :need_more_trials
    end
  end

  defp analyze_complexity_trends(results) do
    # Analyze relationship between complexity and performance
    level_performance =
      results
      |> Enum.map(fn result ->
        levels = get_in(result, [:architecture, :num_levels]) || 0
        accuracy = get_metric_value(result, "accuracy")
        {levels, accuracy}
      end)
      |> Enum.group_by(fn {levels, _} -> levels end)
      |> Enum.into(%{}, fn {levels, pairs} ->
        accuracies = Enum.map(pairs, fn {_, acc} -> acc end)
        avg_acc = if Enum.empty?(accuracies), do: 0, else: Enum.sum(accuracies) / length(accuracies)
        {levels, avg_acc}
      end)

    case Enum.max_by(level_performance, fn {_, acc} -> acc end, fn -> {0, 0} end) do
      {best_levels, _} when best_levels >= 5 -> {:sweet_spot, "4-6"}
      {best_levels, _} when best_levels >= 3 -> {:sweet_spot, "3-5"}
      _ -> :need_more_trials
    end
  end

  defp do_export_results(results, "json", file_path) do
    try do
      json_data = Jason.encode!(results, pretty: true)
      File.write!(file_path, json_data)
      Logger.info("Results exported to #{file_path}")
      :ok
    rescue
      error -> {:error, Exception.message(error)}
    end
  end

  defp do_export_results(results, "csv", file_path) do
    try do
      # Convert to CSV format
      csv_content = results_to_csv(results)
      File.write!(file_path, csv_content)
      Logger.info("Results exported to #{file_path}")
      :ok
    rescue
      error -> {:error, Exception.message(error)}
    end
  end

  defp do_export_results(_results, format, _file_path) do
    {:error, "Unsupported export format: #{format}"}
  end

  defp results_to_csv(results) do
    if Enum.empty?(results) do
      "No results to export\n"
    else
      # Create CSV header
      headers = ["trial_id", "accuracy", "loss", "training_time_ms", "model_size", "num_levels"]
      header_line = Enum.join(headers, ",") <> "\n"

      # Create CSV rows
      rows =
        results
        |> Enum.map(fn result ->
          [
            result.trial_id,
            get_metric_value(result, "accuracy"),
            get_metric_value(result, "loss"),
            result.training_time_ms,
            result.model_size,
            get_in(result, [:architecture, :num_levels]) || 0
          ]
          |> Enum.join(",")
        end)
        |> Enum.join("\n")

      header_line <> rows <> "\n"
    end
  end

  defp maybe_limit(list, :all), do: list
  defp maybe_limit(list, n) when is_integer(n) and n > 0, do: Enum.take(list, n)
  defp maybe_limit(list, _), do: list

  defp load_existing_results(state) do
    results_file = Path.join(state.storage_path, "results.json")

    case File.read(results_file) do
      {:ok, content} ->
        try do
          results = Jason.decode!(content)
          Logger.info("Loaded #{length(results)} existing results")
          %{state | results: results}
        rescue
          _ ->
            Logger.warning("Failed to parse existing results file")
            state
        end

      {:error, _} ->
        Logger.info("No existing results file found")
        state
    end
  end

  defp persist_results(state) do
    File.mkdir_p!(state.storage_path)
    results_file = Path.join(state.storage_path, "results.json")

    try do
      content = Jason.encode!(state.results, pretty: true)
      File.write!(results_file, content)
    rescue
      error ->
        Logger.error("Failed to persist results: #{Exception.message(error)}")
    end

    state
  end

  defp clear_persisted_results(state) do
    results_file = Path.join(state.storage_path, "results.json")

    case File.rm(results_file) do
      :ok -> Logger.info("Cleared persisted results")
  {:error, _} -> Logger.warning("No persisted results to clear")
    end

    state
  end
end
