## Cerebros Elixir Port – Guide for the Python Team

This document orients Python-side contributors so you can evaluate, run, and compare the Elixir/Axon port against the original Python Cerebros codebase.

### 1. TL;DR Run (CPU Only – No CUDA Needed)

Requirements:
- Elixir >= 1.15 (recommend 1.16+)
- Erlang/OTP 26
- Git + build-essential tools

Clone & install deps:
```
git clone git@github.com:Thunderblok/cerebros.git
cd cerebros
mix deps.get
```

Force CPU EXLA build (safe if GPU/NCCL missing):
```
./scripts/setup_cpu_mode.sh
```

Start IEx & run a tiny NAS sample:
```
iex -S mix
iex> Cerebros.test_full_nas_run(number_of_architectures_to_try: 2, number_of_trials_per_architecture: 1, epochs: 2)
```

You should see trial logs and a summary with validation losses.

### 2. Python → Elixir Concept Mapping

| Python Concept | Elixir Module/Concept | Notes / Status |
|----------------|-----------------------|----------------|
| `SimpleCerebrosRandomSearch` | `Cerebros.Training.Orchestrator` + wrapper functions in `Cerebros` | Core orchestration + concurrency. Ranking helper planned. |
| Architecture “moiety” (sample reused over trials) | Spec (`Cerebros.Architecture.Spec`) + repeated trials | Distinct moiety abstraction not yet separated (planned). |
| `DenseAutoMlStructuralComponent` (skip affinity factors + decay + rounding) | `connectivity_config` map passed into builder | Rounding rule options & dual decay separation pending (Priority 1). |
| `DenseLateralConnectivity` | Same `connectivity_config` (lateral fields) | Probabilistic per-distance lateral + gating not yet implemented (Priority 2). |
| Units / Input / Final | Implicit unit maps inside spec levels | Simplified – final layer flagged; real neuron features deferred. |
| Decay helpers (`zero_7_exp_decay`, etc.) | Anonymous functions stored in config | We can add canonical helpers if needed for parity. |
| Gating after N lateral connections | (planned) gating metadata in connectivity | Not yet implemented (Priority 2). |
| Ranking direction & metric | To-be `Cerebros.Search.rank/3` | Will support metric & :min/:max (Priority 1). |
| Persistence directories | (planned) optional `output_dir` | Not implemented – deferred for lean iteration. |
| Graph visualization | (planned) adjacency / DOT export | Not implemented. |
| Early stopping | Basic training loop only | Hook planned with patience (Priority 5). |

### 3. Current Feature Status Snapshot

Implemented:
- Random spec generation with min/max constraints.
- Deterministic connectivity (skip + simple lateral placeholder probability gate).
- Concurrency: multiple architectures × trials.
- Metric: validation MSE (basic reporting).
- Result collection + spec hashing (deterministic across runs for same seed).

Pending (Prioritized):
1. Rounding rules, ranking helper (Priority 1)
2. Probabilistic lateral selection + gating state machine (Priority 2)
3. Explicit moiety separation + per-architecture trial ranking (Priority 3)
4. Optional persistence output_dir (JSON spec/connectivity + metrics) (Priority 4)
5. Metric expansion (MAE, R²) + early stopping (Priority 5)
6. Graph export + gating stats (Priority 6)

### 4. Reproducibility Contract

Given a tuple `{arch_index, trial_index, base_seed}` we derive deterministic random seeds for:
- Spec generation
- Connectivity
- Weight initialization

Spec hashes (via `:erlang.term_to_binary` with filtered transient fields) should remain stable unless we change struct layout.

### 5. How To Review Parity
1. Run a small search both in Python and Elixir with the same (mirrored) config values (layers, units per layer bounds, etc.).
2. Compare distribution of produced specs (#levels, total params) – not exact equality yet because lateral & gating semantics differ.
3. After rounding + ranking helper lands, validate architecture ordering by validation loss vs Python’s ranking direction semantics.
4. Once lateral gating is implemented, re-run to check skip/lateral edge count distributions.

### 6. Adding a New Parity Test (Suggestion)
Create an ExUnit test enumerating N specs with a fixed seed and asserting:
- All non-input units have at least one predecessor (connectivity invariant).
- Spec hash list is identical across two runs (determinism).

### 7. Windows / WSL Notes
- CPU mode works natively (install Elixir via asdf or official installer).
- GPU mode under native Windows would need the EXLA precompiled Windows GPU path (limited support) or run under WSL2 Ubuntu (better). Fedora WSL path currently needs manual NCCL install (deferred here).

### 8. Contributing Changes (Python Team)
If you need a Python feature mirrored:
1. Open an issue describing Python field → desired Elixir config key.
2. Provide a minimal Python run snippet with the parameter values used.
3. We add config + deterministic mapping tests, then adapt builder/orchestrator.

### 9. Planned Public API Stabilization Points
- `Cerebros.test_full_nas_run/1` kept as high-level smoke test API.
- Future: `Cerebros.search/1` returning a structured result with ranked trials and metadata.

### 10. Questions / Feedback
Open a GitHub issue with the label `python-parity` for anything blocking cross‑team validation.

---
This doc tracks parity progress; expect updates as priorities are implemented.
