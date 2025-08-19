defmodule Cerebros.Introspect.Snapshot do
  @moduledoc """
  Data structure representing a captured training/introspection step.
  """

  @enforce_keys [:step, :loss, :timestamp]
  defstruct step: 0,
            loss: nil,
            weights: %{},
            biases: %{},
            activations: %{},
            gradients: %{},
            metadata: %{},
            timestamp: nil

  @type t :: %__MODULE__{
          step: non_neg_integer(),
          loss: float() | nil,
          weights: map(),
          biases: map(),
          activations: map(),
          gradients: map(),
          metadata: map(),
          timestamp: DateTime.t()
        }
end
