defmodule Cerebros.Manual do
  @moduledoc """
  Experimental single-step training utilities.

  CURRENT STATUS: Gradient extraction is placeholder until we implement
  defn-based loss wrappers. This module focuses on wiring so higher layers
  can be built without waiting for full gradient capture.
  """

  require Logger

  @type step_result :: {
          updated_params :: map(),
          optimizer_state :: any(),
          loss :: float(),
          gradients :: map(),
          metadata :: map()
        }

  @doc """
  Performs a forward pass and (placeholder) returns unchanged params and empty gradients.
  Accepts an Axon model plus a predict_fn ({init,predict} from Axon.build).
  """
  @spec single_step(Axon.t(), map(), any(), (map(), map() -> Nx.Tensor.t()), map(), map(), keyword()) :: step_result()
  def single_step(model, params, opt_state, predict_fn, inputs, targets, opts \\ []) do
    loss_fun = Keyword.get(opts, :loss_fun, &default_mse_loss/2)
    preds = predict_fn.(params, inputs)
    loss = loss_fun.(preds, targets) |> Nx.to_number()
    Logger.debug("single_step loss=#{loss}")
    # TODO: integrate gradient calc via defn; for now passthrough.
    {params, opt_state, loss, %{}, %{output_shape: Nx.shape(preds), model_id: :erlang.phash2(model)}}
  end

  defp default_mse_loss(preds, targets) do
    Axon.Losses.mean_squared_error(preds, targets, reduction: :mean)
  end
end
