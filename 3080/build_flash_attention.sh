#!/bin/bash
set -e

# =============================================================================
# FlashAttention 编译脚本
# 针对 RTX 3080 (CUDA 12.1, Compute Capability 8.6)
# =============================================================================

cd /opt/flash-attention

echo "=== 清理旧 build ==="
rm -rf build dist *.egg-info

echo "=== 设置编译环境变量 ==="
export CUDA_HOME=/opt/cuda12.1
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH

export CC=/usr/bin/gcc-12
export CXX=/usr/bin/g++-12

# RTX 3080 架构 (8.6)
export FLASH_ATTN_CUDA_ARCHS="86"
export MAX_JOBS=2

echo "CUDA_HOME: $CUDA_HOME"
echo "GCC: $CC"

echo "=== 开始编译并安装 ==="
/home/dministrator/anaconda3/envs/dl/bin/python setup.py install 2>&1 | tee /root/flash_build.log

echo "=== 验证安装 ==="
cd ~
/home/dministrator/anaconda3/envs/dl/bin/python -c "import torch; import flash_attn; print(f'FlashAttention 版本: {flash_attn.__version__}')"

echo "=== 编译完成 ==="
