#!/bin/bash
set -e

echo "=== 编译 koboldcpp (CUDA 版本 for RTX 4090D) ==="
echo ""

# 检查 CUDA
if [ ! -d "/opt/cuda" ]; then
    echo "错误: 未找到 /opt/cuda 目录"
    exit 1
fi

export PATH=/opt/cuda/bin:$PATH
export LD_LIBRARY_PATH=/opt/cuda/lib64:$LD_LIBRARY_PATH

cd /opt/koboldcpp

echo "=== 清理旧的编译文件 ==="
make clean 2>/dev/null || true
rm -f *.so *.o

echo ""
echo "=== 开始编译 (CUDA/cuBLAS for RTX 4090D) ==="
echo "架构: CUDA 8.9 (RTX 4090D)"
echo "这可能需要 10-20 分钟..."
echo ""

# 只编译 CUDA 版本 (koboldcpp_cublas)
# 关键参数:
# - LLAMA_CUBLAS=1: 启用 cuBLAS 支持
# - CUDA_ARCHITECTURES=89: RTX 4090 的 CUDA 架构
# - 只编译 koboldcpp_cublas 目标，跳过 CPU 版本
make -j$(nproc) LLAMA_CUBLAS=1 CUDA_ARCHITECTURES=89 koboldcpp_cublas

echo ""
echo "=== 编译完成 ==="
echo ""

# 检查是否生成成功
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
echo "  cd /opt/my-shell/4090d"
echo "  ./run_qwen2.5-coder32b_koboldcpp.sh"
