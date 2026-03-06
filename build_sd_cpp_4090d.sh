#!/bin/bash
set -e

echo "=== 清理旧的 build 目录 ==="
rm -rf /opt/stable-diffusion.cpp/build

echo "=== 更新源码 ==="
cd /opt/stable-diffusion.cpp
git pull origin master
git submodule update --init --recursive

echo "=== 创建 build 目录并配置 ==="
mkdir -p build
cd build
cmake .. -DSD_CUDA=ON \
         -DSD_CUBLAS=ON \
         -DSD_FLASH_ATTN=ON \
         -DSD_FAST_SOFTMAX=ON \
         -DGGML_NATIVE=ON \
         -DGGML_LTO=ON \
         -DGGML_CUDA_FA_ALL_QUANTS=ON \
         -DCMAKE_CUDA_ARCHITECTURES="89;90" \
         -DCMAKE_CUDA_COMPILER=/opt/cuda/bin/nvcc \
         -DCMAKE_BUILD_TYPE=Release

echo "=== 开始编译 ==="
make -j$(nproc)

echo "=== 复制二进制文件到 bin 目录 ==="
mkdir -p /opt/stable-diffusion.cpp/bin
cp -r bin/* /opt/stable-diffusion.cpp/bin/

echo "完成! 二进制文件在 /opt/stable-diffusion.cpp/bin/"
