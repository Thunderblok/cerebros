defmodule Cerebros.Utils.ParamCount do
  @moduledoc """
  Utility functions for parameter counting and model size reporting.

  Axon deprecated direct parameter count helpers; this module implements
  a traversal over the parameter tree returned by `Axon.get_parameters/1`.
  """

  @doc """
  Returns the total number of scalar parameters in an Axon model.
  """
  @spec parameter_count(Axon.t()) :: non_neg_integer()
  def parameter_count(model) do
    model
    |> Axon.get_parameters()
    |> count_any()
  end

  defp count_any(%{} = map) do
    Enum.reduce(map, 0, fn {_k, v}, acc -> acc + count_any(v) end)
  end

  defp count_any(list) when is_list(list) do
    Enum.reduce(list, 0, fn v, acc -> acc + count_any(v) end)
  end

  defp count_any(tensor) do
    case tensor do
      %Nx.Tensor{} = t -> Nx.size(t)
      _other -> 0
    end
  end
end
