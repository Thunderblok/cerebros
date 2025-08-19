defmodule Cerebros.Sim.Ising2D do
  @moduledoc """
  Simple 2D Ising model (ferromagnetic, J=1, k_B=1) with Metropolis updates.

  This module is a lightweight simulation utility to support visualization and
  introspection tooling in Cerebros. It is not heavily optimized; emphasis is
  clarity and Nx-integration. Spin lattice values are -1 or +1.

  API:
    * `new(size, temperature, key \\ Nx.Random.key(0))`
    * `partial_sweep(state, proposals)` - attempt `proposals` random spin flips.
    * `sweep(state, proposals_per_call \\ nil)` - perform ~N^2 attempted flips.
    * `energy(lattice)` - energy per spin.
    * `magnetization(lattice)` - magnetization per spin.

  State map fields:
    :lattice (Nx.Tensor {n,n})
    :size (integer)
    :temperature (float)
    :boltzmann (precomputed probs for ΔE=4,8)
    :rng_key (Nx.Random.key)
    :step (integer attempted flips so far)
  """

  alias Nx.Random, as: R
  @type rng_key :: {non_neg_integer(), non_neg_integer()}
  @type state :: %{
          lattice: Nx.Tensor.t(),
          size: pos_integer(),
          temperature: number(),
          boltzmann: %{4 => float(), 8 => float()},
          rng_key: rng_key(),
          step: non_neg_integer()
        }

  @doc """
  Create a new random spin configuration with given lattice size and temperature.
  """
  @spec new(pos_integer(), number(), rng_key()) :: state()
  def new(n, temperature, key \\ R.key(0)) when n > 1 do
    # random spins from uniform(0,1)
    {u, key} = R.uniform(key, shape: {n, n})
    spins = Nx.less(u, 0.5) |> Nx.select(-1, 1) |> Nx.as_type(:f32)
    %{
      lattice: spins,
      size: n,
      temperature: temperature,
      boltzmann: boltzmann_cache(temperature),
      rng_key: key,
      step: 0
    }
  end

  @doc """
  Perform a vectorized batch of random flip proposals (Metropolis).
  """
  @spec partial_sweep(state(), pos_integer()) :: state()
  def partial_sweep(%{size: n} = state, proposals) when proposals > 0 do
  %{lattice: lat, rng_key: key, boltzmann: cache} = state

  # Random coordinates (flattened indices) -> convert to (i,j)
  {flat_idxs, key} = R.randint(key, 0, n * n, shape: {proposals})
    is = Nx.divide(flat_idxs, n) |> Nx.floor() |> Nx.as_type(:s64)
    js = Nx.remainder(flat_idxs, n) |> Nx.as_type(:s64)

    # Gather spins at (i,j)
    spins = take_2d(lat, is, js)

    # Neighbor sums (periodic boundary) for each coordinate
    nb_sum = neighbor_sum(lat, is, js)

  # ΔE = 2 * s * nb (use Nx ops outside defn)
  delta_e = Nx.multiply(2.0, Nx.multiply(spins, nb_sum))

    # Acceptance probabilities (only need for ΔE > 0). Bucket by 4 / 8.
    # Using piecewise selection for vectorization.
    prob_pos = Nx.select(Nx.equal(delta_e, 4.0), cache[4], 0.0)
    prob_pos = Nx.select(Nx.equal(delta_e, 8.0), cache[8], prob_pos)

  {rand_vals, key} = R.uniform(key, shape: {proposals})

    accept = Nx.less(delta_e, 0.0) |> Nx.logical_or(Nx.less(rand_vals, prob_pos))

  flipped = Nx.negate(spins)
    new_spins = Nx.select(accept, flipped, spins)

    # Scatter updates back into lattice
    new_lat = scatter_2d(lat, is, js, new_spins)

  %{state | lattice: new_lat, rng_key: key, step: state.step + proposals}
  end

  @doc """
  Perform approximately N^2 proposals (one sweep).
  """
  @spec sweep(state(), pos_integer() | nil) :: state()
  def sweep(%{size: n} = state, proposals_per_call \\ nil) do
    per = proposals_per_call || n * n |> div(8) |> max(1)
    target = n * n

    do_sweep(state, target, per)
  end

  defp do_sweep(state, remaining, _per) when remaining <= 0, do: state
  defp do_sweep(state, remaining, per) do
    batch = min(remaining, per)
    state = partial_sweep(state, batch)
    do_sweep(state, remaining - batch, per)
  end

  @doc """
  Energy per spin (J=1).
  """
  @spec energy(Nx.Tensor.t()) :: Nx.Tensor.t()
  def energy(lattice) do
    # E = -1/2N^2 Σ_s s * nb_sum (each bond counted twice) -> per spin
    n = elem(Nx.shape(lattice), 0)
    nb = full_neighbor_sum(lattice)
  e_total = Nx.multiply(-0.5, Nx.sum(Nx.multiply(lattice, nb)))
  Nx.divide(e_total, n * n)
  end

  @doc """
  Magnetization per spin.
  """
  @spec magnetization(Nx.Tensor.t()) :: Nx.Tensor.t()
  def magnetization(lattice) do
    n = elem(Nx.shape(lattice), 0)
  Nx.divide(Nx.sum(lattice), n * n)
  end

  # -- Helpers --
  defp boltzmann_cache(t) do
    %{
      4 => :math.exp(-4.0 / t),
      8 => :math.exp(-8.0 / t)
    }
  end

  # removed split3; sequential random calls advance key

  # Gather spins at vector indices
  defp take_2d(lat, is, js) do
    # Convert (i,j) -> flat and gather
    n = elem(Nx.shape(lat), 0)
  flat = Nx.add(Nx.multiply(is, n), js)
    Nx.take(Nx.reshape(lat, {n * n}), flat)
  end

  # Compute neighbor sum for each (i,j)
  defp neighbor_sum(lat, is, js) do
    n = elem(Nx.shape(lat), 0)
  up    = take_2d(lat, wrap(Nx.subtract(is, 1), n), js)
  down  = take_2d(lat, wrap(Nx.add(is, 1), n), js)
  left  = take_2d(lat, is, wrap(Nx.subtract(js, 1), n))
  right = take_2d(lat, is, wrap(Nx.add(js, 1), n))
  Nx.add(Nx.add(up, down), Nx.add(left, right))
  end

  defp wrap(idx, n) do
    Nx.remainder(Nx.add(idx, n), n)
  end

  # Scatter updated spins back; since duplicates may occur we just overwrite (acceptable for Metropolis random picks)
  defp scatter_2d(lat, is, js, values) do
    n = elem(Nx.shape(lat), 0)
  flat_idx = Nx.add(Nx.multiply(is, n), js)
    flat_lat = Nx.reshape(lat, {n * n})
  # Nx.indexed_put expects indices shape {count, rank}; rank here is 1 so reshape to {count,1}
  idx = Nx.reshape(flat_idx, {:auto, 1})
  updated = Nx.indexed_put(flat_lat, idx, values)
    Nx.reshape(updated, {n, n})
  end

  defp full_neighbor_sum(lat) do
    Nx.add(
      Nx.add(shift(lat, 1, 0), shift(lat, -1, 0)),
      Nx.add(shift(lat, 1, 1), shift(lat, -1, 1))
    )
  end

  defp shift(t, delta, axis) do
    n = elem(Nx.shape(t), axis)
    # build indices for axis with modular arithmetic
    idx = Nx.iota({n})
  new_idx = wrap(Nx.add(idx, delta), n)
    gather_axis(t, new_idx, axis)
  end

  defp gather_axis(t, indices, axis) do
    # Expand indices to match other axes using reshape + broadcast
    shape = Nx.shape(t)
    rank = tuple_size(shape)
    # Build slice of all :, replacing axis with indices
  # Simplify by transposing axis to front, gather, then transpose back
    perm = [axis | Enum.reject(Enum.to_list(0..rank-1), &(&1 == axis))]
    inv_perm = invert_permutation(perm)
    trans = Nx.transpose(t, axes: perm)
    # shape now {axis_size, ...}
    gathered = Nx.take(trans, indices)
    Nx.transpose(gathered, axes: inv_perm)
  end

  defp invert_permutation(perm) do
    perm |> Enum.with_index() |> Enum.sort_by(fn {a, _} -> a end) |> Enum.map(fn {_, i} -> i end)
  end
end
