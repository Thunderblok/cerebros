#!/usr/bin/env bash
set -euo pipefail

# Rebuild EXLA with CUDA target after ensuring NCCL and friends are present.
# This script is idempotent and safe to re-run.

REQ_LIBS=(libcudart.so libnccl.so libcublas.so)

color() { printf "\033[%sm%s\033[0m" "$1" "$2"; }
info() { echo "$(color 36 '[INFO]') $*"; }
warn() { echo "$(color 33 '[WARN]') $*"; }
err()  { echo "$(color 31 '[ERR ]') $*"; }

if [ "${EXLA_TARGET:-}" != "cuda" ]; then
  info "Setting EXLA_TARGET=cuda for this rebuild session" && export EXLA_TARGET=cuda
fi

if ! command -v ldconfig >/dev/null 2>&1; then
  warn "ldconfig not found; skipping shared library lookup."
else
  MISSING=()
  for lib in "${REQ_LIBS[@]}"; do
    if ldconfig -p | grep -q "$lib"; then
      info "Found $lib"
    else
      warn "$lib missing from linker cache"
      MISSING+=("$lib")
    fi
  done
  if (( ${#MISSING[@]} > 0 )); then
    warn "Missing critical CUDA libs: ${MISSING[*]}"
    warn "If they exist under /usr/local/cuda/lib64 but not in cache, run: sudo ldconfig"
    warn "Otherwise install/copy them before rebuilding or EXLA NIF may fail to load."
  fi
fi

info "Cleaning previous EXLA build artifacts"
mix deps.clean exla --unlock || true

info "Fetching deps (if needed)"
mix deps.get

info "Compiling EXLA with CUDA"
if ! mix deps.compile exla; then
  err "mix deps.compile exla failed"
  exit 1
fi

info "Compiling project"
if ! mix compile; then
  err "mix compile failed"
  exit 1
fi

cat <<'EOF'
============================================================
Rebuild finished. To verify inside IEx:
  iex -S mix
  Nx.default_backend(EXLA.Backend)
  Cerebros.gpu_diagnostics()
If the NIF still fails with libnccl.so.2 missing:
  1. Confirm the file exists: ls -l /usr/local/cuda/lib64/libnccl.so*
  2. If you only have e.g. libnccl.so.3 create a symlink cautiously:
       sudo ln -s /usr/local/cuda/lib64/libnccl.so.3 /usr/local/cuda/lib64/libnccl.so.2
     (Only do this if versions are compatible; prefer installing matching NCCL.)
  3. sudo ldconfig
  4. Re-run this script.
============================================================
EOF
