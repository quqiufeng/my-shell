#!/bin/bash
set -e

# =============================================================================
# FlashAttention 编译脚本
# 针对 RTX 4090D (CUDA 13.1, Compute Capability 8.9)
# =============================================================================

cd /opt/flash-attention

echo "=== 清理旧 build ==="
rm -rf build dist *.egg-info

echo "=== 设置编译环境变量 ==="
export CUDA_HOME=/opt/cuda
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH

export CC=$(which gcc)
export CXX=$(which g++)

# 只编译 4090D 架构 (8.9 = 90)
export FLASH_ATTN_CUDA_ARCHS="80;90"
export MAX_JOBS=8

echo "CUDA_HOME: $CUDA_HOME"
echo "GCC: $CC"

echo "=== 开始编译并安装 ==="
python setup.py install 2>&1 | tee /root/flash_build.log

echo "=== 验证安装 ==="
cd ~
python3 -c "import torch; import flash_attn; print(f'FlashAttention 版本: {flash_attn.__version__}')"

echo "=== 编译完成 ==="
