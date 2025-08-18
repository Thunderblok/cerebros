# Quick demonstration of EXLA working with auto-fallback
System.put_env("EXLA_TARGET", "host")

# Test basic EXLA functionality
Application.ensure_all_started(:exla)
Application.ensure_all_started(:nx)

# Set EXLA backend
Nx.global_default_backend(EXLA.Backend)

# Test JIT compilation 
IO.puts("Testing EXLA JIT compilation...")

jit_fn = Nx.Defn.jit(fn x -> 
  x 
  |> Nx.add(1) 
  |> Nx.multiply(2) 
  |> Nx.sum()
end, compiler: EXLA)

test_input = Nx.tensor([[1, 2, 3], [4, 5, 6]], type: :f32)
result = jit_fn.(test_input)

IO.puts("✅ JIT test successful!")
IO.puts("Input: #{inspect(test_input)}")
IO.puts("Result: #{inspect(result)}")
IO.puts("Backend: #{inspect(Nx.default_backend())}")

# Test a slightly more complex computation
IO.puts("\nTesting matrix operations...")

mat_fn = Nx.Defn.jit(fn x -> 
  x
  |> Nx.transpose()
  |> Nx.dot(x)
  |> Nx.sum()
end, compiler: EXLA)

matrix = Nx.tensor([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]], type: :f32)
matrix_result = mat_fn.(matrix)

IO.puts("✅ Matrix operations successful!")
IO.puts("Matrix: #{inspect(matrix)}")
IO.puts("Result: #{inspect(matrix_result)}")

IO.puts("\n🎉 EXLA is working with JIT acceleration!")