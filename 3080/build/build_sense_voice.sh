#!/bin/bash
set -e

echo "=== 编译 SenseVoice.cpp (语音转文字) ==="
echo "CUDA: /data/cuda | GPU: RTX 3080 (sm_86)"

export CUDA_HOME=/data/cuda
export PATH=$CUDA_HOME/bin:$PATH
export CC=/usr/bin/gcc-12
export CXX=/usr/bin/g++-12

SENSE_DIR=/opt/SenseVoice.cpp

if [ ! -d "$SENSE_DIR" ]; then
  echo "克隆 SenseVoice.cpp..."
  git clone --recursive https://github.com/lovemefan/SenseVoice.cpp.git "$SENSE_DIR"
fi

cd "$SENSE_DIR"

# 创建 build 目录
echo "创建 build 目录..."
rm -rf build
mkdir -p build
cd build

# CMake 配置 (CUDA + sm_86)
cmake -DCMAKE_BUILD_TYPE=Release \
      -DGGML_CUDA=ON \
      -DCMAKE_CUDA_COMPILER=/data/cuda/bin/nvcc \
      -DCMAKE_CUDA_ARCHITECTURES=86 \
      ..

# 编译
echo "开始编译..."
make -j$(nproc)

# 创建 bin 目录并复制
echo "复制二进制文件..."
mkdir -p ../bin
cp bin/sense-voice-* ../bin/ 2>/dev/null || true

echo "=== SenseVoice.cpp 编译完成 ==="
echo "二进制文件: $SENSE_DIR/bin/"
ls -la ../bin/ 2>/dev/null || echo "无匹配文件"
