#!/usr/bin/env bash
set -euo pipefail

# Simple helper to force EXLA/Nx into CPU (host) mode and rebuild if needed.
# Use this if CUDA/NCCL libs are missing and libnccl errors occur.

export XLA_TARGET=cpu
export EXLA_TARGET=host
export NX_DEFAULT_BACKEND=EXLA.Backend

# Clean existing exla build if present
if [ -d _build/dev/lib/exla ]; then
  echo "[setup_cpu_mode] Cleaning existing EXLA build..."
  mix deps.clean exla --build >/dev/null 2>&1 || true
  rm -rf _build/dev/lib/exla
fi

echo "[setup_cpu_mode] Compiling deps (CPU mode)..."
mix deps.get >/dev/null
mix compile

echo "[setup_cpu_mode] Done. Start IEx with: iex -S mix"
echo "Environment variables (current shell):"
echo "  XLA_TARGET=$XLA_TARGET"
echo "  EXLA_TARGET=$EXLA_TARGET"
echo "  NX_DEFAULT_BACKEND=$NX_DEFAULT_BACKEND"
