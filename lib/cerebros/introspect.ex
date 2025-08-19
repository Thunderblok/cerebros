defmodule Cerebros.Introspect do
  @moduledoc """
  Forward pass capture and parameter flattening utilities.

  NOTE: Intermediate layer activation capture for Axon graphs will require
  deeper graph walking; for now we expose parameter + final output capture.
  """

  alias Cerebros.Introspect.Snapshot

  @doc """
  Capture a lightweight snapshot (no gradients yet) after a forward call.
  `predict_fn` is the function returned from `Axon.build/1` (second element).
  `params` is the current parameter map; `inputs` is map of input name => tensor.
  """
  @spec capture(non_neg_integer(), map(), map(), (map(), map() -> Nx.Tensor.t()), keyword()) :: Snapshot.t()
  def capture(step, params, inputs, predict_fn, opts \\ []) do
    loss = Keyword.get(opts, :loss)
    output = predict_fn.(params, inputs)
    flat_params = flatten_params(params)
    %Snapshot{
      step: step,
      loss: loss,
      weights: flat_params.weights,
      biases: flat_params.biases,
      activations: %{final_output: output},
      gradients: %{},
      metadata: %{output_shape: Nx.shape(output)},
      timestamp: DateTime.utc_now()
    }
  end

  defp flatten_params(params) do
    # Heuristic separation: treat 1-D as bias, >=2-D as weight.
    Enum.reduce(params, %{weights: %{}, biases: %{}}, fn {k, v}, acc ->
      case v do
        %Nx.Tensor{} = t -> classify_param(acc, k, t)
        %{} = sub -> merge_nested(acc, k, sub)
        _ -> acc
      end
    end)
  end

  defp merge_nested(acc, prefix, sub) do
    Enum.reduce(sub, acc, fn {k, v}, a ->
      key = "#{prefix}.#{k}" |> String.to_atom()
      classify_param(a, key, v)
    end)
  end

  defp classify_param(acc, key, %Nx.Tensor{} = t) do
    target = if tuple_size(Nx.shape(t)) <= 1, do: :biases, else: :weights
    put_in(acc, [target, key], t)
  end
end
