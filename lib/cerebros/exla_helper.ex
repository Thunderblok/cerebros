defmodule Cerebros.ExlaHelper do
  @moduledoc """
  Helper for automatically setting up EXLA backend with GPU/CPU fallback.

  This module automatically detects if CUDA is available and working,
  and falls back to CPU-only EXLA if there are issues.
  """

  require Logger

  @doc """
  Sets up the best available EXLA backend (GPU or CPU fallback).

  Returns `:cuda` if GPU backend is working, `:host` if falling back to CPU.
  """
  def setup_best_backend do
    cond do
      gpu_available?() && cuda_backend_working?() ->
        setup_cuda_backend()

      true ->
        setup_host_backend()
    end
  end

  @doc """
  Checks if GPU devices are visible to the system.
  """
  def gpu_available? do
    case File.ls("/dev") do
      {:ok, files} ->
        Enum.any?(files, &String.starts_with?(&1, "nvidia"))

      _ ->
        false
    end
  end

  @doc """
  Tests if CUDA backend can actually compile and run.
  """
  def cuda_backend_working? do
    try do
      # Try to compile a simple function with EXLA
      test_fn = Nx.Defn.jit(fn -> Nx.tensor([1.0, 2.0, 3.0]) |> Nx.sum() end, compiler: EXLA)
      result = test_fn.()

      # If we get here, CUDA backend is working
      Logger.info("✅ CUDA backend test successful: #{inspect(result)}")
      true

    rescue
      e ->
        Logger.warning("❌ CUDA backend test failed: #{inspect(e)}")
        false
    end
  end

  @doc """
  Sets up CUDA backend (attempts GPU acceleration).
  """
  def setup_cuda_backend do
    Logger.info("🚀 Setting up CUDA backend for GPU acceleration")

    # Set environment for CUDA
    System.put_env("EXLA_TARGET", "cuda")
    System.delete_env("EXLA_CPU_ONLY")

    # Set EXLA as default backend
    if function_exported?(Nx, :global_default_backend, 1) do
      Nx.global_default_backend(EXLA.Backend)
    else
      Nx.default_backend(EXLA.Backend)
    end

    :cuda
  end

  @doc """
  Sets up host backend (CPU-only acceleration).
  """
  def setup_host_backend do
    Logger.info("🖥️  Setting up host backend for CPU acceleration")
  Logger.warning("GPU not available or CUDA backend failed - using CPU-only EXLA")

    # Set environment for CPU-only
    System.put_env("EXLA_TARGET", "host")
    System.put_env("EXLA_CPU_ONLY", "true")

    # Set EXLA as default backend
    if function_exported?(Nx, :global_default_backend, 1) do
      Nx.global_default_backend(EXLA.Backend)
    else
      Nx.default_backend(EXLA.Backend)
    end

    :host
  end

  @doc """
  Comprehensive diagnostics for EXLA and GPU status.
  """
  def diagnostics do
    IO.puts("🔍 EXLA & GPU Diagnostics")
    IO.puts("=" |> String.duplicate(50))

    # Environment variables
    exla_target = System.get_env("EXLA_TARGET", "not set")
    exla_cpu_only = System.get_env("EXLA_CPU_ONLY", "not set")

    IO.puts("Environment:")
    IO.puts("  EXLA_TARGET: #{exla_target}")
    IO.puts("  EXLA_CPU_ONLY: #{exla_cpu_only}")

    # NVIDIA driver status
    IO.puts("\nNVIDIA Status:")
    case System.cmd("nvidia-smi", [], stderr_to_stdout: true) do
      {output, 0} ->
        IO.puts("  ✅ nvidia-smi working")
        # Extract GPU name from output
        gpu_match = Regex.run(~r/NVIDIA GeForce (.+?)\s+/, output)
        if gpu_match, do: IO.puts("  GPU: #{Enum.at(gpu_match, 1)}")

      {error, _} ->
        IO.puts("  ❌ nvidia-smi failed: #{String.trim(error)}")
    end

    # Device files
    IO.puts("\nDevice Files:")
    gpu_available = gpu_available?()
    IO.puts("  /dev/nvidia* present: #{if gpu_available, do: "✅", else: "❌"}")

    if gpu_available do
      case File.ls("/dev") do
        {:ok, files} ->
          nvidia_files = Enum.filter(files, &String.starts_with?(&1, "nvidia"))
          IO.puts("  Files: #{Enum.join(nvidia_files, ", ")}")
        _ -> :ok
      end
    end

    # EXLA status
    IO.puts("\nEXLA Status:")
    exla_loaded = Code.ensure_loaded?(EXLA.Backend)
    IO.puts("  EXLA.Backend loaded: #{if exla_loaded, do: "✅", else: "❌"}")

    current_backend = Nx.default_backend()
    IO.puts("  Current Nx backend: #{inspect(current_backend)}")

    # Test compilation
    IO.puts("\nTest Results:")
    if exla_loaded do
      cuda_working = cuda_backend_working?()
      IO.puts("  CUDA backend test: #{if cuda_working, do: "✅", else: "❌"}")
    else
      IO.puts("  CUDA backend test: ❌ (EXLA not loaded)")
    end

    IO.puts("=" |> String.duplicate(50))
  end

  @doc """
  Quick test to verify the current backend is working.
  """
  def quick_test do
    try do
      # Simple tensor operation
      result = Nx.iota({3, 3}) |> Nx.sum()
      IO.puts("✅ Quick test passed: #{inspect(result)}")

      # JIT compilation test
      jit_fn = Nx.Defn.jit(fn x -> x |> Nx.multiply(2) |> Nx.sum() end, compiler: EXLA)
      jit_result = jit_fn.(Nx.iota({2, 2}))
      IO.puts("✅ JIT test passed: #{inspect(jit_result)}")

      true

    rescue
      e ->
        IO.puts("❌ Test failed: #{inspect(e)}")
        false
    end
  end
end
