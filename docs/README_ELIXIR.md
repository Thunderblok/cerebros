# Cerebros (Elixir / Axon Port)

An experimental Elixir + Axon implementation of the Cerebros neural architecture search (NAS) core. This port focuses on:

- Dynamic neural architecture specification & random generation
- Connectivity graph construction (skip/lateral/gated connections)
- Trial orchestration with concurrent GenServer workers
- Training & evaluation loops using Axon.Loop (Nx 0.9 / Axon 0.7 API)
- Result collection, hashing, and summary statistics

> Status: alpha – functional end‑to‑end small NAS runs succeed; APIs may change.

## Quick Start

Prerequisites:
- Elixir >= 1.15 (tested with 1.18.4)
- Erlang/OTP 26
- (Optional) CUDA toolchain if you plan to enable EXLA GPU backend

Install deps:
```
mix deps.get
```

Run a minimal NAS demo (2 architectures x 1 trial, 2 epochs):
```
iex -S mix
iex> Cerebros.test_full_nas_run(input_shapes: [{10}], output_shapes: [{1}], number_of_architectures_to_try: 2, number_of_trials_per_architecture: 1, epochs: 2)
```

Expected output: trial workers start, training batches log, a results summary prints with validation losses (mean_squared_error proxy) and improvement stat.

## Project Structure
```
lib/
  cerebros.ex                # Public entry points & demo helpers
  cerebros/architecture/     # Spec struct & random generation
  cerebros/connectivity/     # DAG construction & validation
  cerebros/networks/         # Axon model builder & compilation helpers
  cerebros/training/         # Orchestrator & trial worker processes
  cerebros/data/             # Synthetic & (placeholder) dataset loaders
  cerebros/results/          # Result persistence & analysis utilities
```

## Key Concepts
- Spec hashing excludes anonymous function fields (deterministic canonical hashing with term_to_binary).
- Metrics: mean_squared_error wrapped via Axon.Losses; validation_loss persisted per trial.
- Training loop: Axon.Loop.trainer + validation + early stopping hooks (patience configurable).

## Running Tests
```
mix test
```
(Current test suite is minimal; add ExUnit cases for connectivity & builder logic.)

## Adding a GPU Backend
Set environment variables before starting IEx:
```
export XLA_TARGET=cuda
export NVIDIA_VISIBLE_DEVICES=all
iex -S mix
```
(Ensure CUDA toolkit & compatible drivers installed.)

## Roadmap / Next Steps
- Expand ExUnit coverage (connectivity edge cases, builder shape invariants, early stopping correctness)
- Introduce configurable search strategies (random, evolutionary, Bayesian)
- Persist & reload trial states (resume NAS)
- Integrate telemetry & tracing hooks
- Provide JSON/GraphQL API wrapper (Phoenix + Absinthe) for remote orchestration

## License
Inherit the parent repository license (see `license.md`).

## Attribution
Original Python Cerebros design concepts by the upstream project. This Elixir/Axon port re-imagines the orchestration & execution model using OTP primitives.
