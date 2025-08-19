System.put_env("EXLA_TARGET", "host")

Mix.install([
  {:nx, "~> 0.10"},
  {:exla, "~> 0.10"},
  {:axon, "~> 0.7"}
])

Nx.global_default_backend(EXLA.Backend)
IO.puts("Backend: #{inspect(Nx.default_backend())}")

jit_fn = Nx.Defn.jit(fn x -> x |> Nx.multiply(2) |> Nx.sum() end, compiler: EXLA)
IO.inspect(jit_fn.(Nx.iota({3,3})), label: "JIT result")
