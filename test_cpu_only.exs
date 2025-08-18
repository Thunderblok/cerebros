System.put_env("EXLA_TARGET", "host")
System.put_env("EXLA_CPU_ONLY", "true")

# Load dependencies
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

IO.puts("✅ EXLA CPU-only JIT test successful!")
IO.puts("Input: #{inspect(test_tensor)}")
IO.puts("Result: #{inspect(result)}")