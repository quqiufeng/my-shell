#!/bin/bash
set -e

echo "=== 编译 koboldcpp (CUDA 版本) ==="
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

echo ""
echo "=== 开始编译 (CUDA 支持) ==="
echo "这可能需要 5-10 分钟..."
echo ""

# 使用 koboldcpp 的 Makefile 编译 CUDA 版本
# 关键参数:
# - LLAMA_CUDA=1: 启用 CUDA 支持
# - CUDA_PATH: CUDA 安装路径
make -j$(nproc) LLAMA_CUDA=1 CUDA_PATH=/opt/cuda

echo ""
echo "=== 编译完成 ==="
echo ""
echo "生成的文件:"
ls -lh *.so 2>/dev/null | grep -E "(cublas|default)" || ls -lh *.so | head -5
echo ""
echo "使用方法:"
echo "  cd /opt/koboldcpp"
echo "  python koboldcpp.py --model /path/to/model.gguf --port 11434"
echo ""
echo "或使用命令行模式 (无 GUI):"
echo "  python koboldcpp.py --model /path/to/model.gguf --port 11434 --nomodel"
