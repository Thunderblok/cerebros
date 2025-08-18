defmodule Cerebros.Training.Orchestrator do
  @moduledoc """
  GenServer that orchestrates neural architecture search trials.

  This module manages the training of multiple architecture candidates,
  coordinating resource allocation, tracking performance, and collecting
  results for analysis.
  """

  use GenServer
  require Logger

  alias Cerebros.Architecture.Spec
  alias Cerebros.Networks.Builder
  alias Cerebros.Training.TrialWorker
  alias Cerebros.Results.Collector

  @type trial_id :: String.t()
  @type trial_status :: :pending | :running | :completed | :failed
  @type orchestrator_state :: %{
    trials: %{trial_id() => trial_info()},
    active_workers: %{trial_id() => pid()},
    max_concurrent: pos_integer(),
    search_config: map(),
    results: [map()]
  }
  @type trial_info :: %{
    id: trial_id(),
    spec: Spec.t(),
    status: trial_status(),
    started_at: DateTime.t() | nil,
    completed_at: DateTime.t() | nil,
    metrics: map() | nil,
    error: String.t() | nil
  }

  # Client API

  @doc """
  Starts the orchestrator with given configuration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    # Allow callers to pass a map for convenience
    opts = case opts do
      %{} = map -> Enum.into(map, [])
      kw when is_list(kw) -> kw
    end
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Submits a trial for training.
  """
  @spec submit_trial(GenServer.server(), Spec.t(), map()) :: {:ok, trial_id()} | {:error, String.t()}
  def submit_trial(orchestrator, spec, training_config \\ %{}) do
    GenServer.call(orchestrator, {:submit_trial, spec, training_config})
  end

  @doc """
  Gets the status of a specific trial.
  """
  @spec get_trial_status(GenServer.server(), trial_id()) :: {:ok, trial_info()} | {:error, :not_found}
  def get_trial_status(orchestrator, trial_id) do
    GenServer.call(orchestrator, {:get_trial_status, trial_id})
  end

  @doc """
  Lists all trials with their current status.
  """
  @spec list_trials(GenServer.server()) :: [trial_info()]
  def list_trials(orchestrator) do
    GenServer.call(orchestrator, :list_trials)
  end

  @doc """
  Gets all completed results.
  """
  @spec get_results(GenServer.server()) :: [map()]
  def get_results(orchestrator) do
    GenServer.call(orchestrator, :get_results)
  end

  @doc """
  Cancels a pending or running trial.
  """
  @spec cancel_trial(GenServer.server(), trial_id()) :: :ok | {:error, String.t()}
  def cancel_trial(orchestrator, trial_id) do
    GenServer.call(orchestrator, {:cancel_trial, trial_id})
  end

  @doc """
  Starts a random search with specified parameters.
  """
  @spec start_random_search(GenServer.server(), map()) :: :ok
  def start_random_search(orchestrator, search_params) do
    GenServer.cast(orchestrator, {:start_random_search, search_params})
  end

  # GenServer Implementation

  @impl GenServer
  def init(opts) do
    max_concurrent = Keyword.get(opts, :max_concurrent, 2)
    search_config = Keyword.get(opts, :search_config, %{})
    dataset = Keyword.get(opts, :dataset, nil)
    use_collector = Keyword.get(opts, :use_results_collector, true)
    collector_pid =
      if use_collector do
        case Cerebros.Results.Collector.start_link() do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
          _ -> nil
        end
      else
        nil
      end

    state = %{
      trials: %{},
      active_workers: %{},
      max_concurrent: max_concurrent,
      search_config: search_config,
      results: [],
  dataset: dataset,
  results_collector: collector_pid
    }

  Logger.info("Training orchestrator started with max_concurrent=#{max_concurrent}")

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:submit_trial, spec, training_config}, _from, state) do
    trial_id = generate_trial_id()

    trial_info = %{
      id: trial_id,
      spec: spec,
      status: :pending,
      started_at: nil,
      completed_at: nil,
      metrics: nil,
      error: nil,
      training_config: training_config
    }

    new_state = %{state | trials: Map.put(state.trials, trial_id, trial_info)}
    new_state = maybe_start_pending_trials(new_state)

    {:reply, {:ok, trial_id}, new_state}
  end

  @impl GenServer
  def handle_call({:get_trial_status, trial_id}, _from, state) do
    case Map.get(state.trials, trial_id) do
      nil -> {:reply, {:error, :not_found}, state}
      trial_info -> {:reply, {:ok, trial_info}, state}
    end
  end

  @impl GenServer
  def handle_call(:list_trials, _from, state) do
    trials = Map.values(state.trials)
    {:reply, trials, state}
  end

  @impl GenServer
  def handle_call(:get_results, _from, state) do
    {:reply, state.results, state}
  end

  @impl GenServer
  def handle_call({:cancel_trial, trial_id}, _from, state) do
    case Map.get(state.trials, trial_id) do
      nil ->
        {:reply, {:error, "Trial not found"}, state}

      %{status: :completed} ->
        {:reply, {:error, "Trial already completed"}, state}

      %{status: :failed} ->
        {:reply, {:error, "Trial already failed"}, state}

      trial_info ->
        # Cancel running worker if exists
        new_state =
          case Map.get(state.active_workers, trial_id) do
            nil -> state
            worker_pid ->
              Process.exit(worker_pid, :kill)
              %{state | active_workers: Map.delete(state.active_workers, trial_id)}
          end

        # Update trial status
        updated_trial = %{trial_info |
          status: :failed,
          error: "Cancelled by user",
          completed_at: DateTime.utc_now()
        }

        final_state = %{new_state |
          trials: Map.put(new_state.trials, trial_id, updated_trial)
        }

        # Try to start pending trials
        final_state = maybe_start_pending_trials(final_state)

        {:reply, :ok, final_state}
    end
  end

  @impl GenServer
  def handle_cast({:start_random_search, search_params}, state) do
    num_trials = Map.get(search_params, :num_trials, 10)

    # Generate random specs and submit trials
    specs =
      1..num_trials
      |> Enum.map(fn _ -> Spec.generate_random(search_params) end)

    new_state =
      specs
      |> Enum.reduce(state, fn spec, acc_state ->
        trial_id = generate_trial_id()

        trial_info = %{
          id: trial_id,
          spec: spec,
          status: :pending,
          started_at: nil,
          completed_at: nil,
          metrics: nil,
          error: nil,
          training_config: Map.get(search_params, :training_config, %{})
        }

        %{acc_state | trials: Map.put(acc_state.trials, trial_id, trial_info)}
      end)

    # Start pending trials
    final_state = maybe_start_pending_trials(new_state)

    Logger.info("Started random search with #{num_trials} trials")

    {:noreply, final_state}
  end

  @impl GenServer
  def handle_cast({:start_search, search_params}, state) do
    new_state = start_search_trials(state, search_params)
  total_trials = map_size(new_state.trials)
  Logger.info("Enqueued #{total_trials} trials (archs=#{Map.get(search_params, :number_of_architectures_to_try, "?")} x trials_per_arch=#{Map.get(search_params, :number_of_trials_per_architecture, "?")})")
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:trial_completed, trial_id, result}, state) do
    Logger.info("Trial #{trial_id} completed")

    # Update trial status
    trial_info = Map.get(state.trials, trial_id)
    updated_trial = %{trial_info |
      status: :completed,
      completed_at: DateTime.utc_now(),
      metrics: result
    }

    # Store result and remove from active workers
    new_state = %{state |
      trials: Map.put(state.trials, trial_id, updated_trial),
      active_workers: Map.delete(state.active_workers, trial_id),
      results: [Map.put(result, :trial_id, trial_id) | state.results]
    }

    # Forward to results collector if present
    if Map.get(state, :results_collector) do
      Cerebros.Results.Collector.store_result(state.results_collector, Map.put(result, :trial_id, trial_id))
    end

    # Try to start pending trials
    final_state = maybe_start_pending_trials(new_state)

    # Log progress
    completed_count = count_trials_by_status(final_state.trials, :completed)
    total_count = map_size(final_state.trials)
    Logger.info("Progress: #{completed_count}/#{total_count} trials completed")

    {:noreply, final_state}
  end

  @impl GenServer
  def handle_info({:trial_failed, trial_id, error}, state) do
  Logger.warning("Trial #{trial_id} failed: #{error}")

    # Update trial status
    trial_info = Map.get(state.trials, trial_id)
    updated_trial = %{trial_info |
      status: :failed,
      completed_at: DateTime.utc_now(),
      error: error
    }

    # Remove from active workers
    new_state = %{state |
      trials: Map.put(state.trials, trial_id, updated_trial),
      active_workers: Map.delete(state.active_workers, trial_id)
    }

  # (Optional) could emit a failure record to collector in future

    # Try to start pending trials
    final_state = maybe_start_pending_trials(new_state)

    {:noreply, final_state}
  end


  @impl GenServer
  def handle_info({:DOWN, _ref, :process, worker_pid, reason}, state) do
    # Find trial_id for the crashed worker
    trial_id =
      state.active_workers
      |> Enum.find_value(fn {id, pid} -> if pid == worker_pid, do: id end)

    case trial_id do
      nil ->
        # Worker not found, ignore
        {:noreply, state}

      id ->
        Logger.error("Worker for trial #{id} crashed: #{inspect(reason)}")

        # Update trial status
        trial_info = Map.get(state.trials, id)
        updated_trial = %{trial_info |
          status: :failed,
          completed_at: DateTime.utc_now(),
          error: "Worker crashed: #{inspect(reason)}"
        }

        # Remove from active workers
        new_state = %{state |
          trials: Map.put(state.trials, id, updated_trial),
          active_workers: Map.delete(state.active_workers, id)
        }

        # Try to start pending trials
        final_state = maybe_start_pending_trials(new_state)

        {:noreply, final_state}
    end
  end

  # Private functions

  defp generate_trial_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
  end

  defp maybe_start_pending_trials(state) do
    active_count = map_size(state.active_workers)
    available_slots = state.max_concurrent - active_count

    if available_slots > 0 do
      pending_trials =
        state.trials
        |> Enum.filter(fn {_id, trial} -> trial.status == :pending end)
        |> Enum.take(available_slots)

      Enum.reduce(pending_trials, state, fn {trial_id, trial_info}, acc_state ->
        start_trial_worker(trial_id, trial_info, acc_state)
      end)
    else
      state
    end
  end

  defp start_trial_worker(trial_id, trial_info, state) do
    # Start the worker process
    {:ok, worker_pid} = TrialWorker.start_link(
      trial_id: trial_id,
      spec: trial_info.spec,
      training_config: trial_info.training_config,
      orchestrator: self()
    )

    # Monitor the worker
    Process.monitor(worker_pid)

    # Update trial status
    updated_trial = %{trial_info |
      status: :running,
      started_at: DateTime.utc_now()
    }

    # Update state
    %{state |
      trials: Map.put(state.trials, trial_id, updated_trial),
      active_workers: Map.put(state.active_workers, trial_id, worker_pid)
    }
  end

  defp count_trials_by_status(trials, status) do
    trials
    |> Enum.count(fn {_id, trial} -> trial.status == status end)
  end

  # === Added helpers for full NAS test integration ===
  defp start_search_trials(state, search_params) do
    arch_count = Map.get(search_params, :number_of_architectures_to_try, 1)
    trials_per_arch = Map.get(search_params, :number_of_trials_per_architecture, 1)
    batch_size = Map.get(search_params, :batch_size, 32)
    epochs = Map.get(search_params, :epochs, 5)
    learning_rate = Map.get(search_params, :learning_rate, 0.001)

    [input_shape] = Map.get(search_params, :input_shapes, [{10}])
    input_dim = elem(input_shape, 0)
    [output_shape] = Map.get(search_params, :output_shapes, [{1}])
    output_dim = elem(output_shape, 0)

    # Connectivity hyperparameters (aligning with original Python Cerebros semantics, but conservative defaults still possible)
    min_skip = Map.get(search_params, :minimum_skip_connection_depth, 1)
    max_skip = Map.get(search_params, :maximum_skip_connection_depth, 7)
    pre_first = Map.get(search_params, :predecessor_affinity_factor_first, 5.0)
    pre_main = Map.get(search_params, :predecessor_affinity_factor_main, 0.7)
    pre_decay = Map.get(search_params, :predecessor_affinity_factor_decay, fn depth -> pre_main * :math.pow(0.9, depth) end)
    lateral_prob = Map.get(search_params, :lateral_connection_probability, 0.2)
    lateral_decay = Map.get(search_params, :lateral_connection_decay, fn depth -> lateral_prob * :math.pow(0.95, depth) end)
    max_lat = Map.get(search_params, :max_consecutive_lateral_connections, 7)
    gate_after = Map.get(search_params, :gate_after_n_lateral_connections, 3)
  gate_activation = Map.get(search_params, :gate_activation, :sigmoid)
  gating_mode = Map.get(search_params, :gating_mode, :activation)

    connectivity_config = %{
      minimum_skip_connection_depth: min_skip,
      maximum_skip_connection_depth: max_skip,
      predecessor_affinity_factor_first: pre_first,
      predecessor_affinity_factor_main: pre_main,
      predecessor_affinity_factor_decay: Cerebros.Functions.Decay.resolve_decay(pre_decay),
      lateral_connection_probability: lateral_prob,
      lateral_connection_decay: Cerebros.Functions.Decay.resolve_decay(lateral_decay),
      max_consecutive_lateral_connections: max_lat,
      gate_after_n_lateral_connections: gate_after,
      gate_activation: gate_activation,
      gating_mode: gating_mode
    }

    # Merge / width control configuration (optional)
    merge_strategy_pool = Map.get(search_params, :merge_strategy_pool, [:concatenate])
    max_merge_width = Map.get(search_params, :max_merge_width, nil) # nil means unlimited
    projection_after_merge = Map.get(search_params, :projection_after_merge, true)
    projection_activation = Map.get(search_params, :projection_activation, :relu)

    merge_config = %{
      strategy_pool: merge_strategy_pool,
      max_merge_width: max_merge_width,
      projection_after_merge: projection_after_merge,
      projection_activation: projection_activation
    }

    dataset_streams = build_dataset_streams(state.dataset, batch_size)

    Enum.reduce(1..arch_count, state, fn arch_idx, acc_state ->
      Enum.reduce(1..trials_per_arch, acc_state, fn trial_idx, inner_state ->
        seed = :erlang.phash2({arch_idx, trial_idx, System.unique_integer()})
        spec = Spec.random(connectivity_config,
          seed: seed,
          min_levels: Map.get(search_params, :minimum_levels, 1),
          max_levels: Map.get(search_params, :maximum_levels, 3),
          min_units_per_level: Map.get(search_params, :minimum_units_per_level, 1),
          max_units_per_level: Map.get(search_params, :maximum_units_per_level, 3),
          min_neurons_per_unit: Map.get(search_params, :minimum_neurons_per_unit, 4),
          max_neurons_per_unit: Map.get(search_params, :maximum_neurons_per_unit, 32),
          input_specs: [%{shape: {input_dim}, dtype: :f32}],
          output_shapes: [output_dim],
          merge_config: merge_config
        )
        if arch_count * trials_per_arch > 4 do
          Logger.debug("Enqueued trial #{arch_idx}.#{trial_idx} levels=#{length(spec.levels)} total_units=#{Enum.sum(Enum.map(spec.levels, &length(&1.units)))} max_neurons=#{Enum.max(Enum.flat_map(spec.levels, fn l -> Enum.map(l.units, & &1.neurons) end))}")
        end

        trial_id = generate_trial_id()
        training_config = %{
          batch_size: batch_size,
          epochs: epochs,
          learning_rate: learning_rate,
          loss: :mean_squared_error,
          optimizer: :adam,
          dataset: dataset_streams,
          metrics: [:mean_squared_error],
          early_stop_patience: Map.get(search_params, :early_stop_patience, 10),
          parameter_budget: Map.get(search_params, :parameter_budget, nil),
          wall_clock_timeout_ms: Map.get(search_params, :wall_clock_timeout_ms, :infinity),
          disable_epoch_adaptation: Map.get(search_params, :disable_epoch_adaptation, false),
          skip_param_estimation: Map.get(search_params, :skip_param_estimation, false),
          parameter_estimation_mode: Map.get(search_params, :parameter_estimation_mode, nil),
          max_batches_per_epoch: Map.get(search_params, :max_batches_per_epoch, nil)
        }

        trial_info = %{
          id: trial_id,
          spec: spec,
          status: :pending,
          started_at: nil,
          completed_at: nil,
          metrics: nil,
          error: nil,
          training_config: training_config
        }

        updated = %{inner_state | trials: Map.put(inner_state.trials, trial_id, trial_info)}
        maybe_start_pending_trials(updated)
      end)
    end)
  end

  defp build_dataset_streams(nil, _batch_size), do: :cifar10
  defp build_dataset_streams(%{train_x: tx, train_y: ty, validation_x: vx, validation_y: vy}, batch_size) do
  {tx, ty} = trim_to_full_batches(tx, ty, batch_size, :train)
  {vx, vy} = trim_to_full_batches(vx, vy, batch_size, :val)
  train_stream = build_stream(tx, ty, batch_size)
  val_stream = build_stream(vx, vy, batch_size)
  %{train: train_stream, validation: val_stream}
  end

  defp build_stream(x, y, batch_size) do
    {num_samples, feat_dim} = Nx.shape(x)
    {label_samples, _} = Nx.shape(y)
    if num_samples != label_samples, do: raise "Sample mismatch: #{num_samples} vs #{label_samples}"
    # Emit only full batches; dataset already trimmed to multiple of batch_size.
    Stream.unfold(0, fn idx ->
      if idx + batch_size > num_samples do
        nil
      else
        batch_x = Nx.slice(x, [idx, 0], [batch_size, feat_dim])
        batch_y = Nx.slice(y, [idx, 0], [batch_size, 1])
        {{batch_x, batch_y}, idx + batch_size}
      end
    end)
  end

  defp trim_to_full_batches(x, y, batch_size, tag) do
    {n, _} = Nx.shape(x)
    full = div(n, batch_size) * batch_size
    if full == n do
      {x, y}
    else
      # Trim tail to avoid partial batch shape mismatch with compiled function
      trimmed_x = Nx.slice(x, [0, 0], [full, elem(Nx.shape(x), 1)])
      trimmed_y = Nx.slice(y, [0, 0], [full, elem(Nx.shape(y), 1)])
      Logger.info("Trimmed #{tag} samples from #{n} -> #{full} to enforce full batches (batch_size=#{batch_size})")
      {trimmed_x, trimmed_y}
    end
  end
end
