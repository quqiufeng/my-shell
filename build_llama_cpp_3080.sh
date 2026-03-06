#!/bin/bash

# llama.cpp CUDA 编译脚本
# 支持自动检测 GPU 架构

echo "=========================================="
echo "llama.cpp CUDA 编译脚本"
echo "=========================================="

# 检查 CUDA
if ! command -v nvcc &> /dev/null; then
    echo "错误: 未找到 nvcc，请先安装 CUDA Toolkit"
    exit 1
fi

echo "检测到 CUDA:"
nvcc --version | grep "release"

# 设置 CUDA 环境变量（兼容 WSL2）
export CUDA_HOME=/usr/local/cuda-12.0
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:/usr/lib/wsl/lib:$LD_LIBRARY_PATH

# 克隆或更新 llama.cpp
if [ ! -d "$HOME/llama.cpp" ]; then
    echo ""
    echo "=== 克隆 llama.cpp ==="
    git clone --depth 1 https://github.com/ggerganov/llama.cpp.git $HOME/llama.cpp
fi

cd $HOME/llama.cpp

# 清理并配置
echo ""
echo "=== 配置 CMake ==="
mkdir -p build && cd build
rm -rf *

# 检测 GPU 架构
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
GPU_CC=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1 | tr -d '.')

echo "GPU: $GPU_NAME"
echo "Compute Capability: $GPU_CC"

# 根据 GPU 设置架构
case $GPU_CC in
    86) CUDA_ARCH=86 ;;   # RTX 3080/3090, RTX 30xx
    89) CUDA_ARCH=89 ;;   # RTX 4090/4090D, RTX 40xx
    75) CUDA_ARCH=75 ;;   # RTX 20xx
    80) CUDA_ARCH=80 ;;   # A100
    90) CUDA_ARCH=90 ;;   # H100
    12) CUDA_ARCH=120 ;;  # GB200, B100/B200
    *) CUDA_ARCH=86 ;;    # 默认 RTX 30xx
esac

echo "使用 CUDA_ARCH: $CUDA_ARCH"

cmake .. -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=$CUDA_ARCH

# 编译
echo ""
echo "=== 编译中 (使用 6 线程) ==="
make -j6

# 检查是否成功
if [ -f "$HOME/llama.cpp/build/bin/llama-cli" ]; then
    echo ""
    echo "=========================================="
    echo "✅ 编译成功！"
    echo "=========================================="
    echo "可执行文件: $HOME/llama.cpp/build/bin/llama-cli"
    echo "API 服务:   $HOME/llama.cpp/build/bin/llama-server"
    
    # 测试 GPU
    echo ""
    echo "=== 测试 GPU 支持 ==="
    $HOME/llama.cpp/build/bin/llama-cli --verbose -m /dev/null -n 1 2>&1 | grep -i cuda
else
    echo ""
    echo "❌ 编译失败"
    exit 1
fi
