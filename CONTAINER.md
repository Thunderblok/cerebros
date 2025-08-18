# Cerebros Container Usage

This document explains how to build and run the Cerebros container image so it can be invoked by the Thunderline project or CI pipelines.

## 1. Build (CPU / host EXLA)
```bash
docker build -t cerebros:cpu .
```
This produces an image with EXLA compiled for the host (CPU) target.

## 2. Build (NVIDIA GPU / CUDA)
To build with CUDA you normally base on an NVIDIA CUDA image and install system libs. For simplicity we still build in Alpine here; for production GPU you should instead:
1. Use a Debian/Ubuntu based image that has a compatible GLIBC + CUDA toolkit or rely on `nvidia/cuda` base.
2. Set `EXLA_TARGET=cuda` at build time.

Example (still Alpine, but triggers CUDA compilation attempt if toolchain + headers are available in your environment):
```bash
docker build -t cerebros:cuda --build-arg EXLA_TARGET=cuda .
```
NOTE: For actual GPU execution you must run with the NVIDIA Container Toolkit:
```bash
docker run --rm --gpus all -e EXLA_TARGET=cuda cerebros:cuda eval "Cerebros.Perf.ensure_exla!()"
```
If drivers/toolkit aren't present, EXLA falls back or build fails.

## 3. Running the CLI
List commands (help):
```bash
docker run --rm cerebros:cpu --help
```
Run a small search:
```bash
docker run --rm -v "$PWD/results:/results" cerebros:cpu search --num-trials 3 --epochs 2 --output-dir /results
```
Analyze existing results:
```bash
docker run --rm -v "$PWD/results:/results" cerebros:cpu analyze --results-dir /results --format summary
```

## 4. Using as a Library via `start_iex`
Start an interactive shell inside the container (for ad-hoc experiments):
```bash
docker run -it --rm cerebros:cpu remote
```
(Where `remote` is the standard release command to connect; you can also run `eval "IO.inspect(Cerebros.hello())"`.)

## 5. Invoking From Thunderline
If Thunderline orchestrates containers:
- Provide an interface contract (JSON in /app/in, results in /app/out for example) and wrap the Cerebros CLI command accordingly.
- Or call release `eval` to execute an Elixir function directly:
  ```bash
  docker run --rm cerebros:cpu eval "Cerebros.test_full_nas_run(number_of_architectures_to_try: 2, number_of_trials_per_architecture: 1, epochs: 2)"
  ```
- For longer NAS jobs use `--name` and detach.

## 6. Example Thunderline Hook
Pseudo-command executed by Thunderline worker:
```bash
docker run --rm \
  -v /thunderline/jobs/job123:/workspace/results \
  cerebros:cpu search --num-trials 10 --epochs 5 --output-dir /workspace/results
```
Return code 0 indicates success; capture JSON files for downstream steps.

## 7. Environment Variables
| Variable | Purpose |
|----------|---------|
| EXLA_TARGET | host | cuda | rocm (target for JIT) |
| MIX_ENV | Should remain `prod` in container |
| LOG_LEVEL | (Optionally) override logger level |

## 8. Reducing Image Size
After validating, you can:
- Use `mix release --path /rel` and copy only `/rel`.
- `apk del build-base git` in builder *after* compile (already multi-stage). Runtime image is already slim.

## 9. Health / Sanity Check
```bash
docker run --rm cerebros:cpu eval "Cerebros.Perf.benchmark_matmul(size: 512, reps: 2) |> IO.inspect()"
```

## 10. Future Enhancements
- Add JSON command interface wrapper script inside image.
- Provide Prometheus metrics exporter mode.
- Supply GPU specific Dockerfile using `nvidia/cuda:12.4.1-runtime-ubuntu22.04` base.
- Harden with non-root user.

---
If you need a GPU-optimized variant, let me know and we can add a `Dockerfile.cuda` with Ubuntu base & proper CUDA libs.
