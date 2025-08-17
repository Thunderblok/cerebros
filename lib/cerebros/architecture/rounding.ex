defmodule Cerebros.Architecture.Rounding do
  @moduledoc """
  Rounding / normalization utilities for neuron counts.

  This is an optional feature layer: existing generation is unchanged unless
  `round_neurons:` is passed to `Cerebros.Architecture.Spec.random/2`.
  """

  import Bitwise

  @type strategy :: :none | :power_of_two | {:multiple_of, pos_integer()} | {:steps, [pos_integer()]} | (pos_integer() -> pos_integer())

  @doc """
  Apply rounding strategy to a neuron count. Always returns >= 1.
  """
  @spec round_neurons(pos_integer(), strategy()) :: pos_integer()
  def round_neurons(count, _strategy) when count <= 0, do: 1
  def round_neurons(count, :none), do: count
  def round_neurons(count, :power_of_two), do: next_power_of_two(count)
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
end
