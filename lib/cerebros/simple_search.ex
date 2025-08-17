defmodule Cerebros.SimpleSearch do
  @moduledoc """
  Minimal high-level API to run a stubbed architecture search returning an artifact.

  Intentionally lightweight so Thunderline can integrate before full trainer wiring.
  Later we will replace the stub metric with real training results.
  """

  alias Cerebros.{Artifacts, Networks.Builder}
  alias Cerebros.Data.AmesTabularDataset

  @default_trials 3

  def run(opts \\ []) do
    dataset_opt = Keyword.get(opts, :dataset, :ames)
    trials = Keyword.get(opts, :trials, @default_trials)
    seed = Keyword.get(opts, :seed, System.unique_integer())
    param_budget = Keyword.get(opts, :param_budget, 1_000_000)

    {:ok, dataset} = load_dataset(dataset_opt)
    ds_info = dataset |> AmesTabularDataset.info()

    trial_results =
      1..trials
      |> Enum.map(fn t ->
        trial_seed = seed + t
        spec = build_random_spec(ds_info, trial_seed)
        {:ok, model} = Builder.build_model(spec)
        # Stub params/state for now
        {init_fn, _pred_fn} = Axon.build(model)
  dummy_input = %{"input_0" => random_tensor({1, elem(hd(ds_info.input_shapes), 0)}, trial_seed)}
        params = init_fn.(dummy_input, Axon.ModelState.empty())
        state = %{}
        pcount = Cerebros.Utils.ParamCount.parameter_count(model)
        fake_metric = fake_validation_loss(pcount, param_budget, trial_seed)
        %{trial: t, seed: trial_seed, spec: spec, model: model, params: params, state: state, val_loss: fake_metric, param_count: pcount}
      end)

    best = Enum.min_by(trial_results, & &1.val_loss)

    envelope =
      Artifacts.build_envelope(
        best.model,
        best.params,
        best.state,
        spec_map(best.spec),
        %{objective: :val_loss, val_loss: best.val_loss},
        %{pipeline: :inline_stub},
        %{epochs: 0, batch_size: nil, optimizer: :none, lr: nil},
        %{trial_seed: best.seed, search_seed: seed}
      )

    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    out_dir = Path.join(["artifacts", "simple_search", Integer.to_string(timestamp)])
    {:ok, paths} = Artifacts.persist(envelope, out_dir)

    {:ok,
     %{
       trials: length(trial_results),
       best_val_loss: best.val_loss,
       best_param_count: best.param_count,
       artifact: paths,
       envelope: Map.drop(envelope, [:model])
     }}
  end

  defp load_dataset(:ames), do: AmesTabularDataset.from_current_loader()
  defp load_dataset(other), do: {:error, {:unsupported_dataset, other}}

  defp fake_validation_loss(param_count, budget, seed) do
    :rand.seed(:exsss, {seed, seed+1, seed+2})
    base = :rand.uniform() * 0.5 + 0.1
  over = max(param_count - budget, 0)
  ratio = over / max(budget, 1)
  # log1p(x) ≈ log(1 + x)
  penalty = :math.log(1 + ratio)
    base + penalty
  end

  defp build_random_spec(ds_info, seed) do
    :rand.seed(:exsss, {seed, seed+1, seed+2})
    levels = Enum.random(2..3)
  _units_per_level = Enum.random(1..3)
    max_neurons = Enum.random(8..32)

    level_defs =
      for l <- 0..levels do
        is_final = l == levels
        %{
          level_number: l,
          unit_type: :dense,
          units: [
            %{unit_id: 0, neurons: (if is_final, do: 1, else: Enum.random(4..max_neurons)), activation: (if is_final, do: nil, else: :relu)}
          ],
          is_final: is_final
        }
      end

    %Cerebros.Architecture.Spec{
      input_specs: Enum.with_index(ds_info.input_shapes) |> Enum.map(fn {{dim}, idx} -> %{shape: {dim}, name: "input_#{idx}"} end),
      output_shapes: ds_info.output_shapes,
      levels: level_defs,
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
      seed: seed
    }
  end

  defp spec_map(%Cerebros.Architecture.Spec{} = spec) do
    %{
      input_specs: spec.input_specs,
      output_shapes: spec.output_shapes,
      levels: spec.levels,
      seed: spec.seed
    }
  end

  defp random_tensor(shape, seed) do
    # Simple uniform 0..1 approximation using custom generator then cast to f32
    :rand.seed(:exsss, {seed, seed+11, seed+111})
    total = shape |> Tuple.to_list() |> Enum.product()
    vals = for _ <- 1..total, do: :rand.uniform()
    Nx.tensor(vals, type: :f32) |> Nx.reshape(shape)
  end
end
