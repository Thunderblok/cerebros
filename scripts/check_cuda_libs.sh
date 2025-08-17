#!/usr/bin/env bash
set -euo pipefail

REQ_LIBS=(libcudart.so libnccl.so libcublas.so libcudnn.so)

echo "[cerebros] CUDA library presence check"
if ! command -v ldconfig >/dev/null 2>&1; then
  echo "ldconfig not found; cannot query linker cache."
  exit 0
fi

MISSING=()
for lib in "${REQ_LIBS[@]}"; do
  if ldconfig -p | grep -q "$lib"; then
    echo "✓ $lib"
  else
    echo "✗ $lib (missing)"
    MISSING+=("$lib")
  fi
done

if [ ${#MISSING[@]} -eq 0 ]; then
  echo "All required CUDA libs found in linker cache."
  exit 0
fi

echo
echo "Missing libs: ${MISSING[*]}"
echo "Suggested actions (Fedora WSL):"
cat <<'EOF'
1. Ensure NVIDIA driver + WSL GPU passthrough works (check /dev/nvidia0).
2. Install runtime packages (example; adjust versions as available):
   sudo dnf search nccl | grep -i nccl
   sudo dnf install -y nccl nccl-devel
   sudo dnf search cudnn | grep -i cudnn || echo 'cuDNN package may require manual download'
3. If cuDNN / NCCL not packaged, download tarballs from NVIDIA and copy:
   sudo cp -P lib*/libcudnn* /usr/local/cuda/lib64/
   sudo cp -P lib*/libnccl* /usr/local/cuda/lib64/
   sudo ldconfig
4. Rebuild EXLA after libs exist:
   export EXLA_TARGET=cuda
   mix deps.clean exla --unlock && mix deps.compile exla
EOF
