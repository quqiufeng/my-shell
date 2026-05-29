#!/bin/bash
set -e
#
# 【编译优化选项】
#   NVCCFLAGS=-arch=sm_86    仅编译 RTX 3080 架构，避免生成多余 PTX
#   NVCCFLAGS+=-O3           显式开启 CUDA O3 优化
#   NVCCFLAGS+=-use_fast_math 快速数学函数（Makefile 已有，显式保险）
#   LDFLAGS=-flto            链接时优化
#

echo "=== 编译 koboldcpp (CUDA 版本 for RTX 3080) ==="
echo ""

export CC=/usr/bin/gcc-12
export CXX=/usr/bin/g++-12

if [ ! -d "/opt/koboldcpp" ]; then
    echo "错误: /opt/koboldcpp 不存在, 请先克隆"
    exit 1
fi

cd /opt/koboldcpp
git pull

echo "=== 清理旧的编译文件 ==="
make clean 2>/dev/null || true
rm -f *.so *.o

echo ""
echo "=== 开始编译 (CUDA/cuBLAS for RTX 3080) ==="
echo "架构: CUDA 8.6 (RTX 3080)"
echo "NVCCFLAGS: -arch=sm_86 -O3 -use_fast_math"
echo "CUDA: /data/cuda"
echo "这可能需要 10-20 分钟..."
echo ""

export CUDA_HOME=/data/cuda
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64
export NVCCFLAGS="-arch=sm_86 -O3 -use_fast_math -extended-lambda --forward-unknown-to-host-compiler"
export LDFLAGS="-flto"

make -j$(nproc) LLAMA_CUBLAS=1 koboldcpp_cublas

echo ""
echo "=== 编译完成 ==="
echo ""

if [ -f "koboldcpp_cublas.so" ]; then
    echo "✓ koboldcpp_cublas.so 生成成功 (CUDA 版本)"
    ls -lh koboldcpp_cublas.so
    echo ""
    echo "文件大小:"
    du -h koboldcpp_cublas.so
else
    echo "✗ 编译失败，未找到 koboldcpp_cublas.so"
    exit 1
fi

echo ""
echo "使用方法:"
echo "  cd /opt/koboldcpp"
echo "  /usr/bin/python3 koboldcpp.py --model /path/to/model.gguf --port 11434 --usecublas --nomodel"
echo ""
echo "或使用启动脚本:"
echo "  cd /opt/my-shell/3080"
echo "  ./run_qwen2.5-coder32b_koboldcpp.sh"