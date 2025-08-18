#!/bin/bash
# GPU Setup for Cerebros with EXLA

# Set CUDA environment
export CUDA_HOME=/opt/nvidia/hpc_sdk/Linux_x86_64/25.7/cuda
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:/usr/local/cuda/targets/x86_64-linux/lib:$LD_LIBRARY_PATH

# Set EXLA for GPU
export EXLA_TARGET=cuda

echo "🚀 GPU environment configured:"
echo "   CUDA: $(nvcc --version | grep 'release')"
echo "   CuDNN: 9.8.0"
echo "   EXLA_TARGET: $EXLA_TARGET"
echo "   GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader,nounits)"

# Ensure device files exist
if [[ ! -e /dev/nvidia0 ]]; then
    echo "🔧 Creating GPU device files..."
    sudo mknod /dev/nvidia0 c 195 0 2>/dev/null
    sudo mknod /dev/nvidiactl c 195 255 2>/dev/null
    sudo chmod 666 /dev/nvidia* 2>/dev/null
fi

echo "✅ Ready for GPU-accelerated Cerebros!"