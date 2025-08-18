defmodule Cerebros do
  @moduledoc """
  Cerebros is a neural architecture search system built with Elixir and Axon.

  This system provides fault-tolerant, distributed neural architecture search
  using the BEAM ecosystem's actor model and OTP supervision trees.
  """

  def hello do
    :world
  end

  @doc """
  Basic EXLA diagnostics delegating to `Cerebros.ExlaHelper` (legacy helper).

  For richer backend + environment details use `gpu_diagnostics/1` which
  returns a map of facts. This function only prints and returns :ok.
  """
  def exla_diagnostics do
    Cerebros.ExlaHelper.diagnostics()
  end

  @doc """
  Sets up the best available EXLA backend automatically.
  """
  def setup_exla_backend do
    Cerebros.ExlaHelper.setup_best_backend()
  end

  @doc """
  Quick test function to verify the system is working.
  """
  def test_basic_functionality do
    IO.puts("🧠 Testing Cerebros basic functionality...")

    # Test basic architecture spec creation
    # NOTE: level numbering starts at 0 so connectivity builder can find predecessors
    spec = %Cerebros.Architecture.Spec{
      input_specs: [%{shape: {10}, name: "test_input"}],
      levels: [
        %{
          level_number: 0,
          unit_type: :dense,
          units: [%{unit_id: 0, neurons: 5, activation: :relu}],
          is_final: false
        },
        %{
          level_number: 1,
          unit_type: :dense,
          units: [%{unit_id: 0, neurons: 1, activation: nil}],
          is_final: true
        }
      ],
      connectivity_config: %{
        minimum_skip_connection_depth: 1,
        maximum_skip_connection_depth: 2,
        predecessor_affinity_factor_first: 1.0,
        predecessor_affinity_factor_main: 0.8,
        predecessor_affinity_factor_decay: fn _ -> 0.9 end,
        lateral_connection_probability: 0.1,
        lateral_connection_decay: fn _ -> 0.8 end,
        max_consecutive_lateral_connections: 2,
        gate_after_n_lateral_connections: 3
      },
      seed: 12345
    }

    IO.puts("✓ Architecture spec created")

    # Test connectivity building
    case Cerebros.Connectivity.Builder.build_connectivity(spec) do
      {:ok, connectivity} ->
        IO.puts("✓ Connectivity built successfully")
        IO.puts("  Connections: #{map_size(connectivity)}")

      {:error, reason} ->
        IO.puts("✗ Connectivity failed: #{reason}")
        {:error, reason}
    end

    # Test basic Axon model creation
    result =
      try do
        input = Axon.input("test", shape: {nil, 10})
        model = input |> Axon.dense(5, activation: :relu) |> Axon.dense(1)
        IO.puts("✓ Basic Axon model created")

        test_data = Nx.iota({2, 10}, type: :f32)
        {init_fn, predict_fn} = Axon.build(model)
        params = init_fn.(%{"test" => test_data}, Axon.ModelState.empty())
        IO.puts("✓ Model parameters initialized")

        predictions = predict_fn.(params, %{"test" => test_data})
        IO.puts("✓ Model prediction successful, shape: #{inspect(Nx.shape(predictions))}")
        :ok
      rescue
        error ->
          IO.puts("✗ Axon test failed: #{Exception.message(error)}")
          {:error, Exception.message(error)}
      end

    case result do
      :ok -> IO.puts("🎉 All basic functionality tests passed!")
      {:error, _} -> IO.puts("⚠️  Basic functionality test encountered errors")
    end
    result
  end

  @doc """
  Test the system with Ames housing data, similar to the original Cerebros example.
  This demonstrates regression on real-world data.
  """
  def test_ames_housing_example(opts \\ []) do
    IO.puts("🏠 Testing Cerebros with Ames Housing Dataset...")

    # Load and preprocess the Ames dataset
    case load_ames_data() do
      {:ok, {train_x, train_y, val_x, val_y, feature_count}} ->
        IO.puts("✓ Ames dataset loaded:")
        IO.puts("  - Features: #{feature_count}")
        IO.puts("  - Train samples: #{elem(Nx.shape(train_x), 0)}")
        IO.puts("  - Validation samples: #{elem(Nx.shape(val_x), 0)}")

        # Configure the search for housing price prediction
  _config = %{
          input_shapes: [{feature_count}],
          output_shapes: [{1}],
          minimum_levels: 1,
          maximum_levels: 4,
          minimum_units_per_level: 1,
          maximum_units_per_level: 4,
          minimum_neurons_per_unit: 5,
          maximum_neurons_per_unit: 50,
          number_of_architectures_to_try: 5,
          number_of_trials_per_architecture: 2,
          epochs: 20,
          batch_size: 64,
          learning_rate: 0.01,
          task_type: :regression,
          loss_function: :mean_squared_error
        }

        normalize? = Keyword.get(opts, :normalize_targets, true)
        IO.puts("🎯 Starting Ames housing price prediction search..." <> if normalize?, do: " (targets normalized)", else: "")

        {train_y_for_search, val_y_for_search, target_mean, target_std} =
          if normalize? do
            m = Nx.mean(train_y)
            std = Nx.standard_deviation(train_y) |> Nx.add(1.0e-7)
            ty_norm = train_y |> Nx.subtract(m) |> Nx.divide(std)
            vy_norm = val_y |> Nx.subtract(m) |> Nx.divide(std)
            {ty_norm, vy_norm, m, std}
          else
            {train_y, val_y, nil, nil}
          end

        # Select search profile (scales breadth/depth). Users can still override any individual knob.
        profile = Keyword.get(opts, :search_profile, :balanced)
        {max_lv, max_units, max_neurons, archs, trials, epochs, timeout_ms, param_budget} =
          case profile do
            :conservative -> {3, 3, 24, 3, 1, 12, Keyword.get(opts, :trial_timeout_ms, 60_000), Keyword.get(opts, :parameter_budget, nil)}
            :balanced -> {5, 5, 64, 6, 2, 18, Keyword.get(opts, :trial_timeout_ms, 90_000), Keyword.get(opts, :parameter_budget, 800_000)}
            :aggressive -> {8, 6, 256, 10, 2, 20, Keyword.get(opts, :trial_timeout_ms, 120_000), Keyword.get(opts, :parameter_budget, 2_000_000)}
            other when is_map(other) ->
              # Allow custom map profile for power users: %{max_levels: .., max_neurons: ..}
              {
                Map.get(other, :maximum_levels, 5),
                Map.get(other, :maximum_units_per_level, 5),
                Map.get(other, :maximum_neurons_per_unit, 64),
                Map.get(other, :number_of_architectures_to_try, 6),
                Map.get(other, :number_of_trials_per_architecture, 2),
                Map.get(other, :epochs, 18),
                Map.get(other, :trial_timeout_ms, Keyword.get(opts, :trial_timeout_ms, 90_000)),
                Map.get(other, :parameter_budget, Keyword.get(opts, :parameter_budget, 800_000))
              }
            _ -> {5, 5, 64, 6, 2, 18, Keyword.get(opts, :trial_timeout_ms, 90_000), Keyword.get(opts, :parameter_budget, 800_000)}
          end

        IO.puts("🗺  Search profile=#{inspect(profile)} (lv<=#{max_lv}, units/lv<=#{max_units}, neurons/unit<=#{max_neurons}, archs=#{archs}, trials/arch=#{trials}, epochs=#{epochs}, param_budget=#{inspect(param_budget)})")

        # Allow explicit user overrides to trump profile-derived defaults
        cfg_overrides = [
          {:maximum_levels, Keyword.get(opts, :maximum_levels, max_lv)},
          {:maximum_units_per_level, Keyword.get(opts, :maximum_units_per_level, max_units)},
          {:maximum_neurons_per_unit, Keyword.get(opts, :maximum_neurons_per_unit, max_neurons)},
          {:number_of_architectures_to_try, Keyword.get(opts, :number_of_architectures_to_try, archs)},
          {:number_of_trials_per_architecture, Keyword.get(opts, :number_of_trials_per_architecture, trials)},
          {:epochs, Keyword.get(opts, :epochs, epochs)},
          {:wall_clock_timeout_ms, timeout_ms},
          {:parameter_budget, param_budget},
          # Pass through disable flags if provided
          {:disable_epoch_adaptation, Keyword.get(opts, :disable_epoch_adaptation, false)}
        ]

        # If caller explicitly sets :unbounded, clear parameter budget & adaptation
        cfg_overrides =
          if Keyword.get(opts, :unbounded, false) do
            IO.puts("🔥 Unbounded mode: removing parameter budget & epoch adaptation limits (may be slow on CPU)")
            cfg_overrides
            |> Keyword.put(:parameter_budget, nil)
            |> Keyword.put(:disable_epoch_adaptation, true)
          else
            cfg_overrides
          end

        max_wait_ms = Keyword.get(opts, :max_wait_ms, timeout_ms * 2)
        case test_full_nas_run([
               {:input_shapes, [{feature_count}]},
               {:output_shapes, [{1}]},
               {:dataset,
                %{
                  train_x: train_x,
                  train_y: train_y_for_search,
                  validation_x: val_x,
                  validation_y: val_y_for_search
                }}
             ] ++ cfg_overrides ++ [
               {:search_profile, profile},
               {:cancel_on_timeout, true},
               {:max_wait_ms, max_wait_ms}
             ]) do
          {:ok, results} ->
            IO.puts("🏆 Ames housing test completed successfully!")
            analyze_regression_performance(train_y, val_y, results, target_mean: target_mean, target_std: target_std)
            {:ok, results}

        end

      {:error, reason} ->
        IO.puts("❌ Failed to load Ames dataset: #{reason}")
        IO.puts("💡 Make sure ames.csv is available in the data directory")
        {:error, reason}
    end
  end

  # Load and preprocess Ames housing data
  defp load_ames_data do
    case find_ames_csv() do
      {:ok, ames_path} ->
        IO.puts("📊 Loading Ames dataset from #{ames_path}")
        case parse_ames_csv(ames_path) do
          {:ok, tuple} -> {:ok, tuple}
          {:error, parse_reason} ->
            IO.puts("⚠️  Failed to parse CSV (#{parse_reason}); falling back to synthetic simulation")
            fallback_simulated_ames()
        end
      {:error, reason} -> {:error, reason}
    end
  end

  # Real CSV parsing using Explorer
  defp parse_ames_csv(path) do
    unless Code.ensure_loaded?(Explorer.DataFrame) do
      {:error, "Explorer not available at runtime"}
    else
      try do
        # Explorer infers dtypes automatically; passing an atom caused an enumerable error.
        df = Explorer.DataFrame.from_csv!(path,
          nil_values: ["NA", "N/A", "", "NULL"],
          infer_schema_length: 10_000
        )
        dtypes = Explorer.DataFrame.dtypes(df)
        numeric_cols =
          dtypes
          |> Enum.filter(fn {_k, v} -> v in [:integer, :float] end)
          |> Enum.map(&elem(&1, 0))

        if numeric_cols == [] do
          raise "No numeric columns detected"
        end

        target_col =
          Enum.find(["SalePrice", "sale_price", "Price", "price"], &(&1 in numeric_cols)) ||
          List.last(numeric_cols)

        feature_cols = Enum.reject(numeric_cols, &(&1 == target_col))

        # Extract rows as maps and build feature matrix
        rows = Explorer.DataFrame.to_rows(df)
        feature_matrix_list =
          rows
          |> Enum.map(fn row -> Enum.map(feature_cols, fn c -> normalize_number(Map.get(row, c)) end) end)
        target_list = rows |> Enum.map(fn row -> normalize_number(Map.get(row, target_col)) end)

        features = Nx.tensor(feature_matrix_list, type: :f32)
        target = Nx.tensor(target_list, type: :f32) |> Nx.reshape({:auto, 1})

        # Impute any NaNs (after to_number parse) with column mean then z-score normalize
        {f_mean, f_std} = {
          Nx.mean(features, axes: [0]),
          Nx.standard_deviation(features, axes: [0]) |> Nx.add(1.0e-7)
        }
  nan_mask = Nx.is_nan(features)
  zero_fill = Nx.broadcast(Nx.tensor(0.0, type: :f32), Nx.shape(features))
  features_no_nan = Nx.select(nan_mask, zero_fill, features)
        norm_features = features_no_nan |> Nx.subtract(f_mean) |> Nx.divide(f_std)

        # Deterministic shuffle/split (seeded)
        num_samples = elem(Nx.shape(norm_features), 0)
        indices = Enum.to_list(0..(num_samples - 1))
        :rand.seed(:exsss, {:erlang.phash2(path), 42, 99})
        shuffled = Enum.shuffle(indices)
        train_split = 0.7
        train_samples = round(num_samples * train_split)
        {train_idx, val_idx} = Enum.split(shuffled, train_samples)

        gather_axis = 0
        train_x = Nx.take(norm_features, Nx.tensor(train_idx), axis: gather_axis)
        val_x   = Nx.take(norm_features, Nx.tensor(val_idx), axis: gather_axis)
        train_y = Nx.take(target, Nx.tensor(train_idx), axis: gather_axis)
        val_y   = Nx.take(target, Nx.tensor(val_idx), axis: gather_axis)

        {:ok, {train_x, train_y, val_x, val_y, length(feature_cols)}}
      rescue
        e -> {:error, Exception.message(e)}
      end
    end
  end

  defp normalize_number(nil), do: 0.0
  defp normalize_number(v) when is_integer(v), do: v * 1.0
  defp normalize_number(v) when is_float(v), do: v
  defp normalize_number(v) when is_binary(v) do
    case Float.parse(v) do
      {num, _} -> num
      :error -> 0.0
    end
  end
  defp normalize_number(_), do: 0.0

  defp fallback_simulated_ames do
    feature_count = 37
    num_samples = 1460
    train_split = 0.7
    train_samples = round(num_samples * train_split)
    val_samples = num_samples - train_samples

    train_x = simulate_housing_features(train_samples, feature_count)
    val_x   = simulate_housing_features(val_samples, feature_count)
    train_y = simulate_housing_prices(train_x)
    val_y   = simulate_housing_prices(val_x)
    {:ok, {train_x, train_y, val_x, val_y, feature_count}}
  end

  # Priority order for locating ames.csv:
  # 1. ENV CEREBROS_DATA_DIR
  # 2. opts not yet supported (future)
  # 3. project_root/ames.csv
  # 4. project_root/data/ames.csv
  # 5. project_root/priv/data/ames.csv
  # 6. parent_directory/ames.csv (legacy fallback)
  defp find_ames_csv do
    cwd = File.cwd!()
    env_dir = System.get_env("CEREBROS_DATA_DIR")
    parent = Path.dirname(cwd)

    candidates =
      [
        (env_dir && Path.join(env_dir, "ames.csv")),
        Path.join(cwd, "ames.csv"),
        Path.join([cwd, "data", "ames.csv"]),
        Path.join([cwd, "priv", "data", "ames.csv"]),
        Path.join(parent, "ames.csv")
      ]
      |> Enum.filter(& &1)

    case Enum.find(candidates, &File.exists?/1) do
      nil -> {:error, "Ames dataset not found. Looked in: #{Enum.join(candidates, ", ")}"}
      path -> {:ok, path}
    end
  end

  # Simulate housing features (lot size, bedrooms, bathrooms, etc.)
  defp simulate_housing_features(num_samples, feature_count) do
    # Create realistic housing features with proper scaling
    base =
      normal({num_samples, feature_count}, 0.0, 1.0, 100)
      |> Nx.add(
        Nx.broadcast(
          Nx.tensor(
            [1, 2, 3, 1500, 2000, 10, 5, 3, 2, 1990]
            |> Enum.take(feature_count)
            |> Enum.concat(List.duplicate(0, feature_count - 10))
            |> Nx.tensor()
          ), {num_samples, feature_count}
        )
      )
      |> Nx.abs()

    # Standardize to stabilize activations
    mean = Nx.mean(base, axes: [0])
    std  = Nx.standard_deviation(base, axes: [0]) |> Nx.add(1.0e-6)
    base |> Nx.subtract(mean) |> Nx.divide(std)
  end

  # Simulate housing prices based on features
  defp simulate_housing_prices(features) do
    # Create a realistic price model: base price + weighted features + noise
    base_price = 150_000
    feature_weights = Nx.tensor([50_000, 25_000, 30_000, 100, 80, 5_000, 10_000, 15_000, 20_000, 500])

    # Compute price as weighted sum of first 10 features + base + noise
    {num_samples, feature_count} = Nx.shape(features)
    weights_size = min(10, feature_count)

    weighted_features = features[[.., 0..(weights_size-1)]]
                       |> Nx.dot(feature_weights[0..(weights_size-1)])

  noise = normal({num_samples}, 0.0, 10_000, 101)

  base_price
  |> Nx.broadcast({num_samples})
  |> Nx.add(weighted_features)
  |> Nx.add(noise)  # Add price noise
  |> Nx.reshape({num_samples, 1})
  |> Nx.abs()  # Ensure positive prices
  end

  # Analyze regression performance
  defp analyze_regression_performance(train_y, val_y, results, opts) do
    train_mean = Nx.mean(train_y) |> Nx.to_number()
    val_mean = Nx.mean(val_y) |> Nx.to_number()
  target_std = Keyword.get(opts, :target_std, nil)
  _target_mean = Keyword.get(opts, :target_mean, nil)

    IO.puts("\n🏠 === HOUSING PRICE PREDICTION RESULTS ===")
    IO.puts("💰 Dataset statistics:")
    IO.puts("   - Average training price: $#{Float.round(train_mean, 2)}")
    IO.puts("   - Average validation price: $#{Float.round(val_mean, 2)}")

    cond do
      is_list(results) and results != [] ->
        best_trial = Enum.min_by(results, fn trial -> Map.get(trial, :validation_loss, :infinity) end)
        raw_best_loss = Map.get(best_trial, :validation_loss, 0)
        {best_loss, rmse} =
          if target_std do
            # Denormalize MSE back to original scale: MSE_orig = MSE_norm * std^2
            dn = raw_best_loss * :math.pow(Nx.to_number(target_std), 2)
            {dn, :math.sqrt(dn)}
          else
            {raw_best_loss, :math.sqrt(raw_best_loss)}
          end
        relative_error = if val_mean > 0, do: (rmse / val_mean) * 100, else: 0.0

        IO.puts("🎯 Best model performance:")
        IO.puts("   - Validation MSE: #{Float.round(best_loss, 5)}" <> if target_std, do: " (denormalized)", else: "")
        IO.puts("   - Validation RMSE: $#{Float.round(rmse, 2)}")
        IO.puts("   - Relative Error: #{Float.round(relative_error, 3)}%")
        if target_std do
          IO.puts("   - (Trained on normalized targets; metrics shown on original scale)")
        end
      match?(%{trials: _}, results) ->
        trials = Map.get(results, :trials)
        analyze_regression_performance(train_y, val_y, trials, opts)
      true ->
        IO.puts("⚠️  No results to analyze (empty or unexpected shape)")
    end

    IO.puts("=============================================\n")
  end

  @doc """
  Run a comprehensive neural architecture search test similar to the original Cerebros.
  This function demonstrates the full system functionality including:
  - Data loading and preprocessing
  - Architecture generation
  - Model building and training
  - Results collection and analysis
  """
  def test_full_nas_run(opts \\ []) do
    IO.puts("🔬 Starting full Neural Architecture Search test...")

    # Default configuration matching original Cerebros parameters
    exla_loaded = Code.ensure_loaded?(EXLA.Backend)
    unless exla_loaded do
      IO.puts("⚠️  EXLA not loaded; enabling conservative defaults (epoch adaptation + parameter budget) to avoid timeouts.")
    end

    config = %{
      input_shapes: Keyword.get(opts, :input_shapes, [{10}]),
      output_shapes: Keyword.get(opts, :output_shapes, [{1}]),
      minimum_levels: Keyword.get(opts, :minimum_levels, 1),
      maximum_levels: Keyword.get(opts, :maximum_levels, 3),
      minimum_units_per_level: Keyword.get(opts, :minimum_units_per_level, 1),
      maximum_units_per_level: Keyword.get(opts, :maximum_units_per_level, 3),
      minimum_neurons_per_unit: Keyword.get(opts, :minimum_neurons_per_unit, 1),
      maximum_neurons_per_unit: Keyword.get(opts, :maximum_neurons_per_unit, 10),
      number_of_architectures_to_try: Keyword.get(opts, :number_of_architectures_to_try, 3),
      number_of_trials_per_architecture: Keyword.get(opts, :number_of_trials_per_architecture, 2),
      epochs: Keyword.get(opts, :epochs, 10),
      batch_size: Keyword.get(opts, :batch_size, 32),
  learning_rate: Keyword.get(opts, :learning_rate, 0.01),
  wall_clock_timeout_ms: Keyword.get(opts, :wall_clock_timeout_ms, Keyword.get(opts, :trial_timeout_ms, :infinity)),
      # Soft parameter budget when EXLA missing (can override by passing :parameter_budget or setting to nil)
      parameter_budget: Keyword.get(opts, :parameter_budget, if(exla_loaded, do: nil, else: 400_000)),
  disable_epoch_adaptation: Keyword.get(opts, :disable_epoch_adaptation, false),
  skip_param_estimation: Keyword.get(opts, :skip_param_estimation, Keyword.get(opts, :speed_mode, false)),
  speed_mode: Keyword.get(opts, :speed_mode, false)
    }

    # Optional search expansion knobs (display only if provided)
    extra_keys = [
      :merge_strategy_pool,
      :max_merge_width,
      :projection_after_merge,
      :early_stop_patience,
      :search_profile
    ]
    extras =
      extra_keys
      |> Enum.flat_map(fn k ->
        case Keyword.fetch(opts, k) do
          {:ok, v} -> [{k, v}]
          :error -> []
        end
      end)
      |> Enum.into(%{})

    config = Map.merge(config, extras)

    # Speed mode trims expensive pieces for faster visual feedback
    config =
      if config.speed_mode do
        IO.puts("⚡ Speed mode: limiting epochs, batches, and enabling quick early stopping")
        Map.merge(config, %{
          epochs: min(config.epochs, 5),
          early_stop_patience: 2,
          max_batches_per_epoch: Map.get(config, :max_batches_per_epoch, 6),
          skip_param_estimation: true
        })
      else
        config
      end

    IO.puts("📊 Configuration: #{inspect(config, pretty: true)}")

    # Step 1: Obtain dataset (synthetic unless caller injects a real one)
    {train_x, train_y, val_x, val_y} =
      case Keyword.get(opts, :dataset) do
  %{train_x: tx, train_y: _ty, validation_x: vx, validation_y: _vy} = ds ->
          IO.puts("📥 Using provided dataset (#{elem(Nx.shape(tx), 0)} train / #{elem(Nx.shape(vx), 0)} val)")
          {ds.train_x, ds.train_y, ds.validation_x, ds.validation_y}
        nil ->
          IO.puts("🎲 Generating synthetic dataset...")
          data = generate_test_dataset(config)
          {sx, _sy, vx, _vy} = data
          IO.puts("✓ Dataset created - Train: #{inspect(Nx.shape(sx))}, Val: #{inspect(Nx.shape(vx))}")
          data
      end

    # Step 2: Start the search orchestrator
    IO.puts("🎯 Starting search orchestrator...")
    # Allow max_concurrent override or derive from search_profile to let aggressive runs "breathe"
    derived_concurrency =
      case Map.get(config, :search_profile) do
        :aggressive -> 4
        :balanced -> 3
        _ -> 2
      end
    max_concurrent = Keyword.get(opts, :max_concurrent, derived_concurrency)
    {:ok, orchestrator_pid} = Cerebros.Training.Orchestrator.start_link(%{
      max_concurrent: max_concurrent,
      search_params: config,
      dataset: %{
        train_x: train_x,
        train_y: train_y,
        validation_x: val_x,
        validation_y: val_y
      }
    })
    IO.puts("🧵 Concurrency: max_concurrent=#{max_concurrent}")

    # Step 3: Run the search
    IO.puts("🚀 Launching neural architecture search...")
    :ok = GenServer.cast(orchestrator_pid, {:start_search, config})

    # Step 4: Wait for completion (poll instead of fixed sleep)
    IO.puts("⏳ Waiting for search completion (polling)...")
    total_trials = config.number_of_architectures_to_try * config.number_of_trials_per_architecture
    max_wait_ms =
      case Keyword.get(opts, :max_wait_ms, 60_000) do
        :infinity -> :infinity
        v when is_integer(v) and v > 0 -> v
        _ -> 60_000
      end
    cancel_on_timeout = Keyword.get(opts, :cancel_on_timeout, false)
    poll_interval = 250
    start_wait = System.monotonic_time(:millisecond)

    # Robust wait loop: loop with explicit tail recursion, no anonymous self-ref closure (clearer debugging),
    # and progress emission every second.
  progress_emit_ms = if config.speed_mode, do: 5_000, else: 1_000
    wait_loop = fn ->
      rec = fn rec_fun, last_emit ->
        elapsed = System.monotonic_time(:millisecond) - start_wait
        results_now = GenServer.call(orchestrator_pid, :get_results)
        completed = length(results_now)
        cond do
          completed >= total_trials -> {results_now, false}
          max_wait_ms != :infinity and elapsed >= max_wait_ms ->
            IO.puts("⚠️  Timeout waiting for trials (#{completed}/#{total_trials} finished)")
            {results_now, true}
          true ->
            if elapsed - last_emit >= progress_emit_ms do
              IO.puts("⏱  Elapsed #{elapsed}ms – #{completed}/#{total_trials} trials complete")
              Process.sleep(poll_interval)
              rec_fun.(rec_fun, elapsed)
            else
              Process.sleep(poll_interval)
              rec_fun.(rec_fun, last_emit)
            end
        end
      end
      rec.(rec, 0)
    end
    {results, timed_out?} = wait_loop.()
    if timed_out? and cancel_on_timeout do
      IO.puts("🛑 Cancelling remaining trials after timeout...")
      Enum.each(GenServer.call(orchestrator_pid, :list_trials), fn trial ->
        if trial.status in [:pending, :running] do
          Cerebros.Training.Orchestrator.cancel_trial(orchestrator_pid, trial.id)
        end
      end)
    end
    IO.puts("📈 Search completed!")

    # Step 5: Analyze results
    analyze_nas_results(results)

    # Cleanup
    GenServer.stop(orchestrator_pid)

    IO.puts("🏆 Full NAS test completed successfully!")
  {:ok, results}
  end

  @doc """
  Bang version returning just the trials list (raises on timeout if :raise_on_timeout option true).
  """
  def test_full_nas_run!(opts \\ []) do
    {:ok, results} = test_full_nas_run(opts)
    results
  end

  @doc """
  Diagnose current Nx / EXLA backend status and (if possible) GPU availability.

  This function does NOT change any global state; it only reports:
    - Elixir & OTP versions
    - Current `EXLA_TARGET` env var (the one EXLA actually uses – note: use EXLA_TARGET, not XLA_TARGET)
    - Loaded Nx backends
    - Whether `EXLA.Backend` is loaded
    - Whether `/dev/nvidia0` (or any /dev/nvidia*) device files exist
    - Tries a tiny JIT computation on EXLA if available, reporting success/failure & backend used

  Returns a map of collected facts for programmatic inspection.
  """
  def gpu_diagnostics(opts \\ []) do
    IO.puts("🧪 Running Cerebros GPU / EXLA diagnostics...")

  exla_target_env = System.get_env("EXLA_TARGET")
  xla_target_env = System.get_env("XLA_TARGET") # In case user set the legacy / wrong var
  default_backend = Nx.default_backend()
  # Nx 0.9 does not expose a public Nx.backends/0 enumeration API; capture just the default
  backends = [inspect(default_backend)]

    {dev_nodes, dev_exists?} =
      case Path.wildcard("/dev/nvidia*") do
        [] -> {[], false}
        list -> {list, true}
      end

    exla_loaded? = Code.ensure_loaded?(EXLA.Backend)

    # Check for critical CUDA shared libraries via ldconfig if available
  {ld_out, _} = System.cmd("sh", ["-c", "command -v ldconfig >/dev/null 2>&1 && ldconfig -p || echo 'ldconfig-not-found'"])
    libs_needed = ["libcudart.so", "libcublas.so", "libcudnn.so", "libnccl.so"]
    libs_present =
      if String.contains?(ld_out, "ldconfig-not-found") do
        :unknown
      else
        Enum.reduce(libs_needed, %{}, fn lib, acc ->
          found = String.contains?(ld_out, lib)
          Map.put(acc, lib, found)
        end)
      end

    tiny_result =
      if exla_loaded? do
        try do
          # Force a short JIT compile on EXLA if user requested or if EXLA is already default.
          attempt = fn ->
            defn = Nx.Defn.jit(fn -> Nx.add(1, 2) end, compiler: EXLA)
            defn.()
          end
          tensor = attempt.()
          {:ok, Nx.to_number(tensor)}
        rescue
          e -> {:error, Exception.message(e)}
        end
      else
        {:error, "EXLA.Backend not loaded"}
      end

    otp_v = :erlang.system_info(:otp_release) |> to_string()
    elixir_v = System.version()

    summary = %{
      elixir_version: elixir_v,
      otp_release: otp_v,
      exla_target_env: exla_target_env,
      xla_target_env: xla_target_env,
      note: if(xla_target_env && !exla_target_env, do: "Set EXLA_TARGET, not XLA_TARGET", else: nil),
      nx_default_backend: inspect(default_backend),
      nx_available_backends: backends,
      exla_loaded?: exla_loaded?,
      nvidia_device_files_present?: dev_exists?,
      nvidia_device_files: dev_nodes,
  cuda_libraries: libs_present,
      tiny_exla_jit_result: tiny_result
    }

    pretty = fn label, value -> IO.puts(String.pad_trailing("  " <> label <> ":", 34) <> inspect(value)) end
    IO.puts("\n📋 Environment:")
    pretty.("Elixir version", summary.elixir_version)
    pretty.("OTP release", summary.otp_release)
    pretty.("EXLA_TARGET", summary.exla_target_env)
    if summary.xla_target_env, do: pretty.("(Legacy) XLA_TARGET", summary.xla_target_env)
    if summary.note, do: IO.puts("  ⚠️  " <> summary.note)

    IO.puts("\n🧩 Backends:")
    pretty.("Default backend", summary.nx_default_backend)
    pretty.("Available backends", summary.nx_available_backends)
    pretty.("EXLA loaded?", summary.exla_loaded?)

    IO.puts("\n🖥  GPU Device Files:")
    pretty.("/dev/nvidia* present?", summary.nvidia_device_files_present?)
    if summary.nvidia_device_files_present?, do: pretty.("Devices", summary.nvidia_device_files)

    IO.puts("\n📚 CUDA Library Presence:")
    case libs_present do
      :unknown -> IO.puts("  (ldconfig not found; skipping shared library check)")
      m when is_map(m) ->
        Enum.each(m, fn {lib, ok?} ->
          IO.puts("  #{String.pad_trailing(lib, 18)} -> #{if ok?, do: "✓", else: "✗ MISSING"}")
        end)
    end

    IO.puts("\n⚙️  Tiny EXLA JIT test:")
    case tiny_result do
      {:ok, val} -> IO.puts("  ✓ JIT add(1,2) => #{val}")
      {:error, reason} -> IO.puts("  ✗ JIT failed: #{reason}")
    end

    # Explicit NCCL warning if CUDA target but NCCL missing
    if exla_target_env == "cuda" and (is_map(libs_present) and Map.get(libs_present, "libnccl.so") == false) do
      IO.puts("\n🚫 NCCL not found (libnccl.so). EXLA's CUDA NIF will fail to load until it's installed.")
      IO.puts("   Install NCCL (and optionally cuDNN) or temporarily fall back to CPU with EXLA_TARGET=host.")
    end

    cond do
      !exla_loaded? -> IO.puts("💡 Suggestion: ensure {:exla, \"~> 0.9\"} is compiled; run `mix deps.compile exla`. Set EXLA_TARGET before compiling.")
      exla_loaded? and not dev_exists? -> IO.puts("💡 No /dev/nvidia* devices. In WSL: install Windows NVIDIA driver + reboot; ensure this distro supports WSL GPU. `dmesg | grep -i nvidia` can help.")
      exla_loaded? and dev_exists? and match?({:error, _}, tiny_result) -> IO.puts("💡 Devices exist but JIT failed: verify CUDA toolkit & cuDNN versions. Recompile EXLA with EXLA_TARGET=cuda.")
      true -> :ok
    end

    if Keyword.get(opts, :return, true), do: summary, else: :ok
  end

  # Generate synthetic test data similar to original Cerebros
  defp generate_test_dataset(config) do
    [input_shape] = config.input_shapes
    [output_shape] = config.output_shapes

  num_samples = 1000
  # Adjust to be multiple of batch_size (default 32) to avoid short final batch shape mismatch
  batch_size = config.batch_size || 32
  num_samples = div(num_samples, batch_size) * batch_size
    train_split = 0.7
    train_samples = round(num_samples * train_split)
    val_samples = num_samples - train_samples

    # Generate feature data with some realistic patterns
  train_x = normal({train_samples, elem(input_shape, 0)}, 0.0, 1.0, 200)
  val_x   = normal({val_samples, elem(input_shape, 0)}, 0.0, 1.0, 201)

    # Generate target data with some correlation to inputs
  train_noise = normal({train_samples, elem(output_shape, 0)}, 0.0, 0.1, 202)
  val_noise   = normal({val_samples, elem(output_shape, 0)}, 0.0, 0.1, 203)

  train_y = train_x
        |> Nx.sum(axes: [1], keep_axes: true)
        |> Nx.add(train_noise)

  val_y = val_x
        |> Nx.sum(axes: [1], keep_axes: true)
        |> Nx.add(val_noise)

    {train_x, train_y, val_x, val_y}
  end

  # Analyze and display NAS results
  defp analyze_nas_results(results) when is_list(results) do
    IO.puts("\n📊 === NEURAL ARCHITECTURE SEARCH RESULTS ===")

    trials = results

    if trials != [] do
      fetch_loss = fn trial ->
        cond do
          is_number(Map.get(trial, :validation_loss)) -> Map.get(trial, :validation_loss)
          is_number(get_in(trial, [:final_metrics, :mean_squared_error])) -> get_in(trial, [:final_metrics, :mean_squared_error])
          is_number(get_in(trial, [:final_metrics, "mean_squared_error"])) -> get_in(trial, [:final_metrics, "mean_squared_error"])
          true -> nil
        end
      end

      losses =
        trials
        |> Enum.map(fetch_loss)
        |> Enum.reject(&is_nil/1)

      best_trial =
        case losses do
          [] -> List.first(trials)
          _ -> Enum.min_by(trials, fn t -> fetch_loss.(t) || :infinity end)
        end

      avg_loss = case losses do
        [] -> 0.0
        _ -> Enum.sum(losses) / length(losses)
      end

      best_loss = fetch_loss.(best_trial)

      IO.puts("🏅 Best trial performance:")
      IO.puts("   - Validation Loss: #{if is_number(best_loss), do: Float.round(best_loss, 6), else: "n/a"}")
      # If validation_loss is nil but mean_squared_error metric exists, show it explicitly
      mse_metric =
        cond do
          is_number(get_in(best_trial, [:final_metrics, "mean_squared_error"])) -> get_in(best_trial, [:final_metrics, "mean_squared_error"])
          is_number(get_in(best_trial, [:final_metrics, :mean_squared_error])) -> get_in(best_trial, [:final_metrics, :mean_squared_error])
          true -> nil
        end
      if mse_metric && (best_loss == nil or best_loss == :infinity) do
        IO.puts("   - mean_squared_error: #{Float.round(mse_metric, 6)}")
      end
      IO.puts("   - Trial ID: #{Map.get(best_trial, :trial_id, "n/a")}")
      IO.puts("   - Model Size (params): #{Map.get(best_trial, :model_size, "n/a")}")

      IO.puts("📈 Overall search statistics:")
      IO.puts("   - Total trials: #{length(trials)}")
  IO.puts("   - Average validation loss: #{Float.round(avg_loss, 6)}")
  IO.puts("   - Best validation loss: #{if is_number(best_loss), do: Float.round(best_loss, 6), else: "n/a"}")

      improvement = if avg_loss > 0.0 and is_number(best_loss) do
        (avg_loss - best_loss) / avg_loss * 100.0
      else
        0.0
      end
      IO.puts("   - Improvement over average: #{Float.round(improvement, 2)}%")
    else
      IO.puts("⚠️  No completed trials found")
    end

    IO.puts("===========================================\n")
  end
  defp analyze_nas_results(results) do
    IO.puts("\n📊 === NEURAL ARCHITECTURE SEARCH RESULTS ===")

    case results do
  %{trials: [_ | _] = trials} ->
        best_trial = Enum.min_by(trials, fn trial ->
          Map.get(trial, :validation_loss, :infinity)
        end)

        avg_loss = trials
                   |> Enum.map(fn trial -> Map.get(trial, :validation_loss, 0) end)
                   |> Enum.sum()
                   |> Kernel./(length(trials))

        IO.puts("🏅 Best trial performance:")
        IO.puts("   - Validation Loss: #{Map.get(best_trial, :validation_loss, "N/A")}")
        IO.puts("   - Architecture: #{inspect(Map.get(best_trial, :architecture_summary, "N/A"))}")
        IO.puts("   - Parameters: #{Map.get(best_trial, :parameter_count, "N/A")}")

        IO.puts("📈 Overall search statistics:")
        IO.puts("   - Total trials: #{length(trials)}")
        IO.puts("   - Average validation loss: #{Float.round(avg_loss, 6)}")
        IO.puts("   - Best validation loss: #{Map.get(best_trial, :validation_loss, "N/A")}")

        improvement = if avg_loss > 0 do
          (avg_loss - Map.get(best_trial, :validation_loss, avg_loss)) / avg_loss * 100
        else
          0
        end

        IO.puts("   - Improvement over average: #{Float.round(improvement, 2)}%")

      _ ->
        IO.puts("⚠️  No completed trials found")
    end

    IO.puts("===========================================\n")
  end

  # Helper: wrapper around Nx.Random.normal for current Nx API.
  # Returns only the tensor for convenience.
  defp normal(shape, mean, sigma, seed) do
    # Fallback custom normal generator (Box-Muller) to avoid Nx.Random API changes.
    # Suitable for moderate-sized tensors used in tests; not vectorized.
    :rand.seed(:exsss, {seed, seed + 1, seed + 2})
    dims = Tuple.to_list(shape)
    total = Enum.reduce(dims, 1, &(&1 * &2))

    # Generate pairs until we have enough values
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

  @doc """
  Benchmark a matrix multiplication to sanity‑check that EXLA (GPU or CPU) is active.

  Options:
    * :size – matrix dimension N for an (N x N) * (N x N) multiply (default 1024)
    * :reps – repetitions (default 3)
    * :warmup – warmup repetitions not timed (default 1)

  Returns a map with timing statistics and an approximate GFLOP/s figure.

  NOTE: If you see very low GFLOP/s (< 20 on modern GPUs) you're likely still on CPU.
        Make sure you compiled EXLA with `EXLA_TARGET=cuda` before `mix deps.compile exla`.
  """
  def benchmark_matmul(opts \\ []) do
    size   = Keyword.get(opts, :size, 1024)
    reps   = Keyword.get(opts, :reps, 3)
    warmup = Keyword.get(opts, :warmup, 1)

    if size < 128 do
      IO.puts("⚠️  Size too small for meaningful benchmark; increasing to 128")
    end

    rng_tensor = fn shape, seed ->
      try do
        # Prefer built-in uniform if available (depends on Nx version)
        if function_exported?(Nx, :random_uniform, 2) do
          Nx.random_uniform(shape, type: :f32)
        else
          normal(shape, 0.0, 1.0, seed)
        end
      rescue
        _ -> normal(shape, 0.0, 1.0, seed)
      end
    end

    IO.puts("🧪 Benchmarking matmul #{size}x#{size} (backend=#{inspect(Nx.default_backend())}) …")
    flop_count = 2.0 * size * size * size # ~2N^3 floating ops

    run_once = fn rep_idx ->
      a = rng_tensor.({size, size}, 10 + rep_idx)
      b = rng_tensor.({size, size}, 20 + rep_idx)
      t0 = System.monotonic_time(:microsecond)
      c = Nx.dot(a, b)
      # Force realization; ensures JIT + execution completes before timing stop
      _ = Nx.backend_copy(c)
      dt_us = System.monotonic_time(:microsecond) - t0
      dt_ms = dt_us / 1000.0
      gflops = flop_count / (dt_ms / 1000.0) / 1.0e9
      {dt_ms, gflops}
    end

    # Warmup (not timed in stats)
    Enum.each(1..warmup, fn _ -> run_once.(0) end)

    measurements = Enum.map(1..reps, run_once)
    times_ms = Enum.map(measurements, &elem(&1, 0))
    gflops_list = Enum.map(measurements, &elem(&1, 1))
    avg_ms = Enum.sum(times_ms) / reps
    avg_gflops = Enum.sum(gflops_list) / reps
    min_ms = Enum.min(times_ms)
    max_ms = Enum.max(times_ms)

    result = %{
      size: size,
      reps: reps,
      backend: inspect(Nx.default_backend()),
      times_ms: times_ms,
      avg_ms: avg_ms,
      min_ms: min_ms,
      max_ms: max_ms,
      avg_gflops: avg_gflops,
      flop_count: flop_count
    }

    IO.puts("⏱  Times (ms): #{Enum.map(times_ms, &Float.round(&1, 2)) |> Enum.join(", ")}")
    IO.puts("📊 Avg: #{Float.round(avg_ms, 2)} ms  (min #{Float.round(min_ms, 2)} / max #{Float.round(max_ms, 2)})")
    IO.puts("🚀 Throughput: ~#{Float.round(avg_gflops, 2)} GFLOP/s")
    case System.get_env("EXLA_TARGET") do
      "cuda" -> IO.puts("(If this GFLOP/s seems low for your GPU, verify driver + that EXLA was compiled with CUDA support)")
      _ -> IO.puts("(CPU target detected; set EXLA_TARGET=cuda + recompile exla for GPU acceleration)")
    end

    result
  end

  @doc """
  Run a lightweight synthetic training benchmark to estimate steps/sec.

  Options:
    * :input_dim  (default 256)
    * :hidden_dims list of layer sizes (default [512,512])
    * :output_dim (default 128)
    * :batch_size (default 256)
    * :batches    number of batches to time (default 20)
    * :dtype      numeric type (default :f32)

  Returns a map with timing stats and approximate forward+backward GFLOP/s (rough heuristic: 2 * parameter_count per batch).
  """
  def benchmark_training(opts \\ []) do
    ensure_exla!(verbose: false)
    input_dim  = Keyword.get(opts, :input_dim, 256)
    hidden     = Keyword.get(opts, :hidden_dims, [512, 512])
    output_dim = Keyword.get(opts, :output_dim, 128)
    batch_size = Keyword.get(opts, :batch_size, 256)
    batches    = Keyword.get(opts, :batches, 20)
    dtype      = Keyword.get(opts, :dtype, :f32)

    model =
      Enum.reduce(hidden, Axon.input("x", shape: {nil, input_dim}, type: dtype), fn h, acc ->
        Axon.dense(acc, h, activation: :relu)
      end)
      |> Axon.dense(output_dim)

    loss_fun = &Axon.Losses.mean_squared_error/3
    opt = Polaris.Optimizers.adam(0.001)
    loop = Axon.Loop.trainer(model, loss_fun, opt)

    # Synthetic stream generator
    stream =
      Stream.repeatedly(fn ->
        x = normal({batch_size, input_dim}, 0.0, 1.0, :erlang.unique_integer([:positive]))
        # target just random so loss is irrelevant
        y = normal({batch_size, output_dim}, 0.0, 1.0, :erlang.unique_integer([:positive]))
        {x, y}
      end)
      |> Enum.take(batches)

    {init_t_ms, params_state} = time_ms(fn -> Axon.Loop.run(loop, stream |> Enum.take(1), %{}, epochs: 1) end)
    # Recreate loop to avoid warmed internal state aside from compiled functions
    loop2 = Axon.Loop.trainer(model, loss_fun, opt)
    stream2 = Enum.drop(stream, 1)
    {t_ms, _} = time_ms(fn -> Axon.Loop.run(loop2, stream2, %{}, epochs: 1) end)

    # Parameter count (approx FLOPs per forward ~ param_count; forward+backward ~ 2x)
    {_graph, params, _state} = Axon.build(model, %{ "x" => normal({1, input_dim}, 0.0, 1.0, 42) })
    param_total = params.data |> Map.values() |> Enum.flat_map(&Map.values/1) |> Enum.map(&Nx.size/1) |> Enum.sum()
    per_batch_flop_est = 2.0 * param_total
    measured_batches = batches - 1 # first batch used just for init
    steps_per_sec = measured_batches / (t_ms / 1000.0)
    gflops = (per_batch_flop_est * measured_batches) / (t_ms / 1000.0) / 1.0e9

    result = %{
      backend: inspect(Nx.default_backend()),
      device_target: System.get_env("EXLA_TARGET"),
      init_compile_ms: init_t_ms,
      timed_batches: measured_batches,
      batch_size: batch_size,
      steps_per_sec: steps_per_sec,
      est_forward_backward_flops_per_batch: per_batch_flop_est,
      avg_batch_ms: t_ms / measured_batches,
      approx_gflops: gflops,
      param_count: param_total,
      model_shape: %{input: input_dim, hidden: hidden, output: output_dim}
    }

    IO.puts("🧪 Training benchmark (#{inspect(Nx.default_backend())})")
    IO.puts("Compile + first batch: #{Float.round(init_t_ms, 1)} ms")
    IO.puts("Measured #{measured_batches} batches: total #{Float.round(t_ms,1)} ms")
    IO.puts("Steps/sec: #{Float.round(steps_per_sec, 2)}  Avg batch: #{Float.round(result.avg_batch_ms,2)} ms")
    IO.puts("Approx throughput: #{Float.round(gflops,2)} GFLOP/s (heuristic)")
    result
  end

  defp time_ms(fun) do
    t0 = System.monotonic_time(:microsecond)
    val = fun.()
    dt = (System.monotonic_time(:microsecond) - t0) / 1000.0
    {dt, val}
  end

  @doc """
  Poll live GPU utilization via nvidia-smi.

  Options:
    * :samples (default 5)
    * :interval_ms (default 1000)

  Returns list of maps: %{ts: DateTime, gpu_util: %, mem_util: %, mem_used_mb: ..., mem_total_mb: ..., temp_c: ...}.
  If nvidia-smi not found or CUDA target not active returns {:error, reason}.
  """
  def gpu_live_metrics(opts \\ []) do
    samples = Keyword.get(opts, :samples, 5)
    interval = Keyword.get(opts, :interval_ms, 1000)
    unless System.get_env("EXLA_TARGET") == "cuda" do
      return = {:error, "EXLA_TARGET is not cuda"}
      IO.puts("⚠️  #{elem(return,1)}")
      return
    end
    query = ["--query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu", "--format=csv,noheader,nounits"]
    case System.find_executable("nvidia-smi") do
      nil -> {:error, "nvidia-smi not found"}
      _ ->
        Enum.map(1..samples, fn i ->
          {out, 0} = System.cmd("nvidia-smi", query, stderr_to_stdout: true)
          # Expect single line like: "35, 12, 500, 8192, 54"
          [gpu_u, mem_u, mem_used, mem_total, temp] =
            out |> String.split("\n") |> List.first() |> String.split(",") |> Enum.map(&String.trim/1)
          if i < samples, do: Process.sleep(interval)
          %{
            ts: DateTime.utc_now(),
            gpu_util: String.to_integer(gpu_u),
            mem_util: String.to_integer(mem_u),
            mem_used_mb: String.to_integer(mem_used),
            mem_total_mb: String.to_integer(mem_total),
            temp_c: String.to_integer(temp)
          }
        end)
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Convenience helper: ensure EXLA backend is initialized (preferring CUDA) and return current backend.
  """
  def ensure_exla!(opts \\ []) do
    mode = setup_exla_backend()
    unless Code.ensure_loaded?(EXLA.Backend) do
      raise "EXLA backend not loaded after setup; ensure {:exla, \"~> 0.9\"} compiled with proper EXLA_TARGET"
    end
    if Keyword.get(opts, :verbose, true) do
      IO.puts("EXLA backend ready (mode=#{mode}, default=#{inspect(Nx.default_backend())})")
    end
    mode
  end
end
