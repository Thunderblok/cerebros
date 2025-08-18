System.put_env("EXLA_TARGET", "host")

# Load the Cerebros application context
Mix.install([
  {:nx, "~> 0.10"},
  {:exla, "~> 0.10"},
  {:axon, "~> 0.7"}
])

# Set EXLA as the default backend
Nx.global_default_backend(EXLA.Backend)

IO.puts("Current Nx backend: #{inspect(Nx.default_backend())}")

# Quick test of JIT compilation
jit_fn = Nx.Defn.jit(fn x -> 
  x
  |> Nx.multiply(2)
  |> Nx.sum()
end, compiler: EXLA)

test_tensor = Nx.iota({3, 3})
result = jit_fn.(test_tensor)

IO.puts("✅ EXLA JIT test successful!")
IO.puts("Input: #{inspect(test_tensor)}")
IO.puts("Result: #{inspect(result)}")

# Try to load Cerebros modules
try do
  Code.require_file("lib/cerebros.ex")
  IO.puts("✅ Cerebros module loaded")
  
  # Test if we can call a simple Cerebros function
  if function_exported?(Cerebros, :test_full_nas_run, 1) do
    IO.puts("✅ test_full_nas_run function available")
    IO.puts("Ready to run: Cerebros.test_full_nas_run(speed_mode: true, search_profile: :conservative)")
  else
    IO.puts("⚠️  test_full_nas_run function not found")
  end
rescue
  e -> 
    IO.puts("❌ Failed to load Cerebros: #{inspect(e)}")
end