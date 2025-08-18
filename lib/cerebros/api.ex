defmodule Cerebros.API do
  @moduledoc """
  Public integration API for programmatic Neural Architecture Search runs.

  Provides a stable `run_search/1` entrypoint used by external orchestrators (e.g. Thunderline).

  Contract (subset / forward compatible):
    Input map keys (all optional unless noted):
      :task               - :regression | :classification | atom() (default :regression)
      :input_shapes       - list of tuples (default [{10}])
      :output_shapes      - list of tuples (default [{1}])
      :trials             - total trial count (architectures * per-arch trials) (default 6)
      :epochs             - training epochs per trial (default 5)
      :batch_size         - batch size (default 32)
      :learning_rate      - LR (default 0.001)
  :parameter_estimation_mode - :full | :approximate | :auto | :skip (default nil -> legacy behaviour: full unless skip flag)
      :seed               - integer seed (optional)
      :time_budget_ms     - soft wall clock budget for entire search (default :infinity)
      :artifact_store     - %{kind: :fs, path: String.t()} (default fs ./results)
      :telemetry_run_id   - string id injected into telemetry metadata (auto UUID if absent)
      :extra              - map of extra knobs (ignored by core logic, echoed back)

    Returns {:ok, result_map} | {:error, reason}

    result_map fields:
      :run_id, :best_metric, :best_trial, :trials, :artifact_path, :metrics_summary, :version

  Telemetry events emitted:
    [:cerebros, :search, :progress]   measurements %{completed, total, best_metric} meta %{run_id: run_id}
    [:cerebros, :trial, :completed]   measurements %{metric, duration_ms, params?} meta %{trial_id, run_id}
  """
  require Logger
  alias Cerebros.Training.Orchestrator

  @spec run_search(map()) :: {:ok, map()} | {:error, term()}
  def run_search(spec) when is_map(spec) do
    ensure_telemetry()
    ensure_nx()
    run_id = Map.get(spec, :telemetry_run_id) || uuid()
    seed = Map.get(spec, :seed)
    if seed, do: :rand.seed(:exsss, {seed, seed + 1, seed + 2})

    total_trials = Map.get(spec, :trials, 6)
    # Provide a simple factorization into architectures × trials-per-architecture
    {arches, per_arch} = factor_trials(total_trials)

    {dataset, inferred_in_shapes, inferred_out_shapes} = resolve_dataset(spec)

    config = %{
      input_shapes: Map.get(spec, :input_shapes, inferred_in_shapes || [{10}]),
      output_shapes: Map.get(spec, :output_shapes, inferred_out_shapes || [{1}]),
      number_of_architectures_to_try: arches,
      number_of_trials_per_architecture: per_arch,
      epochs: Map.get(spec, :epochs, 5),
      batch_size: Map.get(spec, :batch_size, 32),
      learning_rate: Map.get(spec, :learning_rate, 0.001),
  parameter_estimation_mode: Map.get(spec, :parameter_estimation_mode, nil),
      minimum_levels: Map.get(spec, :minimum_levels, 1),
  maximum_levels: Map.get(spec, :maximum_levels, 3),
  # Additional pass-through knobs for parity with Python prototype
  minimum_units_per_level: Map.get(spec, :minimum_units_per_level, 1),
  maximum_units_per_level: Map.get(spec, :maximum_units_per_level, 3),
  minimum_neurons_per_unit: Map.get(spec, :minimum_neurons_per_unit, 4),
  maximum_neurons_per_unit: Map.get(spec, :maximum_neurons_per_unit, 32),
  disable_epoch_adaptation: Map.get(spec, :disable_epoch_adaptation, false),
  early_stop_patience: Map.get(spec, :early_stop_patience, 10),
  early_stop?: Map.get(spec, :early_stop?, true),
  parameter_budget: Map.get(spec, :parameter_budget, nil),
  skip_param_estimation: Map.get(spec, :skip_param_estimation, false),
  max_batches_per_epoch: Map.get(spec, :max_batches_per_epoch, nil),
  merge_strategy_pool: Map.get(spec, :merge_strategy_pool, [:concatenate]),
  max_merge_width: Map.get(spec, :max_merge_width, nil),
  projection_after_merge: Map.get(spec, :projection_after_merge, true),
  projection_activation: Map.get(spec, :projection_activation, :relu)
    }

    artifact_store = Map.get(spec, :artifact_store, %{kind: :fs, path: "./results"})
    time_budget_ms = Map.get(spec, :time_budget_ms, :infinity)

    Logger.info("[Cerebros.API] run_id=#{run_id} starting search total_trials=#{total_trials} time_budget=#{inspect(time_budget_ms)}")
    emit_progress(run_id, 0, total_trials, :nan)

    # Dataset (synthetic by default; overridden by :dataset option)
    ds =
      case dataset do
        nil -> generate_dataset(config)
        %{train_x: _, train_y: _, validation_x: _, validation_y: _} = m -> maybe_normalize_targets(m, Map.get(spec, :normalize_targets, false))
      end

    {:ok, orchestrator} = Orchestrator.start_link(%{
      max_concurrent: Map.get(spec, :max_concurrent, 2),
      search_params: config,
      dataset: ds
    })

    GenServer.cast(orchestrator, {:start_search, config})

    start_ms = System.monotonic_time(:millisecond)
    poll_loop(run_id, orchestrator, total_trials, start_ms, time_budget_ms)
    results = GenServer.call(orchestrator, :get_results)

    GenServer.stop(orchestrator)

    {best_trial, best_metric} = best_trial(results)
    artifact_path = persist_artifact(run_id, best_trial, artifact_store)
    summary = metric_summary(results)
    version = cerebros_version()

    debug? = Map.get(spec, :debug_metrics, false)
    if debug? do
      vlosses = Enum.map(results, & &1.validation_loss)
      Logger.debug("[Cerebros.API] debug_metrics validation_losses=#{inspect(vlosses)} raw_results_count=#{length(results)}")
    end

    {:ok, %{
      run_id: run_id,
      best_metric: best_metric,
      best_trial: sanitize_trial(best_trial),
      trials: total_trials,
      artifact_path: artifact_path,
      metrics_summary: summary,
      version: version,
      extra: Map.get(spec, :extra, %{})
  } |> maybe_put_raw_trials(results, debug?)}
  catch
    kind, reason -> {:error, {kind, reason, __STACKTRACE__}}
  end

  # Accept :dataset in spec:
  #   :ames -> loads Ames dataset via existing loader (if available)
  #   %{train_x: Nx.t(), train_y: Nx.t(), validation_x: Nx.t(), validation_y: Nx.t()} -> used directly
  # Returns {dataset_map | nil, inferred_input_shapes | nil, inferred_output_shapes | nil}
  defp resolve_dataset(spec) do
    case Map.get(spec, :dataset, :synthetic) do
      :synthetic -> {nil, Map.get(spec, :input_shapes, [{10}]), Map.get(spec, :output_shapes, [{1}])}
      :ames ->
        case safe_load_ames() do
          {:ok, ds = %{train_x: tx, train_y: ty}} ->
            in_shape = [{elem(Nx.shape(tx), 1)}]
            out_shape = [{elem(Nx.shape(ty), 1)}]
            {ds, in_shape, out_shape}
          {:error, _} -> {nil, Map.get(spec, :input_shapes, [{10}]), Map.get(spec, :output_shapes, [{1}])}
        end
      %{} = custom ->
        # Expect required keys; infer shapes defensively
        with true <- Map.has_key?(custom, :train_x),
             true <- Map.has_key?(custom, :train_y),
             true <- Map.has_key?(custom, :validation_x),
             true <- Map.has_key?(custom, :validation_y) do
          tx = custom.train_x; ty = custom.train_y
          in_shape = [{elem(Nx.shape(tx), 1)}]
          out_shape = [{elem(Nx.shape(ty), 1)}]
          {custom, in_shape, out_shape}
        else
          _ -> {nil, Map.get(spec, :input_shapes, [{10}]), Map.get(spec, :output_shapes, [{1}])}
        end
      other ->
        Logger.warning("[Cerebros.API] Unknown dataset option #{inspect(other)} – falling back to synthetic")
        {nil, Map.get(spec, :input_shapes, [{10}]), Map.get(spec, :output_shapes, [{1}])}
    end
  end

  defp safe_load_ames do
    try do
      case apply(Cerebros, :load_ames_data, []) do
        {:ok, {train_x, train_y, val_x, val_y, _feat_count}} ->
          {:ok, %{train_x: train_x, train_y: train_y, validation_x: val_x, validation_y: val_y}}
        other -> other
      end
    rescue e -> {:error, Exception.message(e)} end
  end

  defp factor_trials(t) when t <= 0, do: {1, 1}
  defp factor_trials(1), do: {1, 1}
  defp factor_trials(t) do
  # Choose per_arch <= 4 for reasonable parallelism
  per_arch = Enum.find(4..1//-1, fn x -> rem(t, x) == 0 end) || 1
    {div(t, per_arch), per_arch}
  end

  defp poll_loop(run_id, orch, total, start_ms, budget_ms) do
    :timer.sleep(300)
    now = System.monotonic_time(:millisecond)
    results = GenServer.call(orch, :get_results)
    completed = length(results)
    {_, best_metric} = best_trial(results)
    emit_progress(run_id, completed, total, best_metric)
    Enum.each(newly_completed(results), fn tr ->
      emit_trial_completed(run_id, tr)
    end)
    cond do
      completed >= total -> :ok
      budget_ms != :infinity and now - start_ms >= budget_ms -> Logger.warning("[Cerebros.API] run_id=#{run_id} time budget exceeded – stopping early")
      true -> poll_loop(run_id, orch, total, start_ms, budget_ms)
    end
  end

  # Track which trials we've already announced (store in process dictionary for simplicity)
  defp newly_completed(results) do
    announced = Process.get(:c_completed_ids, MapSet.new())
    done = Enum.filter(results, &match?(%{status: :completed}, &1))
    new = Enum.filter(done, fn t -> not MapSet.member?(announced, t.trial_id) end)
    Process.put(:c_completed_ids, Enum.reduce(new, announced, fn t, acc -> MapSet.put(acc, t.trial_id) end))
    new
  end

  defp best_trial([]), do: {nil, :nan}
  defp best_trial(trials) do
    completed = Enum.filter(trials, &match?(%{validation_loss: v} when is_number(v), &1))
    case completed do
      [] -> {nil, :nan}
      list ->
        bt = Enum.min_by(list, & &1.validation_loss)
        {bt, bt.validation_loss}
    end
  end

  defp metric_summary(trials) do
    vals = trials |> Enum.map(& &1.validation_loss) |> Enum.filter(&is_number/1) |> Enum.sort()
    n = length(vals)
    median =
      cond do
        n == 0 -> :nan
        rem(n, 2) == 1 -> Enum.at(vals, div(n, 2))
        true ->
          # Even sample size: average the two middle values
          i = div(n, 2)
          (Enum.at(vals, i - 1) + Enum.at(vals, i)) / 2
      end

    p95 =
      if n == 0 do
        :nan
      else
        # Use ceil for percentile rank then clamp to last index
        idx = min(n - 1, max(0, trunc(Float.ceil(n * 0.95)) - 1))
        Enum.at(vals, idx)
      end

    %{median: median, p95: p95, count: n}
  end

  defp persist_artifact(run_id, nil, _store), do: nil
  defp persist_artifact(run_id, trial, %{kind: :fs, path: base}) do
    dir = Path.join(base, run_id)
    File.mkdir_p!(dir)
    file = Path.join(dir, "best_trial.json")
    File.write!(file, Jason.encode!(sanitize_trial(trial), pretty: true))
    dir
  rescue
    e -> Logger.error("[Cerebros.API] artifact persist failed: #{inspect(e)}"); nil
  end
  defp persist_artifact(_run_id, _trial, _other), do: nil

  defp maybe_put_raw_trials(result_map, _trials, false), do: result_map
  defp maybe_put_raw_trials(result_map, trials, true), do: Map.put(result_map, :raw_trials, sanitize_trials(trials))

  # Normalize regression targets (y) to zero mean / unit variance for stability if requested.
  defp maybe_normalize_targets(ds, false), do: ds
  defp maybe_normalize_targets(%{train_x: tx, train_y: ty, validation_x: vx, validation_y: vy} = ds, true) do
    mean = Nx.mean(ty)
    std = Nx.standard_deviation(ty) |> Nx.add(1.0e-7)
    %{
      ds |
      train_y: ty |> Nx.subtract(mean) |> Nx.divide(std),
      validation_y: vy |> Nx.subtract(mean) |> Nx.divide(std),
      target_norm: %{mean: Nx.to_number(mean), std: Nx.to_number(std)}
    }
  end

  defp sanitize_trial(nil), do: nil
  defp sanitize_trial(trial) do
    Map.take(trial, [:trial_id, :validation_loss, :model_size, :architecture, :epochs_trained])
  end

  defp sanitize_trials(trials) do
    Enum.map(trials, &sanitize_trial/1)
  end

  defp generate_dataset(config) do
    # Local synthetic dataset generator (mirrors logic in Cerebros.generate_test_dataset/1
    # but kept private there). We duplicate here to keep API self‑contained.
    [input_shape] = Map.get(config, :input_shapes, [{10}])
    [output_shape] = Map.get(config, :output_shapes, [{1}])
    input_dim = elem(input_shape, 0)
    output_dim = elem(output_shape, 0)
    batch_size = Map.get(config, :batch_size, 32)
    base_samples = 1000
    num_samples = div(base_samples, batch_size) * batch_size
    train_split = 0.7
    train_samples = round(num_samples * train_split)
    val_samples = num_samples - train_samples

    train_x = normal({train_samples, input_dim}, 0.0, 1.0, 10)
    val_x   = normal({val_samples, input_dim}, 0.0, 1.0, 11)
    train_noise = normal({train_samples, output_dim}, 0.0, 0.1, 12)
    val_noise   = normal({val_samples, output_dim}, 0.0, 0.1, 13)

    train_y =
      train_x
      |> Nx.sum(axes: [1], keep_axes: true)
      |> Nx.add(train_noise)

    val_y =
      val_x
      |> Nx.sum(axes: [1], keep_axes: true)
      |> Nx.add(val_noise)

    %{
      train_x: train_x,
      train_y: train_y,
      validation_x: val_x,
      validation_y: val_y
    }
  end

  # Minimal local normal RNG replicating helper in main module (Box-Muller)
  defp normal(shape, mean, sigma, seed) do
    :rand.seed(:exsss, {seed, seed + 1, seed + 2})
    dims = Tuple.to_list(shape)
    total = Enum.reduce(dims, 1, &(&1 * &2))
    values =
      Stream.repeatedly(fn ->
        u1 = :rand.uniform()
        u2 = :rand.uniform()
        r = :math.sqrt(-2.0 * :math.log(u1))
        theta = 2.0 * :math.pi * u2
        z0 = r * :math.cos(theta)
        z1 = r * :math.sin(theta)
        [z0, z1]
      end)
      |> Stream.flat_map(& &1)
      |> Enum.take(total)
      |> Enum.map(fn z -> z * sigma + mean end)
    Nx.tensor(values, type: :f32) |> Nx.reshape(shape)
  end

  defp emit_progress(run_id, completed, total, best_metric) do
    if Code.ensure_loaded?(:telemetry) do
      :telemetry.execute([:cerebros, :search, :progress], %{completed: completed, total: total, best_metric: best_metric}, %{run_id: run_id})
    end
  end

  defp emit_trial_completed(run_id, trial) do
    meas = %{
      metric: trial.validation_loss || :nan,
      duration_ms: Map.get(trial, :training_time_ms, :unknown),
      params: trial.model_size
    }
    if Code.ensure_loaded?(:telemetry) do
      :telemetry.execute([:cerebros, :trial, :completed], meas, %{run_id: run_id, trial_id: trial.trial_id})
    end
  end

  defp uuid do
    binary = :crypto.strong_rand_bytes(16)
    <<a1::32, a2::16, a3::16, a4::16, a5::48>> = binary
    <<v3::16, v4::16>> = <<a2::16, a3::16>>
    Enum.map_join([a1, v3, v4, a4, a5], "-", &Integer.to_string(&1, 16))
  end

  defp cerebros_version do
    case :application.get_key(:cerebros, :vsn) do
      {:ok, vsn} -> List.to_string(vsn)
      _ -> "unknown"
    end
  end

  defp ensure_telemetry do
    case Application.ensure_all_started(:telemetry) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp ensure_nx do
    # Start Nx (and transitively its dependencies). EXLA will start lazily if compiled.
    _ = Application.ensure_all_started(:nx)
    :ok
  end
end
