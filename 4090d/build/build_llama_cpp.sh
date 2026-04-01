#!/bin/bash
set -e

cd /opt/llama.cpp

echo "=== 清理旧的 build 目录 ==="
rm -rf build

echo "=== 创建 build 目录并配置 ==="
mkdir -p build
cd build
cmake .. -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=89 -DCMAKE_CUDA_COMPILER=/opt/cuda/bin/nvcc

echo "=== 开始编译 ==="
make -j$(nproc)

echo "=== 复制二进制文件到 /opt/llama.cpp/bin ==="
mkdir -p ../bin
cp -r bin/* ../bin/

echo "=== 清理 build 目录 ==="
cd ..
rm -rf build

echo "完成! 二进制文件在 /opt/llama.cpp/bin/"
