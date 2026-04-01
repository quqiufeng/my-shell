#!/bin/bash
set -e

echo "=== 编译 SenseVoice.cpp (语音转文字) ==="

cd /opt

# 克隆源码
if [ ! -d "SenseVoice.cpp" ]; then
  echo "克隆 SenseVoice.cpp 源码..."
  git clone --recursive https://github.com/lovemefan/SenseVoice.cpp.git
  cd SenseVoice.cpp
  git submodule sync && git submodule update --init --recursive
else
  echo "更新源码..."
  cd SenseVoice.cpp
  git pull
  git submodule sync && git submodule update --init --recursive
fi

# 创建 build 目录
echo "创建 build 目录..."
rm -rf build
mkdir -p build
cd build

# CMake 配置 (支持 CUDA)
cmake -DCMAKE_BUILD_TYPE=Release \
      -DGGML_CUDA=ON \
      -DCMAKE_CUDA_COMPILER=/opt/cuda/bin/nvcc \
      ..

# 编译
echo "开始编译..."
make -j$(nproc)

# 创建 bin 目录并复制
echo "复制二进制文件..."
mkdir -p ../bin
cp bin/sense-voice-* ../bin/

echo "=== SenseVoice.cpp 编译完成 ==="
echo "二进制文件: /opt/SenseVoice.cpp/bin/"
ls -la ../bin/
