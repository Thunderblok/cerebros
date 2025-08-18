# Cerebros Python Reference Run

This directory will hold a minimal Python reference implementation / runner so we can:

1. Reproduce original Cerebros (Python) style NAS loop
2. Capture timing + parameter counting behavior for comparison with current Elixir port
3. Produce JSON line (NDJSON) progress records so we can diff semantics cleanly

## Planned Components

- `cerebros_ref/` package with:
  - `spec.py` (architecture spec + random generation)
  - `model_builder.py` (translate spec -> torch.nn.Module)
  - `search.py` (random search loop + training + metrics)
  - `data.py` (synthetic regression dataset similar to Elixir synthetic generator)
  - `util.py` (parameter counting, timing, hashing)
- `run_search.py` CLI producing NDJSON progress + final summary JSON

We keep it intentionally small and dependency-light (torch + numpy only). If torch isn't installed we'll instruct installing CPU version.

## Quick Start (will be updated after files added)

```bash
python -m venv .venv
source .venv/bin/activate
pip install torch numpy
python run_search.py --trials 4 --epochs 3 --input-dim 10 --output-dim 1
```

Progress lines will be emitted as NDJSON to stdout; final summary goes to stderr (or a file via --out-dir).

---
(Implementation scaffold to follow.)
