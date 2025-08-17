defmodule Cerebros.Search.Ranking do
  @moduledoc """
  Composite heuristic ranking for trial results (optional utility layer).

  Scoring formula (defaults aim to be simple and easily swappable):
    score = w_acc * accuracy - w_loss * loss - w_params * log10(params + 1)
            - w_time * log10(training_time_ms + 1)

  Missing metrics contribute 0.
  """

  @type result :: map()
  @type weights :: %{
          optional(:accuracy) => number(),
          optional(:loss) => number(),
          optional(:parameters) => number(),
          optional(:training_time) => number()
        }

  @default_weights %{accuracy: 1.0, loss: 0.5, parameters: 0.1, training_time: 0.05}

  @spec score(result(), weights()) :: float()
  def score(result, weights_override \\ %{}) do
    w = Map.merge(@default_weights, weights_override)
    acc = fetch_metric(result, ["accuracy", :accuracy])
    loss = fetch_metric(result, ["loss", :loss])
    params = Map.get(result, :model_size) || Map.get(result, "model_size") || 0
    time = Map.get(result, :training_time_ms) || Map.get(result, "training_time_ms") || 0

    acc_term = w.accuracy * acc
    loss_term = w.loss * loss
    param_penalty = w.parameters * safe_log10(params + 1)
    time_penalty = w.training_time * safe_log10(time + 1)
    acc_term - loss_term - param_penalty - time_penalty
  end

  @spec rank([result()], weights()) :: [{float(), result()}]
  def rank(results, weights_override \\ %{}) do
    results
    |> Enum.map(fn r -> {score(r, weights_override), r} end)
    |> Enum.sort_by(fn {s, _} -> s end, :desc)
  end

  defp fetch_metric(result, keys) do
    metrics = Map.get(result, :final_metrics) || Map.get(result, "final_metrics") || %{}
    Enum.find_value(keys, 0.0, fn k ->
      case Map.get(metrics, k) do
        %Nx.Tensor{} = t -> Nx.to_number(t)
        v when is_number(v) -> v
        _ -> nil
      end
    end)
  end

  defp safe_log10(0), do: 0.0
  defp safe_log10(n), do: :math.log10(n)
end
