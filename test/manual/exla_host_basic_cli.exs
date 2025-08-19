#!/usr/bin/env elixir

IO.puts("Testing EXLA host backend...")

# Set EXLA target
System.put_env("EXLA_TARGET", "host")

# Load dependencies
Code.require_file("mix.exs")

# Start the application
Application.ensure_all_started(:exla)
Application.ensure_all_started(:nx)

IO.puts("EXLA loaded?: #{Code.ensure_loaded?(EXLA.Backend)}")

# Test EXLA backend availability
try do
  # Set global backend
  if function_exported?(Nx, :global_default_backend, 1) do
    Nx.global_default_backend(EXLA.Backend)
    IO.puts("Set global backend to EXLA")
  else
    Nx.default_backend(EXLA.Backend)
    IO.puts("Set default backend to EXLA")
  end

  # Test basic operation
  result = Nx.iota({2, 3}) |> Nx.sum()
  IO.puts("Basic test result: #{inspect(result)}")

  # Test JIT compilation
  jit_fn = Nx.Defn.jit(fn -> Nx.iota({2, 3}) |> Nx.sum() end, compiler: EXLA)
  jit_result = jit_fn.()
  IO.puts("JIT test result: #{inspect(jit_result)}")

  IO.puts("✅ EXLA host backend working!")

rescue
  e ->
    IO.puts("❌ Error: #{inspect(e)}")
end