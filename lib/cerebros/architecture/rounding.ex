defmodule Cerebros.Architecture.Rounding do
  @moduledoc """
  Rounding / normalization utilities for neuron counts.

  This is an optional feature layer: existing generation is unchanged unless
  `round_neurons:` is passed to `Cerebros.Architecture.Spec.random/2`.
  """

  import Bitwise

  @type strategy :: :none | :power_of_two | :growth_series | {:multiple_of, pos_integer()} | {:steps, [pos_integer()]} | (pos_integer() -> pos_integer())

  @doc """
  Apply rounding strategy to a neuron count. Always returns >= 1.
  """
  @spec round_neurons(pos_integer(), strategy()) :: pos_integer()
  def round_neurons(count, _strategy) when count <= 0, do: 1
  def round_neurons(count, :none), do: count
  def round_neurons(count, :power_of_two), do: next_power_of_two(count)
  def round_neurons(count, :growth_series) do
    growth_series_round(count)
  end
  def round_neurons(count, {:multiple_of, k}) when k > 0 do
    r = rem(count, k)
    if r == 0, do: count, else: count + (k - r)
  end
  def round_neurons(_count, {:steps, []}), do: 1
  def round_neurons(count, {:steps, steps}) when is_list(steps) do
    Enum.reduce(steps, hd(steps), fn step, acc ->
      if abs(step - count) < abs(acc - count), do: step, else: acc
    end)
  end
  def round_neurons(count, fun) when is_function(fun, 1) do
    case fun.(count) do
      n when is_integer(n) and n > 0 -> n
      _ -> count
    end
  end

  @doc """
  Parse simple user-friendly inputs into a rounding strategy.
  Examples:
    8 -> {:multiple_of, 8}
    [:5, 10, 20] -> {:steps, [5, 10, 20]}
    :power_of_two -> :power_of_two
  """
  @spec parse(any()) :: strategy()
  def parse(nil), do: :none
  def parse(:none), do: :none
  def parse(:power_of_two), do: :power_of_two
  # Backwards compatibility for deprecated whimsical names
  def parse(:phi), do: :growth_series
  def parse(:golden_ratio), do: :growth_series
  def parse(:growth_series), do: :growth_series
  def parse(k) when is_integer(k) and k > 1, do: {:multiple_of, k}
  def parse(list) when is_list(list) and list != [] do
    if Enum.all?(list, fn x -> is_integer(x) end) do
      {:steps, Enum.sort(list)}
    else
      :none
    end
  end
  def parse(fun) when is_function(fun, 1), do: fun
  def parse(_), do: :none

  # -- internal helpers --
  defp next_power_of_two(n) when n <= 1, do: 1
  defp next_power_of_two(n) do
    if (n &&& (n - 1)) == 0 do
      n
    else
      p = n - 1
      p = p ||| (p >>> 1)
      p = p ||| (p >>> 2)
      p = p ||| (p >>> 4)
      p = p ||| (p >>> 8)
      p = p ||| (p >>> 16)
      p + 1
    end
  end

  # Growth series rounding: uses an irrational-base exponential sequence to
  # produce smoothly increasing bucket sizes; keeps strictly increasing
  # sequence starting at 1 while offering diversity vs power-of-two.
  defp growth_series_round(n) when n <= 1, do: 1
  defp growth_series_round(n) do
    base = (1 + :math.sqrt(5.0)) / 2.0 # retained constant, but semantics renamed
    grow_series(n, base, 1, 1)
  end

  defp grow_series(target, base, k, prev) do
    candidate = trunc(:math.pow(base, k))
    cond do
      candidate == target -> candidate
      candidate > target -> choose_nearest(prev, candidate, target)
      true ->
        # Avoid stagnation if pow truncated to previous (rare for small k)
        next = if candidate <= prev, do: prev + 1, else: candidate
        grow_series(target, base, k + 1, next)
    end
  end

  defp choose_nearest(a, b, target) do
    if abs(a - target) <= abs(b - target), do: a, else: b
  end
end
