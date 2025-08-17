defmodule Cerebros.Data.Dataset do
  @moduledoc """
  Behaviour defining the contract for datasets used by Cerebros searches.

  This isolates data ingestion & preprocessing from architecture/training logic.

  A dataset implementation should be a struct carrying any necessary internal
  state and implement the callbacks below.
  """

  @type split :: :train | :val
  @type sample :: %{input: map(), target: Nx.t()}
  @type t :: struct()

  @callback info(t()) :: %{
              task: :regression | :classification,
              input_shapes: [tuple()],
              output_shapes: [tuple()],
              size: %{train: non_neg_integer(), val: non_neg_integer()},
              classes?: nil | [any()]
            }
  @callback stream(t(), split()) :: Enumerable.t()
  @callback to_batch([sample()], keyword()) :: {%{String.t() => Nx.t()}, Nx.t()}
  @callback preprocess(t(), raw :: any()) :: sample()
end
