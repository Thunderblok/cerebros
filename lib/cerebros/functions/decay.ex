defmodule Cerebros.Functions.Decay do
  @moduledoc """
  Parity layer for original Python Cerebros decay and gating helper functions.

  Implements:
    * zero_7_exp_decay/1   (≈ 0.7^x with x>=1, 1.0 when x==0)
    * zero_95_exp_decay/1  (≈ 0.95^x with x>=1, 1.0 when x==0)
    * simple_sigmoid/1     (logistic 1/(1+e^-x))

  The original Python used JAX JIT. Here we keep them pure & lightweight.

  In addition we provide a small preset resolution API so search parameter
  maps can specify atoms (e.g. :zero_7_exp_decay) instead of anonymous
  functions. This keeps CLI / config usage ergonomic while still storing
  executable funs inside specs.
  """

  @spec zero_7_exp_decay(non_neg_integer() | number()) :: float()
  def zero_7_exp_decay(0), do: 1.0
  def zero_7_exp_decay(x) when is_integer(x) and x > 0, do: :math.pow(0.7, x)
  def zero_7_exp_decay(x) when is_number(x), do: :math.pow(0.7, x)

  @spec zero_95_exp_decay(non_neg_integer() | number()) :: float()
  def zero_95_exp_decay(0), do: 1.0
  def zero_95_exp_decay(x) when is_integer(x) and x > 0, do: :math.pow(0.95, x)
  def zero_95_exp_decay(x) when is_number(x), do: :math.pow(0.95, x)

  @spec simple_sigmoid(number()) :: float()
  def simple_sigmoid(x) do
    1.0 / (1.0 + :math.exp(-x))
  end

  @doc """
  Resolves a preset decay function name (atom) or returns the function
  unchanged if already a 1-arity function. Falls back to identity if the
  input is nil or unrecognised.

  Accepted atoms:
    :zero_7_exp_decay
    :zero_95_exp_decay
    :simple_sigmoid
    :identity
  """
  @spec resolve_decay((number() -> number()) | atom() | nil) :: (number() -> number())
  def resolve_decay(fun) when is_function(fun, 1), do: fun
  def resolve_decay(nil), do: fn x -> x end
  def resolve_decay(atom) when is_atom(atom) do
    case atom do
      :zero_7_exp_decay -> &__MODULE__.zero_7_exp_decay/1
      :zero_95_exp_decay -> &__MODULE__.zero_95_exp_decay/1
      :simple_sigmoid -> &__MODULE__.simple_sigmoid/1
      :identity -> fn x -> x end
      _ -> fn x -> x end
    end
  end
end
