# Thunderline Integration Plan

This document tracks alignment and integration work between the **Cerebros** NAS engine and the **Thunderline** platform.

## 1. Current Snapshot
- Thunderline vendor copy cloned at: `vendor/thunderline/`
- Thunderline version: see `vendor/thunderline/mix.exs` (`@version "2.0.0"`).
- Cerebros version: `0.1.0` (local, unreleased on Hex).
- Both projects depend on: `nx ~> 0.9`, `axon ~> 0.7`, `exla ~> 0.9`, `polaris ~> 0.1`.
  - Lock files show resolution up to Nx 0.10.0 in Cerebros (acceptable under `~> 0.9`).
- Thunderline currently contains an **internal lightweight NAS stub** under `lib/thunderline/ml/cerebros/` (`SimpleSearch`, `Adapter`, `Artifacts`, `Telemetry`).
- Adapter logic defers to internal implementation even when external Cerebros is available (placeholder for future delegation).

## 2. Integration Modes
| Mode | Description | Pros | Cons |
|------|-------------|------|------|
| A. In-Process Dependency | Thunderline depends on Cerebros as a Hex library and calls modules directly | Low latency; rich API | Tight coupling; upgrade risk |
| B. External Service (Container) | Thunderline shells out (CLI) or calls HTTP microservice wrapping Cerebros | Isolation; version pinning | Serialization overhead; more ops |
| C. Hybrid Adapter | Attempt in-process first; fallback to external container via CLI | Resilience; incremental adoption | More code paths |
| D. RPC / Distributed Erlang | Thunderline connects to a long-running Cerebros node | Fast; can stream telemetry | Needs cluster auth & node mgmt |

Initial recommendation: **Mode C (Hybrid)** to allow rapid migration without blocking on packaging & release.

## 3. Unified API Contract (Proposed)
Define a minimal search contract independent of transport:
```elixir
@type search_spec :: %{
  input_shapes: [tuple()],
  output_shapes: [tuple()],
  trials: pos_integer(),
  epochs: pos_integer(),
  batch_size: pos_integer(),
  learning_rate: float(),
  seed: non_neg_integer() | nil
}

@type search_result :: %{
  best_metric: float(),
  best_trial: map(),
  trials: non_neg_integer(),
  artifact_path: String.t(),
  metrics_summary: map()
}
```
Transport-level payload (JSON) for CLI / service:
```json
{
  "action": "run_search",
  "spec": { "input_shapes": [[10]], "output_shapes": [[1]], "trials": 5, "epochs": 3, "batch_size": 32, "learning_rate": 0.001 }
}
```
Response:
```json
{
  "status": "ok",
  "result": {
    "best_metric": 0.5231,
    "trials": 5,
    "artifact_path": "/results/2025-08-18/trial_3_best.json",
    "best_trial": { "id": 3, "params": 18240, "metric": 0.5231 },
    "metrics_summary": { "median": 0.54 }
  }
}
```

## 4. Adapter Evolution Roadmap
| Phase | Goal | Thunderline Changes | Cerebros Changes |
|-------|------|----------------------|------------------|
| P1 | Vendor snapshot + doc (DONE) | None | Add integration doc + update script |
| P2 | CLI Delegation | Modify `Adapter` to shell out to release/CLI if `Cerebros.Application` not loaded | Ensure stable CLI JSON mode |
| P3 | Direct Library Delegation | If `Code.ensure_loaded?(Cerebros)` true, call `Cerebros.search/1` (to implement) | Implement `Cerebros.search/1` returning unified `search_result` |
| P4 | Streaming Telemetry | Adapter attaches Telemetry handlers mapping Cerebros events to Thunderline UI | Emit richer telemetry events with stable shape |
| P5 | Service Mode (Optional) | HTTP/GRPC wrapper for remote deployment | Thin Plug / Bandit service wrapper |

## 5. Immediate Action Items
1. (Cerebros) Provide `Cerebros.Adapter` or `Cerebros.API` module with `run_search(opts)` returning unified result.
2. (Cerebros) Add CLI JSON command: `cerebros json --file /in/spec.json --out /out/result.json` (or stdin/stdout streaming).
3. (Thunderline) Update `Thunderline.ML.Cerebros.Adapter.run_search/1` to:
   - TRY direct: `function_exported?(Cerebros, :run_search, 1)` then call.
   - ELSE look for env `CEREBROS_CLI` (default `cerebros`) and run: `System.cmd(cerebros_cli, ["json", "--spec", json])`.
   - ELSE fallback to internal `SimpleSearch` (mark deprecated).
4. Provide container label + version endpoint for introspection (`eval "IO.puts(Cerebros.version())"`).

## 6. Version & Dependency Alignment
- Keep Nx / Axon versions consistent. If Thunderline updates to Nx 0.11+ ensure Cerebros `mix.exs` loosens constraint (`~> 0.11`) before upgrading there.
- Telemetry: unify event names under a shared prefix, e.g. `[:cerebros, :trial, :completed]`, `[:cerebros, :search, :progress]`.

## 7. Suggested Telemetry Mapping
| Event | Measurements | Metadata | Thunderline Usage |
|-------|--------------|----------|-------------------|
| [:cerebros, :search, :progress] | %{completed: n, total: t, best_metric: f} | %{run_id: id} | Live progress bar |
| [:cerebros, :trial, :completed] | %{metric: f, duration_ms: i, params: i} | %{trial_id: id, run_id: id} | Trial table update |
| [:cerebros, :perf, :gpu] | %{gpu_util: i, mem_util: i} | %{device: idx} | Perf dashboard |

## 8. Container Invocation Patterns
Short run:
```bash
docker run --rm -v "$PWD/specs:/specs" cerebros:cpu eval 'Cerebros.CLI.json_run("/specs/search_1.json", "/specs/result_1.json")'
```
(Will add `json_run/2` helper in P2.)

## 9. Update Script
A helper script `scripts/update_thunderline.sh` keeps vendor copy current (added with this plan).

## 10. Open Questions
- Persistence: Should artifacts be pushed to object storage (S3/MinIO) instead of local path? (Recommend phased: local → pluggable store.)
- Authentication: If service mode, do we need request signing or rely on internal network trust? (Likely internal first.)
- Multi-tenancy: Add `run_id` / `tenant` tags early for isolation.

## 11. Next Steps (Recommended Order)
1. Implement `Cerebros.API.run_search/1` (unified return shape). ✅ THEN commit.
2. Add JSON CLI mode + container test.
3. Patch Thunderline adapter (PR) to delegate.
4. Add Telemetry bridging & UI updates inside Thunderline.
5. Evaluate service mode only if remote scaling required.

---
Feel free to annotate this file as integration evolves.
