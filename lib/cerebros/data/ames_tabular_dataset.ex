defmodule Cerebros.Data.AmesTabularDataset do
  @moduledoc """
  Lightweight dataset adapter wrapping the existing Ames loading logic.

  This bridges current ad-hoc helpers to the new `Cerebros.Data.Dataset` behaviour.
  """
  @behaviour Cerebros.Data.Dataset

  defstruct [:train_x, :train_y, :val_x, :val_y, :task]

  @type t :: %__MODULE__{}

  @spec from_current_loader() :: {:ok, t()} | {:error, term()}
  def from_current_loader() do
    case apply(Cerebros, :load_ames_data, []) do
      {:ok, {train_x, train_y, val_x, val_y, _feat_count}} ->
        {:ok, %__MODULE__{train_x: train_x, train_y: train_y, val_x: val_x, val_y: val_y, task: :regression}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def info(%__MODULE__{train_x: tx, val_x: vx} = ds) do
    {train_sz, _} = Nx.shape(tx)
    {val_sz, _} = Nx.shape(vx)
    %{
      task: ds.task,
      input_shapes: [{elem(Nx.shape(tx), 1)}],
      output_shapes: [{1}],
      size: %{train: train_sz, val: val_sz},
      classes?: nil
    }
  end

  @impl true
  def stream(%__MODULE__{train_x: tx, train_y: ty}, :train), do: build_stream(tx, ty)
  def stream(%__MODULE__{val_x: vx, val_y: vy}, :val), do: build_stream(vx, vy)

  defp build_stream(x, y) do
    {n, _} = Nx.shape(x)
    0..(n-1)
    |> Stream.map(fn i ->
      feat = x[i]
      target = y[i]
      %{input: %{"input_0" => feat}, target: target}
    end)
  end

  @impl true
  def preprocess(_ds, sample), do: sample

  @impl true
  def to_batch(samples, _opts) do
    inputs =
      samples
      |> Enum.map(& &1.input["input_0"])
      |> Nx.stack()

    targets =
      samples
      |> Enum.map(& &1.target)
      |> Nx.stack()

    {%{"input_0" => inputs}, targets}
  end
end
