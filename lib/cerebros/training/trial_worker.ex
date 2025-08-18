defmodule Cerebros.Training.TrialWorker do
  @moduledoc """
  Worker process that trains a single neural architecture candidate.

  This module handles the complete training lifecycle for one architecture:
  - Building the Axon model from the specification
  - Compiling with training configuration
  - Running the training loop
  - Collecting and reporting results
  """

  use GenServer
  require Logger

  alias Cerebros.Architecture.Spec
  alias Cerebros.Networks.Builder
  alias Cerebros.Data.Loader

  @type worker_state :: %{
    trial_id: String.t(),
    spec: Spec.t(),
    training_config: map(),
    orchestrator: pid(),
    model: Axon.t() | nil,
    loop: Axon.Loop.t() | nil,
    training_data: any() | nil,
    validation_data: any() | nil,
    start_time: DateTime.t(),
    metrics: map()
  }

  # Client API

  @doc """
  Starts a trial worker for a specific architecture.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  # GenServer Implementation

  @impl GenServer
  def init(opts) do
    trial_id = Keyword.fetch!(opts, :trial_id)
    spec = Keyword.fetch!(opts, :spec)
    training_config = Keyword.fetch!(opts, :training_config)
    orchestrator = Keyword.fetch!(opts, :orchestrator)

    state = %{
      trial_id: trial_id,
      spec: spec,
      training_config: training_config,
      orchestrator: orchestrator,
      model: nil,
      loop: nil,
      training_data: nil,
      validation_data: nil,
      start_time: DateTime.utc_now(),
      metrics: %{}
    }

    Logger.info("Trial worker #{trial_id} started")

    # Start the training process immediately
    send(self(), :start_training)

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:start_training, state) do
    try do
      # Execute the complete training pipeline
      result = execute_training_pipeline(state)

      # Report success to orchestrator
      send(state.orchestrator, {:trial_completed, state.trial_id, result})

      {:stop, :normal, state}
    rescue
      error ->
        stacktrace = __STACKTRACE__
        error_msg = Exception.message(error)
        Logger.error("Trial #{state.trial_id} failed: #{error_msg}\n" <>
                     Enum.map_join(stacktrace, "\n", &Exception.format_stacktrace_entry/1))

        # Report failure to orchestrator
        send(state.orchestrator, {:trial_failed, state.trial_id, error_msg})

        {:stop, :normal, state}
    end
  end

  # Private functions

  defp execute_training_pipeline(state) do
    %{
      trial_id: trial_id,
      spec: spec,
      training_config: training_config
    } = state

    phase_t0 = System.monotonic_time(:millisecond)
    Logger.info("Building model for trial #{trial_id}")

    # Optional performance / backend diagnostics (lightweight, controlled by :debug_performance)
    if Map.get(training_config, :debug_performance, false) do
      backend = Nx.default_backend()
      exla_loaded? = Code.ensure_loaded?(EXLA.Backend)
      exla_target = System.get_env("EXLA_TARGET") || "(not set)"
      Logger.info("[perf][trial #{trial_id}] default_backend=#{inspect(backend)} exla_loaded?=#{exla_loaded?} EXLA_TARGET=#{exla_target}")
      if exla_loaded? do
        # Tiny JIT sanity check (guard against unexpected slow interpreter path)
        try do
          fun = Nx.Defn.jit(fn -> Nx.sum(Nx.iota({8})) end, compiler: EXLA)
          _ = fun.()
          Logger.debug("[perf][trial #{trial_id}] EXLA JIT sanity check ok")
        rescue
          e -> Logger.warning("[perf][trial #{trial_id}] EXLA JIT test failed: #{inspect(e)}")
        end
      else
        Logger.warning("[perf][trial #{trial_id}] EXLA not loaded – training will use pure interpreter and be slow. Call Cerebros.setup_exla_backend/0 before starting the search for major speedups.")
      end
    end

    # Step 1: Build the Axon model (spec -> Axon graph)
    {:ok, model} = Builder.build_model(spec)
    t_after_build = System.monotonic_time(:millisecond)

    # Step 2: Parameter budget estimation / enforcement
    param_budget = Map.get(training_config, :parameter_budget, nil)
    skip_flag = Map.get(training_config, :skip_param_estimation, false)
    estimation_mode =
      cond do
        mode = Map.get(training_config, :parameter_estimation_mode) -> mode
        skip_flag -> :skip
        true -> :full
      end

    {est_params, estimation_strategy} =
      case estimation_mode do
        :skip ->
          # Even in skip mode, do a cheap approximate count if we have a budget to allow early pruning
          if param_budget do
            {approximate_parameter_count(spec), :approximate_skip_for_budget}
          else
            {0, :skip}
          end
        :approximate -> {approximate_parameter_count(spec), :approximate}
        :auto ->
          # Heuristic: approximate for larger specs (many units) otherwise full
          summary = spec_to_summary(spec)
          total_units = summary.total_units
          if total_units > 50 do
            {approximate_parameter_count(spec), :approximate_auto}
          else
            {estimate_parameter_count(model, spec), :full_auto}
          end
        :full -> {estimate_parameter_count(model, spec), :full}
        other ->
          Logger.warning("Unknown parameter_estimation_mode=#{inspect(other)} falling back to :full")
          {estimate_parameter_count(model, spec), :full}
      end

    t_after_param_estimation = System.monotonic_time(:millisecond)

    if Map.get(training_config, :debug_performance, false) do
      Logger.info("[perf][trial #{trial_id}] parameter_estimation strategy=#{estimation_strategy} est_params=#{est_params} time_ms=#{t_after_param_estimation - t_after_build}")
    end

    if param_budget && est_params > 0 && est_params > param_budget do
      Logger.info("Skipping trial #{trial_id}: parameter budget exceeded (#{est_params} > #{param_budget})")
      %{
        trial_id: trial_id,
        architecture: spec_to_summary(spec),
        training_time_ms: 0,
        epochs_trained: 0,
        training_metrics: %{},
        final_metrics: %{},
        validation_loss: nil,
        model_size: est_params,
        spec_hash: spec_hash(spec),
        completed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        skipped: :parameter_budget_exceeded,
        estimated_parameters: est_params,
        parameter_estimation_strategy: estimation_strategy,
        phases_ms: %{
          build_model: t_after_build - phase_t0,
          parameter_estimation: t_after_param_estimation - t_after_build,
          compile: 0,
          training: 0,
          evaluation: 0
        }
      }
    else
      # Step 3: Load / attach training data
      {train_data_full, val_data} = load_training_data(training_config)
      max_batches = Map.get(training_config, :max_batches_per_epoch, nil)
      train_data =
        if max_batches && is_integer(max_batches) && max_batches > 0 do
          Stream.take(train_data_full, max_batches)
        else
          train_data_full
        end

      # Step 4: Compile the training loop (with compile time budget if wall clock timeout finite)
      compile_start = System.monotonic_time(:millisecond)
      timeout_ms = Map.get(training_config, :wall_clock_timeout_ms, :infinity)
      compile_budget_ms =
        case timeout_ms do
          :infinity -> :infinity
          ms when is_integer(ms) and ms > 5_000 ->
            # Reserve at least 1s for training/eval; use up to 30% of wall clock for compile
            budget = trunc(min(ms * 0.30, ms - 1_000))
            max(budget, 5_000)
          _ -> 5_000
        end

      loop =
        case compile_budget_ms do
          :infinity -> Builder.compile_model(model, training_config)
          b when is_integer(b) ->
            task = Task.async(fn -> Builder.compile_model(model, training_config) end)
            case Task.yield(task, b) || Task.shutdown(task, :brutal_kill) do
              {:ok, compiled} -> compiled
              nil -> :compile_timeout
              {:exit, reason} ->
                Logger.warning("Trial #{trial_id} compile task exited: #{inspect(reason)}")
                :compile_failed
            end
        end
      compile_end = System.monotonic_time(:millisecond)
      compile_time = compile_end - compile_start
      if Map.get(training_config, :debug_performance, false) do
        Logger.info("[perf][trial #{trial_id}] compile_time_ms=#{compile_time} compile_budget_ms=#{inspect(compile_budget_ms)}")
      end

      if loop in [:compile_timeout, :compile_failed] do
        reason = if loop == :compile_timeout, do: :compile_timeout, else: :compile_failed
        Logger.info("Skipping trial #{trial_id}: #{reason}")
        %{
          trial_id: trial_id,
          architecture: spec_to_summary(spec),
          training_time_ms: 0,
          epochs_trained: 0,
          training_metrics: %{},
          final_metrics: %{},
          validation_loss: nil,
          model_size: est_params,
          spec_hash: spec_hash(spec),
          completed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          skipped: reason,
          estimated_parameters: est_params,
          parameter_estimation_strategy: estimation_strategy,
          epochs_requested: Map.get(training_config, :epochs, 0),
          phases_ms: %{
            build_model: t_after_build - phase_t0,
            parameter_estimation: t_after_param_estimation - t_after_build,
            compile: compile_time,
            training: 0,
            evaluation: 0
          }
        }
      else

        # Step 5: Run training
        Logger.info("Starting training for trial #{trial_id}")
        training_start = System.monotonic_time(:millisecond)

        configured_loop =
          loop
          |> Axon.Loop.validate(model, val_data)
          |> maybe_attach_early_stop(training_config)
          |> Axon.Loop.checkpoint(event: :epoch_completed, filter: [every: 10])

        original_epochs = Map.get(training_config, :epochs, 50)
        epochs = adapt_epochs(original_epochs, est_params, training_config)
        if epochs != original_epochs do
          Logger.info("Trial #{trial_id}: reducing epochs from #{original_epochs} -> #{epochs} (est_params=#{est_params})")
        end

        initial_state = %Axon.ModelState{data: %{}}
        timeout_ms = Map.get(training_config, :wall_clock_timeout_ms, :infinity)
        final_params =
          if timeout_ms == :infinity do
            Axon.Loop.run(configured_loop, train_data, initial_state, epochs: epochs)
          else
            task = Task.async(fn -> Axon.Loop.run(configured_loop, train_data, initial_state, epochs: epochs) end)
            case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
              {:ok, params} -> params
              nil -> raise "Trial #{trial_id} exceeded wall clock timeout #{timeout_ms}ms"
              {:exit, reason} -> raise reason
            end
          end

        training_end = System.monotonic_time(:millisecond)
        training_time = training_end - training_start
        Logger.info("Training completed for trial #{trial_id} in #{training_time}ms")
        if Map.get(training_config, :debug_performance, false) do
          Logger.info("[perf][trial #{trial_id}] training_time_ms=#{training_time} epochs_trained=#{epochs} batches_per_epoch=#{Map.get(training_config, :max_batches_per_epoch, :all)}")
        end

        # Step 6: Evaluate
        eval_start = System.monotonic_time(:millisecond)
        final_metrics = evaluate_model(model, final_params, val_data, training_config)
        eval_end = System.monotonic_time(:millisecond)
        if Map.get(training_config, :debug_performance, false) do
          Logger.info("[perf][trial #{trial_id}] evaluation_time_ms=#{eval_end - eval_start}")
        end

        validation_loss =
          case Map.get(final_metrics, "mean_squared_error") || Map.get(final_metrics, :mean_squared_error) do
            %Nx.Tensor{} = t -> Nx.to_number(t)
            v when is_number(v) -> v
            _ -> nil
          end

        %{
          trial_id: trial_id,
          architecture: spec_to_summary(spec),
          training_time_ms: training_time,
          training_metrics: %{},
          final_metrics: final_metrics,
          validation_loss: validation_loss,
          model_size: count_parameters(final_params),
          spec_hash: spec_hash(spec),
          completed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          estimated_parameters: est_params,
          parameter_estimation_strategy: estimation_strategy,
          epochs_requested: original_epochs,
          epochs_trained: epochs,
          phases_ms: %{
            build_model: t_after_build - phase_t0,
            parameter_estimation: t_after_param_estimation - t_after_build,
            compile: compile_end - compile_start,
            training: training_end - training_start,
            evaluation: eval_end - eval_start
          }
        }
      end
    end
  end

  defp approximate_parameter_count(spec) do
    # Extremely rough dense-like approximation accounting for neuron transitions.
    spec.levels
    |> Enum.reduce({0, 0}, fn level, {prev_width, acc} ->
      # For each unit assume fully connected from aggregated previous width.
      # If prev_width is 0 (first level), treat as input size heuristically using first unit neurons.
      units = level.units
      level_params =
        units
        |> Enum.reduce({acc, prev_width}, fn u, {inner_acc, pw} ->
          n = u.neurons
          input_width = if pw == 0, do: n, else: pw
          # weights + bias
          params = input_width * n + n
          {inner_acc + params, pw + n}
        end)
      {new_acc, new_width} = level_params
      {new_width, new_acc}
    end)
    |> elem(1)
  end

  defp load_training_data(training_config) do
    dataset = Map.get(training_config, :dataset, :cifar10)
    batch_size = Map.get(training_config, :batch_size, 32)

    case dataset do
      :cifar10 ->
        Loader.load_cifar10(batch_size: batch_size)

      :mnist ->
        Loader.load_mnist(batch_size: batch_size)

      :synthetic ->
        input_shape = Map.get(training_config, :input_shape, {32, 32, 3})
        num_classes = Map.get(training_config, :num_classes, 10)
        Loader.generate_synthetic_data(input_shape, num_classes, batch_size: batch_size)

      custom_data when is_map(custom_data) ->
        # Allow passing custom data directly
        {custom_data.train, custom_data.validation}
    end
  end

  # (Removed manual parameter initialization; Axon.Loop handles this.)

  defp get_patience(training_config) do
    Map.get(training_config, :early_stop_patience, 10)
  end

  defp maybe_attach_early_stop(loop, training_config) do
    case Map.get(training_config, :early_stop?, true) do
      true -> Axon.Loop.early_stop(loop, "mean_squared_error", patience: get_patience(training_config))
      false -> loop
    end
  end

  defp evaluate_model(model, params, validation_data, training_config) do
    # Create evaluation loop
    eval_loop =
      Axon.Loop.evaluator(model)
      |> Axon.Loop.metric(
        fn y_true, y_pred -> Axon.Losses.mean_squared_error(y_true, y_pred, reduction: :mean) end,
        "mean_squared_error"
      )

  # Run evaluation (Axon may wrap metrics under numeric keys like 0 => %{...})
  raw_metrics = Axon.Loop.run(eval_loop, validation_data, params)
  metrics = normalize_metrics(raw_metrics)

    # Add custom metrics if specified
    custom_metrics = Map.get(training_config, :custom_metrics, [])

    custom_results =
      custom_metrics
      |> Enum.into(%{}, fn metric_name ->
        result = compute_custom_metric(metric_name, model, params, validation_data)
        {metric_name, result}
      end)

    Map.merge(metrics, custom_results)
  end

  defp compute_custom_metric(:top_5_accuracy, model, params, validation_data) do
    # Implement top-5 accuracy calculation
  _predictions = Axon.predict(model, params, validation_data)
    # Implementation would depend on specific needs
    0.0  # Placeholder
  end

  defp compute_custom_metric(:inference_time, model, params, validation_data) do
    # Measure average inference time
    batch = Enum.take(validation_data, 1) |> List.first()

    start_time = System.monotonic_time(:microsecond)
    _predictions = Axon.predict(model, params, batch)
    end_time = System.monotonic_time(:microsecond)

    (end_time - start_time) / 1000  # Convert to milliseconds
  end

  defp compute_custom_metric(_metric_name, _model, _params, _data) do
    # Default implementation for unknown metrics
    nil
  end

  defp count_parameters(params) do
    # params is %Axon.ModelState{}, extract tensors and count
    case params do
      %Axon.ModelState{data: data} ->
        data
        |> Map.values()
        |> Enum.flat_map(fn layer_params ->
          layer_params
          |> Map.values()
        end)
        |> Enum.map(&Nx.size/1)
        |> Enum.sum()
      _ -> 0
    end
  end

  defp spec_to_summary(spec) do
    %{
      num_levels: length(spec.levels),
      total_units: Enum.sum(Enum.map(spec.levels, &length(&1.units))),
      connectivity_patterns: %{
  minimum_skip_connection_depth: Map.get(spec.connectivity_config, :minimum_skip_connection_depth),
  maximum_skip_connection_depth: Map.get(spec.connectivity_config, :maximum_skip_connection_depth),
  lateral_connection_probability: Map.get(spec.connectivity_config, :lateral_connection_probability),
  max_consecutive_lateral_connections: Map.get(spec.connectivity_config, :max_consecutive_lateral_connections),
  gate_after_n_lateral_connections: Map.get(spec.connectivity_config, :gate_after_n_lateral_connections),
  gating_mode: Map.get(spec.connectivity_config, :gating_mode),
  gate_activation?: not is_nil(Map.get(spec.connectivity_config, :gate_activation))
      },
      unit_types: spec.levels |> Enum.map(& &1.unit_type) |> Enum.uniq()
    }
  end

  defp spec_hash(spec) do
    sanitized = %{
      seed: spec.seed,
      input_specs: spec.input_specs,
      output_shapes: spec.output_shapes,
      levels: Enum.map(spec.levels, fn level ->
        %{
          level_number: level.level_number,
          unit_type: level.unit_type,
          is_final: level.is_final,
          units: Enum.map(level.units, fn u ->
            Map.take(u, [:unit_id, :neurons, :activation, :dendrites, :dendrite_activation])
          end)
        }
      end),
      connectivity_config: spec.connectivity_config |> Map.drop([:predecessor_affinity_factor_decay, :lateral_connection_decay])
    }

    canonical = canonicalize(sanitized)
    binary = :erlang.term_to_binary(canonical)
    :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
  end

  # Normalize Axon metric structure: flatten possible index key and convert tensors to numbers
  defp normalize_metrics(%{0 => inner}) when is_map(inner), do: normalize_metrics(inner)
  defp normalize_metrics(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      cond do
        match?(%Nx.Tensor{}, v) -> {k, Nx.to_number(v)}
        is_map(v) -> {k, normalize_metrics(v)}
        true -> {k, v}
      end
    end)
    |> Enum.into(%{})
  end
  defp normalize_metrics(other), do: other

  # Produce a deterministic representation by turning maps into sorted lists
  defp canonicalize(term) when is_map(term) do
    term
    |> Enum.map(fn {k, v} -> {k, canonicalize(v)} end)
    |> Enum.sort_by(fn {k, _} -> k end)
  end
  defp canonicalize(list) when is_list(list), do: Enum.map(list, &canonicalize/1)
  defp canonicalize(other), do: other

  defp estimate_parameter_count(model, spec) do
    try do
      {init_fn, _predict_fn} = Axon.build(model)
      input_map =
        spec.input_specs
        |> Enum.with_index()
        |> Enum.into(%{}, fn {inp, idx} ->
          shape_list = inp.shape |> Tuple.to_list()
          shape_list = case shape_list do
            [nil | rest] -> [1 | rest]
            other -> other
          end
          tensor = Nx.broadcast(Nx.tensor(0.0, type: :f32), List.to_tuple(shape_list))
          {"input_#{idx}", tensor}
        end)
      params = init_fn.(input_map, Axon.ModelState.empty())
      count_parameters(params)
    rescue _ -> 0 end
  end

  # Heuristic epoch adaptation to avoid wall clock timeouts on pure interpreter backends.
  # If EXLA (or any JIT backend) is not loaded, large parameter counts can make epochs very slow.
  # We scale epochs down based on parameter buckets unless the user explicitly set :disable_epoch_adaptation.
  defp adapt_epochs(epochs, _est_params, _training_config) when epochs <= 1, do: epochs
  defp adapt_epochs(epochs, est_params, training_config) do
    disable? = Map.get(training_config, :disable_epoch_adaptation, false)
    timeout_ms = Map.get(training_config, :wall_clock_timeout_ms, :infinity)
    # Determine if we are actually using EXLA backend (not just loaded) to decide adaptation aggressiveness
    backend = Nx.default_backend()
    exla_active? = match?(EXLA.Backend, backend) or (is_tuple(backend) and elem(backend, 0) == EXLA.Backend)
    cond do
      disable? -> epochs
      exla_active? -> epochs
      timeout_ms == :infinity -> epochs
      est_params < 50_000 -> min(epochs, 8)
      est_params < 150_000 -> min(epochs, 6)
      est_params < 300_000 -> min(epochs, 4)
      est_params < 600_000 -> min(epochs, 3)
      true -> min(epochs, 2)
    end
  end
end
