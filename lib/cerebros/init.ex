defmodule Cerebros.Init do
  @moduledoc """
  Pluggable parameter initializer utilities.

  Provides deterministic, seedable initializers to match lower-level engines
  where explicit control over weight/bias initialization is required for
  visualization or reproducibility.
  """

  alias Nx.Random, as: R

  @type shape :: tuple()
  @type key :: Nx.Random.key()

  @doc """
  Returns `{tensor, new_key}` for a constant initializer.
  """
  @spec constant(number(), shape(), key()) :: {Nx.Tensor, key()}
  def constant(val, shape, key) do
    {Nx.broadcast(val, shape), key}
  end

  @spec uniform({number(), number()}, shape(), key()) :: {Nx.Tensor, key()}
  def uniform({min, max}, shape, key) do
    {k1, k2} = R.split(key)
    scale = max - min
  t = R.uniform(k1, shape) * scale + min
    {t, k2}
  end

  @spec normal({number(), number()}, shape(), key()) :: {Nx.Tensor, key()}
  def normal({mean, std}, shape, key) do
    {k1, k2} = R.split(key)
  t = R.normal(k1, shape) * std + mean
    {t, k2}
  end

  @doc """
  Xavier / Glorot uniform initializer.
  """
  @spec glorot_uniform(pos_integer(), pos_integer(), shape(), key()) :: {Nx.Tensor, key()}
  def glorot_uniform(fan_in, fan_out, shape, key) do
    limit = :math.sqrt(6.0 / (fan_in + fan_out))
    uniform({-limit, limit}, shape, key)
  end

  @spec he_uniform(pos_integer(), shape(), key()) :: {Nx.Tensor, key()}
  def he_uniform(fan_in, shape, key) do
    limit = :math.sqrt(6.0 / fan_in)
    uniform({-limit, limit}, shape, key)
  end

  @doc """
  Dispatcher by atom spec.

  Options:
    * `:seed` - reproducibility seed (default 1337)
    * `:fan_in`, `:fan_out` - required for some initializers
    * `:value` - for `:constant`
    * `:range` - for `:uniform` (tuple {min,max})
    * `:mu_sigma` - for `:normal` (tuple {mean,std})
  """
  @spec build(atom(), shape(), keyword()) :: Nx.Tensor
  def build(kind, shape, opts \\ []) do
    seed = Keyword.get(opts, :seed, 1337)
    key = Nx.Random.key(seed)
    fan_in = Keyword.get(opts, :fan_in)
    fan_out = Keyword.get(opts, :fan_out)

    {tensor, _} =
      case kind do
        :constant -> constant(Keyword.fetch!(opts, :value), shape, key)
        :uniform -> uniform(Keyword.get(opts, :range, {-0.1, 0.1}), shape, key)
        :normal -> normal(Keyword.get(opts, :mu_sigma, {0.0, 0.02}), shape, key)
        :glorot -> glorot_uniform(fan_in, fan_out, shape, key)
        :he -> he_uniform(fan_in, shape, key)
        other -> raise "Unsupported initializer #{inspect(other)}"
      end

    tensor
  end
end
