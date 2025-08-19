System.put_env("EXLA_TARGET", "host")
Application.ensure_all_started(:exla)
Application.ensure_all_started(:nx)
Nx.global_default_backend(EXLA.Backend)

IO.puts("Testing EXLA JIT compilation...")

jit_fn = Nx.Defn.jit(fn x -> x |> Nx.add(1) |> Nx.multiply(2) |> Nx.sum() end, compiler: EXLA)
input = Nx.tensor([[1,2,3],[4,5,6]], type: :f32)
IO.inspect(jit_fn.(input), label: "JIT sum")

mat_fn = Nx.Defn.jit(fn x -> x |> Nx.transpose() |> Nx.dot(x) |> Nx.sum() end, compiler: EXLA)
mat = Nx.tensor([[1.0,2.0],[3.0,4.0],[5.0,6.0]])
IO.inspect(mat_fn.(mat), label: "Matrix op result")
