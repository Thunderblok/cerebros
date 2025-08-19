System.put_env("EXLA_TARGET", "host")

Mix.install([
  {:nx, "~> 0.10"},
  {:exla, "~> 0.10"},
  {:axon, "~> 0.7"}
])

Nx.global_default_backend(EXLA.Backend)
IO.puts("Backend: #{inspect(Nx.default_backend())}")

Code.require_file("lib/cerebros.ex")
IO.puts("Loaded Cerebros: #{function_exported?(Cerebros, :hello, 0)}")

if function_exported?(Cerebros, :test_full_nas_run, 1) do
  IO.puts("NAS entrypoint available. You can run: Cerebros.test_full_nas_run(speed_mode: true, search_profile: :conservative)")
else
  IO.puts("NAS entrypoint missing (unexpected)")
end
