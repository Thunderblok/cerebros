1. Quick sanity checks
Initialize and verify everything loads: Cerebros.hello() Cerebros.test_basic_functionality()

2. Minimal NAS demo (as in README)
2 architectures × 1 trial × 2 epochs (fast)
Cerebros.test_full_nas_run( input_shapes: [{10}], output_shapes: [{1}], number_of_architectures_to_try: 2, number_of_trials_per_architecture: 1, epochs: 2 )

3. Tweaking search scale
More architectures, short epochs
Cerebros.test_full_nas_run(number_of_architectures_to_try: 5, number_of_trials_per_architecture: 1, epochs: 3)

Multiple trials per architecture
Cerebros.test_full_nas_run(number_of_architectures_to_try: 3, number_of_trials_per_architecture: 3, epochs: 5)

Narrower model size range
Cerebros.test_full_nas_run(minimum_neurons_per_unit: 4, maximum_neurons_per_unit: 16, epochs: 4)

Larger hidden size exploration
Cerebros.test_full_nas_run(maximum_neurons_per_unit: 128, number_of_architectures_to_try: 4, epochs: 6)

4. Controlling depth/width
Cerebros.test_full_nas_run( minimum_levels: 1, maximum_levels: 5, minimum_units_per_level: 1, maximum_units_per_level: 4, minimum_neurons_per_unit: 8, maximum_neurons_per_unit: 64, epochs: 5 )

5. Adjusting batch & learning rate
Cerebros.test_full_nas_run(batch_size: 64, learning_rate: 0.005, epochs: 4) Cerebros.test_full_nas_run(batch_size: 16, learning_rate: 0.001, epochs: 4)

6. Capturing the full result object
{:ok, results} = Cerebros.test_full_nas_run(number_of_architectures_to_try: 2, number_of_trials_per_architecture: 1, epochs: 2) results |> Enum.map(& &1.validation_loss)

7. Inspecting best trial manually
best = Enum.min_by(results, fn r -> r.validation_loss || :infinity end) best.trial_id best.model_size best.architecture

8. Ames housing simulation demo
Cerebros.test_ames_housing_example()

9. Direct orchestrator usage (manual lifecycle)
{:ok, orch} = Cerebros.Training.Orchestrator.start_link(max_concurrent: 2) search_cfg = %{ input_shapes: [{10}], output_shapes: [{1}], number_of_architectures_to_try: 2, number_of_trials_per_architecture: 2, epochs: 3, batch_size: 32, learning_rate: 0.01 } GenServer.cast(orch, {:start_search, search_cfg})

Poll progress
Cerebros.Training.Orchestrator.list_trials(orch) :timer.sleep(3000) Cerebros.Training.Orchestrator.get_results(orch) GenServer.stop(orch)

10. Submitting a single custom spec
conn_cfg = %{ minimum_skip_connection_depth: 1, maximum_skip_connection_depth: 3, predecessor_affinity_factor_first: 1.0, predecessor_affinity_factor_main: 0.8, predecessor_affinity_factor_decay: fn _ -> 0.9 end, lateral_connection_probability: 0.2, lateral_connection_decay: fn _ -> 0.85 end, max_consecutive_lateral_connections: 2, gate_after_n_lateral_connections: 3 } spec = Cerebros.Architecture.Spec.random(conn_cfg, input_specs: [%{shape: {10}, dtype: :f32}], output_shapes: [1], min_levels: 2, max_levels: 3 ) {:ok, orch} = Cerebros.Training.Orchestrator.start_link(max_concurrent: 1) {:ok, trial_id} = Cerebros.Training.Orchestrator.submit_trial(orch, spec, %{epochs: 3, batch_size: 32, learning_rate: 0.01, dataset: :cifar10}) Process.sleep(2000) Cerebros.Training.Orchestrator.get_trial_status(orch, trial_id) Cerebros.Training.Orchestrator.get_results(orch) GenServer.stop(orch)

11. Inspect / normalize a trial’s metrics
trial = best trial.final_metrics trial.validation_loss

12. Counting parameters of a built model (ad hoc)
input = Axon.input("x", shape: {nil, 10}) model = input |> Axon.dense(32, activation: :relu) |> Axon.dense(1) {_graph, params, _state} = Axon.build(model, Nx.iota({1,10}, type: :f32)) param_total = params.data |> Map.values() |> Enum.flat_map(&Map.values/1) |> Enum.map(&Nx.size/1) |> Enum.sum()

13. Quick tensor generation sanity (normal helper)
(Inside Cerebros module only; for quick experiments replicate logic)
For generic random: use Nx.random_normal/3 if enabled or replicating custom normal:
rand_tensor = Nx.random_uniform({4,4})

14. Observing trial statuses loop
Enum.each(1..5, fn _ -> IO.inspect(Cerebros.Training.Orchestrator.list_trials(orch)) Process.sleep(1000) end)

15. Cancelling a running trial
Cerebros.Training.Orchestrator.cancel_trial(orch, trial_id)

16. Analyzing result list directly (post-run)
{:ok, res} = Cerebros.test_full_nas_run(number_of_architectures_to_try: 3, number_of_trials_per_architecture: 1, epochs: 3) Enum.map(res, &{&1.trial_id, &1.validation_loss}) Enum.sort_by(res, & &1.validation_loss)

17. Filtering architectures by depth
Enum.filter(res, fn r -> r.architecture.num_levels >= 3 end)

18. Deriving spec hashes
Enum.map(res, & &1.spec_hash) |> Enum.uniq()

19. EXLA (CPU) backend session (optional)
Before starting IEx (shell):
export EXLA_TARGET=host
Then in IEx:
Nx.default_backend(EXLA.Backend)

20. EXLA (GPU) if CUDA available
Shell before iex:
export XLA_TARGET=cuda
export NVIDIA_VISIBLE_DEVICES=all
Then:
Nx.default_backend(EXLA.Backend)

21. Timing a function
:timer.tc(fn -> Cerebros.test_full_nas_run(number_of_architectures_to_try: 1, number_of_trials_per_architecture: 1, epochs: 2) end)

22. Getting shapes & sample prediction from trained params (manual)
(From earlier param_total example)
sample = Nx.random_uniform({5,10}) preds = Axon.predict(model, params, sample) Nx.shape(preds)

23. Logging best vs average improvement (post-run)
{:ok, res2} = Cerebros.test_full_nas_run(number_of_architectures_to_try: 4, number_of_trials_per_architecture: 1, epochs: 2) losses = Enum.map(res2, & &1.validation_loss) |> Enum.reject(&is_nil/1) best = Enum.min(losses) avg = Enum.sum(losses)/length(losses) IO.puts("Improvement: #{Float.round((avg - best)/avg * 100, 2)}%")

24. Simple retry wrapper for flaky runs
retry = fn fun, attempts -> Enum.reduce_while(1..attempts, nil, fn i, _ -> case fun.() do {:ok, v} -> {:halt, {:ok, v}} {:error, e} -> IO.puts("Attempt #{i} failed: #{inspect(e)}") if i == attempts, do: {:halt, {:error, e}}, else: {:cont, nil} end end) end retry.(fn -> Cerebros.test_full_nas_run(number_of_architectures_to_try: 1, number_of_trials_per_architecture: 1, epochs: 2) end, 3)

25. Saving results manually to JSON
{:ok, res3} = Cerebros.test_full_nas_run(number_of_architectures_to_try: 2, number_of_trials_per_architecture: 1, epochs: 2) File.write!("nas_results.json", Jason.encode!(res3, pretty: true))

26. Finding largest model in a result batch
Enum.max_by(res3, & &1.model_size)

27. Extracting per-architecture level summaries
Enum.map(res3, fn r -> {r.trial_id, r.architecture.num_levels, r.architecture.total_units} end)

28. Raw Axon loop (standalone – educational)
inp = Axon.input("x", shape: {nil, 10}) mdl = inp |> Axon.dense(16, activation: :relu) |> Axon.dense(1) loss_fun = :mean_squared_error optimizer = Polaris.Optimizers.adam(0.001) loop = Axon.Loop.trainer(mdl, &Axon.Losses.mean_squared_error/3, optimizer)

Build synthetic stream
train_stream = Stream.repeatedly(fn -> x = Nx.random_uniform({32,10}) y = Nx.sum(x, axes: [1], keep_axes: true) {x,y} end) |> Enum.take(20) loop_params = Axon.Loop.run(loop, train_stream, %{}, epochs: 3)

29. Exploring a spec’s raw map
spec.architecture_spec = spec

30. Reproducibility via seed (architecture)
s1 = Cerebros.Architecture.Spec.random(conn_cfg, seed: 123, input_specs: [%{shape: {10}, dtype: :f32}], output_shapes: [1]) s2 = Cerebros.Architecture.Spec.random(conn_cfg, seed: 123, input_specs: [%{shape: {10}, dtype: :f32}], output_shapes: [1]) s1.levels == s2.levels

31. Checking connectivity builder independently (if module present)
(If you have a connectivity builder module as referenced)
{:ok, connectivity} = Cerebros.Connectivity.Builder.build_connectivity(spec) map_size(connectivity)

32. Graceful shutdown of all processes
(When you spawned orchestrator)
GenServer.stop(orch)

33. Pattern for repeated small NAS sweeps (utility)
Enum.each(1..3, fn run -> IO.puts("Run #{run}") {:ok, res} = Cerebros.test_full_nas_run(number_of_architectures_to_try: 2, number_of_trials_per_architecture: 1, epochs: 2) best = Enum.min_by(res, & &1.validation_loss) IO.inspect({run, best.validation_loss}) end)

Optional: Shell (outside IEx) helpers for environment
GPU (if available): export XLA_TARGET=cuda export NVIDIA_VISIBLE_DEVICES=all iex -S mix

Force CPU EXLA: export EXLA_TARGET=host iex -S mix

