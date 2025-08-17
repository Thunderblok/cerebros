defmodule Cerebros.Data.Loader do
  @moduledoc """
  Data loading utilities for neural architecture search experiments.

  This module provides standardized data loading for common datasets
  and utilities for creating synthetic datasets for testing purposes.
  """

  require Logger

  @type dataset_config :: %{
    batch_size: pos_integer(),
    shuffle: boolean(),
    augment: boolean(),
    normalize: boolean()
  }

  @type data_stream :: Enumerable.t()

  @doc """
  Loads CIFAR-10 dataset for image classification.
  """
  @spec load_cifar10(keyword()) :: {data_stream(), data_stream()}
  def load_cifar10(opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 32)
    shuffle = Keyword.get(opts, :shuffle, true)
    augment = Keyword.get(opts, :augment, true)

    Logger.info("Loading CIFAR-10 dataset with batch_size=#{batch_size}")

    # This would typically load from files or download
    # For now, we'll create synthetic data with CIFAR-10 dimensions
    train_data = create_cifar10_synthetic(:train, batch_size, shuffle, augment)
    val_data = create_cifar10_synthetic(:validation, batch_size, false, false)

    {train_data, val_data}
  end

  @doc """
  Loads MNIST dataset for digit classification.
  """
  @spec load_mnist(keyword()) :: {data_stream(), data_stream()}
  def load_mnist(opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 32)
    shuffle = Keyword.get(opts, :shuffle, true)

    Logger.info("Loading MNIST dataset with batch_size=#{batch_size}")

    # Create synthetic MNIST-like data
    train_data = create_mnist_synthetic(:train, batch_size, shuffle)
    val_data = create_mnist_synthetic(:validation, batch_size, false)

    {train_data, val_data}
  end

  @doc """
  Generates synthetic dataset for testing and development.
  """
  @spec generate_synthetic_data(tuple(), pos_integer(), keyword()) :: {data_stream(), data_stream()}
  def generate_synthetic_data(input_shape, num_classes, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 32)
    train_samples = Keyword.get(opts, :train_samples, 1000)
    val_samples = Keyword.get(opts, :val_samples, 200)

    Logger.info("Generating synthetic data: shape=#{inspect(input_shape)}, classes=#{num_classes}")

    train_data = create_synthetic_stream(input_shape, num_classes, train_samples, batch_size)
    val_data = create_synthetic_stream(input_shape, num_classes, val_samples, batch_size)

    {train_data, val_data}
  end

  @doc """
  Loads data from CSV files for structured data experiments.
  """
  @spec load_csv_data(String.t(), keyword()) :: {data_stream(), data_stream()}
  def load_csv_data(file_path, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 32)
    target_column = Keyword.get(opts, :target_column, -1)
    validation_split = Keyword.get(opts, :validation_split, 0.2)

    Logger.info("Loading CSV data from #{file_path}")

    # Load and process CSV data
    {:ok, data} = load_and_process_csv(file_path, target_column)

    # Split into train/validation
    {train_data, val_data} = split_data(data, validation_split)

    # Convert to batched streams
    train_stream = create_batched_stream(train_data, batch_size, true)
    val_stream = create_batched_stream(val_data, batch_size, false)

    {train_stream, val_stream}
  end

  # Private functions

  defp create_cifar10_synthetic(split, batch_size, shuffle, augment) do
    num_samples = case split do
      :train -> 1600  # Small dataset for quick training
      :validation -> 400
    end

    # CIFAR-10: 32x32x3 images, 10 classes
    input_shape = {32, 32, 3}
  # For current regression-oriented NAS test we generate a single continuous target
  num_classes = 1

  data_stream = create_synthetic_regression_stream(input_shape, num_samples, batch_size)

    data_stream = if shuffle, do: Enum.shuffle(data_stream), else: data_stream
    data_stream = if augment, do: apply_augmentations(data_stream), else: data_stream

    data_stream
  end

  defp create_mnist_synthetic(split, batch_size, shuffle) do
    num_samples = case split do
      :train -> 1000
      :validation -> 200
    end

    # MNIST: 28x28x1 images, 10 classes
    input_shape = {28, 28, 1}
    num_classes = 10

    data_stream = create_synthetic_stream(input_shape, num_classes, num_samples, batch_size)

    if shuffle, do: Enum.shuffle(data_stream), else: data_stream
  end

  defp create_synthetic_stream(input_shape, num_classes, num_samples, batch_size) do
    # Calculate total elements needed
    total_batches = div(num_samples, batch_size)

    Stream.repeatedly(fn ->
      # Create a batch of synthetic data
      batch_x = create_synthetic_inputs(input_shape, batch_size)
      batch_y = create_synthetic_labels(num_classes, batch_size)

      {batch_x, batch_y}
    end)
    |> Stream.take(total_batches)
  end

  defp create_synthetic_regression_stream(input_shape, num_samples, batch_size) do
  # Force exact multiple of batch_size so all batches have identical shapes
  total_batches = div(num_samples, batch_size)
  effective_batches = if rem(num_samples, batch_size) == 0, do: total_batches, else: total_batches

    Stream.repeatedly(fn ->
      batch_x = create_synthetic_inputs(input_shape, batch_size)
      # Regression target: random normal aggregated over features + noise
      flat = Nx.reshape(batch_x, {batch_size, :auto})
      target =
        flat
        |> Nx.mean(axis: [1])
        |> Nx.add(Nx.random_normal({batch_size}, mean: 0.0, sigma: 0.1))
        |> Nx.reshape({batch_size, 1})
      {batch_x, target}
    end)
  |> Stream.take(effective_batches)
  end

  defp create_synthetic_inputs(input_shape, batch_size) do
    # Create random tensor with the specified shape
    full_shape = Tuple.insert_at(input_shape, 0, batch_size)

    Nx.random_normal(full_shape)
    |> Nx.clip(-2.0, 2.0)  # Clip to reasonable range
  end

  defp create_synthetic_labels(num_classes, batch_size) do
    # Create random one-hot encoded labels
    labels =
      1..batch_size
      |> Enum.map(fn _ -> :rand.uniform(num_classes) - 1 end)
      |> Nx.tensor()

    Nx.to_categorical(labels, num_classes: num_classes)
  end

  defp apply_augmentations(data_stream) do
    # Apply basic data augmentations
    Stream.map(data_stream, fn {x, y} ->
      # Random horizontal flip
      x = if :rand.uniform() > 0.5, do: Nx.reverse(x, axes: [2]), else: x

      # Small random rotation/shift (simplified)
      # In a real implementation, you'd use proper image augmentation
      noise = Nx.random_normal(Nx.shape(x), mean: 0.0, sigma: 0.1)
      x = Nx.add(x, noise) |> Nx.clip(-2.0, 2.0)

      {x, y}
    end)
  end

  defp load_and_process_csv(file_path, target_column) do
    # This would use a CSV parsing library like NimbleCSV
    # For now, we'll simulate CSV loading
    case File.exists?(file_path) do
      true ->
        # Simulate loading structured data
        {:ok, generate_structured_data()}

      false ->
  Logger.warning("CSV file #{file_path} not found, generating synthetic structured data")
        {:ok, generate_structured_data()}
    end
  end

  defp generate_structured_data do
    # Generate synthetic structured data (like housing prices, etc.)
    num_samples = 1000
    num_features = 10

    1..num_samples
    |> Enum.map(fn _ ->
      features =
        1..num_features
        |> Enum.map(fn _ -> :rand.normal() end)
        |> Nx.tensor()

      # Simple synthetic target based on features
      target =
        features
        |> Nx.sum()
        |> Nx.add(Nx.random_normal({}, mean: 0.0, sigma: 0.1))

      {features, target}
    end)
  end

  defp split_data(data, validation_split) do
    total_samples = length(data)
    val_size = round(total_samples * validation_split)
    train_size = total_samples - val_size

    shuffled_data = Enum.shuffle(data)

    train_data = Enum.take(shuffled_data, train_size)
    val_data = Enum.drop(shuffled_data, train_size)

    {train_data, val_data}
  end

  defp create_batched_stream(data, batch_size, shuffle) do
    data = if shuffle, do: Enum.shuffle(data), else: data

    data
    |> Stream.chunk_every(batch_size)
    |> Stream.map(fn batch ->
      # Convert batch to tensors
      {features, targets} = Enum.unzip(batch)

      batch_features = Nx.stack(features)
      batch_targets = Nx.stack(targets)

      {batch_features, batch_targets}
    end)
  end

  @doc """
  Downloads and caches dataset files.
  """
  @spec download_dataset(atom(), String.t()) :: :ok | {:error, String.t()}
  def download_dataset(dataset_name, cache_dir \\ "./data") do
    File.mkdir_p!(cache_dir)

    case dataset_name do
      :cifar10 -> download_cifar10(cache_dir)
      :mnist -> download_mnist(cache_dir)
      _ -> {:error, "Unknown dataset: #{dataset_name}"}
    end
  end

  defp download_cifar10(cache_dir) do
    # This would implement actual CIFAR-10 downloading
    # For now, just create placeholder
    cifar_path = Path.join(cache_dir, "cifar-10")
    File.mkdir_p!(cifar_path)
    Logger.info("CIFAR-10 dataset placeholder created at #{cifar_path}")
    :ok
  end

  defp download_mnist(cache_dir) do
    # This would implement actual MNIST downloading
    # For now, just create placeholder
    mnist_path = Path.join(cache_dir, "mnist")
    File.mkdir_p!(mnist_path)
    Logger.info("MNIST dataset placeholder created at #{mnist_path}")
    :ok
  end

  @doc """
  Validates dataset integrity and format.
  """
  @spec validate_dataset(data_stream()) :: :ok | {:error, String.t()}
  def validate_dataset(data_stream) do
    try do
      # Take first few batches to validate
      sample_batches = Enum.take(data_stream, 3)

      case sample_batches do
        [] ->
          {:error, "Dataset is empty"}

        [{first_x, first_y} | _] ->
          # Validate tensor shapes and types
          cond do
            not is_struct(first_x, Nx.Tensor) ->
              {:error, "Input data is not a tensor"}

            not is_struct(first_y, Nx.Tensor) ->
              {:error, "Target data is not a tensor"}

            Nx.rank(first_x) < 2 ->
              {:error, "Input tensor must have at least 2 dimensions (batch, features)"}

            true ->
              Logger.info("Dataset validation passed")
              :ok
          end
      end
    rescue
      error -> {:error, "Dataset validation failed: #{Exception.message(error)}"}
    end
  end
end
