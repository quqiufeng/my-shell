#!/bin/bash
set -euo pipefail

# stable-diffusion.cpp CUDA 编译脚本

echo "=========================================="
echo "stable-diffusion.cpp CUDA 编译脚本"
echo "=========================================="

export CC=/usr/bin/gcc-12
export CXX=/usr/bin/g++-12
export CUDA_HOME=/data/cuda
export PATH=$CUDA_HOME/bin:/data/venv/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}

NVCC_PATH=$CUDA_HOME/bin/nvcc
CUDA_VERSION=$($NVCC_PATH --version | grep "release" | awk '{print $5}' | cut -d',' -f1)
echo "检测到 CUDA: $CUDA_VERSION"
echo "NVCC 路径: $NVCC_PATH"

if [ ! -d "/opt/stable-diffusion.cpp" ]; then
    echo "错误: /opt/stable-diffusion.cpp 不存在"
    exit 1
fi

PROJECT_DIR=/opt/stable-diffusion.cpp
cd "$PROJECT_DIR"
# git pull (disabled to preserve local changes)

# 确保子模块完整
if [ ! -f "ggml/CMakeLists.txt" ]; then
    echo ""
    echo "=== 更新 git 子模块 ==="
    git submodule update --init --recursive
fi

# 清理 build 目录
echo ""
echo "=== 清理并配置 CMake ==="
rm -rf build
mkdir -p build && cd build

# GPU 检测
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
GPU_CC=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1 | tr -d '.')

echo "GPU: $GPU_NAME"
echo "Compute Capability: $GPU_CC"

# 根据 GPU 设置架构
case $GPU_CC in
    86) CUDA_ARCH=86 ;;
    89) CUDA_ARCH=89 ;;
    75) CUDA_ARCH=75 ;;
    80) CUDA_ARCH=80 ;;
    90) CUDA_ARCH=90 ;;
    120) CUDA_ARCH=120 ;;
    12) CUDA_ARCH=120 ;;
    *) CUDA_ARCH=86 ;;
esac

echo "使用 CUDA_ARCH: $CUDA_ARCH"

# CMake 配置
cmake .. \
    -DSD_CUDA=ON \
    -DSD_FLASH_ATTN=ON \
    -DSD_FAST_SOFTMAX=ON \
    -DGGML_NATIVE=OFF \
    -DGGML_LTO=ON \
    -DGGML_CUDA_FA_ALL_QUANTS=ON \
    -DCMAKE_CUDA_ARCHITECTURES=$CUDA_ARCH \
    -DCMAKE_CUDA_COMPILER="$CUDA_HOME/bin/nvcc" \
    -DCMAKE_BUILD_TYPE=Release

# 编译
echo ""
echo "=== 编译中 (使用 4 线程) ==="
make -j$(nproc)

# 移动 bin 目录
cd "$PROJECT_DIR"
if [ -f "build/bin/sd-cli" ]; then
    echo ""
    echo "=== 整理文件 ==="
    rm -rf bin
    mv build/bin bin
    # rm -rf build   # 保留 build 目录供 my-img 链接
    
    echo ""
    echo "=========================================="
    echo "✅ 编译成功！"
    echo "=========================================="
    echo "可执行文件: $PROJECT_DIR/bin/sd-cli"
    echo "API 服务:   $PROJECT_DIR/bin/sd-server"
else
    echo ""
    echo "❌ 编译失败"
    exit 1
fi
