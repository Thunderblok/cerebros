defmodule Cerebros.Viz.Heatmap do
  @moduledoc """
  Converts 1D / 2D tensors into normalized RGB heatmaps (Nx tensors).
  Designed for eventual PNG or ANSI export.
  """

  @type colormap :: :turbo | :grayscale | :blue_red

  @doc """
  Return `{heatmap, min, max}` where heatmap has shape `{h, w, 3}`.
  """
  @spec tensor_to_heatmap(Nx.Tensor.t(), keyword()) :: {Nx.Tensor.t(), float(), float()}
  def tensor_to_heatmap(t, opts \\ []) do
    cmap = Keyword.get(opts, :colormap, :turbo)
    {matrix, h, w} = ensure_2d(t)
    minv = Nx.reduce_min(matrix) |> Nx.to_number()
    maxv = Nx.reduce_max(matrix) |> Nx.to_number()
    denom = max(maxv - minv, 1.0e-12)
    norm = (matrix - minv) / denom

    rgb = apply_colormap(norm, cmap)
    {Nx.reshape(rgb, {h, w, 3}), minv, maxv}
  end

  defp ensure_2d(tensor) do
    shape = Nx.shape(tensor)

    case shape do
      {h, w} -> {tensor, h, w}
      {n} ->
        side = trunc(:math.sqrt(n))
        side = if side * side < n, do: side + 1, else: side
        padded = Nx.pad(tensor, 0.0, [{0, side * side - n, 0}])
        {Nx.reshape(padded, {side, side}), side, side}

      _ ->
        flat = Nx.reshape(tensor, {:auto})
        ensure_2d(flat)
    end
  end

  defp apply_colormap(norm, :grayscale), do: Nx.stack([norm, norm, norm], axis: -1)

  defp apply_colormap(norm, :blue_red) do
    r = norm
    g = Nx.broadcast(0.0, Nx.shape(norm))
    b = 1.0 - norm
    Nx.stack([r, g, b], axis: -1)
  end

  defp apply_colormap(norm, :turbo) do
    # Simple approximation: map norm -> (r,g,b) via polynomial slices.
    r = Nx.power(norm, 0.5)
    g = Nx.power(norm, 1.2)
    b = Nx.power(1.0 - norm, 0.7)
    Nx.stack([r, g, b], axis: -1)
  end
end
