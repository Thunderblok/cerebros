Manual / exploratory scripts
=============================

These scripts are NOT part of the automated ExUnit suite; they're convenience / smoke tests you can run with `elixir path/to/script.exs` or `mix run`.

Files:
- `exla_host_basic.exs` – minimal EXLA host backend sanity (load, JIT, sum)
- `exla_jit_demo.exs` – matrix + JIT examples (was quick_demo.exs)
- `cerebros_module_load.exs` – loads `Cerebros` and reports availability of NAS entrypoint
- `exla_fallback_diagnostics.exs` – multi-step diagnostic using `Cerebros.ExlaHelper`
- `exla_cpu_only.exs` – forces CPU-only path via `EXLA_CPU_ONLY`
- `exla_presence_check.exs` – checks that the shared library exists

Guidelines:
1. Set environment vars BEFORE running (e.g. `EXLA_TARGET=cuda` for GPU).
2. Keep them deterministic / fast; prefer tiny tensors.
3. For anything assertable, consider porting a version into proper ExUnit tests.

Not executed automatically by `mix test` unless you deliberately `require` them.

Run examples:
```bash
elixir test/manual/exla_host_basic.exs
EXLA_TARGET=host elixir test/manual/cerebros_module_load.exs
```
