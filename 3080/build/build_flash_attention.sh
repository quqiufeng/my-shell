#!/bin/bash
set -e

# =============================================================================
# FlashAttention 编译脚本 (优化版)
# 针对 RTX 3080 (CUDA 12.1, Compute Capability 8.6)
# 优化点: 内存限制、并行度控制、重试机制
# =============================================================================

cd /opt/flash-attention

# 检查内存
echo "=== 系统资源检查 ==="
free -h
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
echo "总内存: ${TOTAL_MEM}MB"

# FlashAttention 编译内存优化配置 (极限模式)
# 72个CUDA文件 | CPU: 6核 | 内存: 24GB
# 激进配置: 3个并行任务 x 6线程 = 18并发
export NVCC_THREADS=6
export MAX_JOBS=3
echo "=== 编译配置 (极限模式) ==="
echo "NVCC_THREADS=6 (每个任务6线程)"
echo "MAX_JOBS=3 (3个并行编译任务)"
echo "总并行: 18线程 | 风险: 内存可能不足"
echo "预计时间: 3-5分钟 (72文件÷3任务≈24轮)"
echo "⚠️ 如果OOM崩溃，请改回 MAX_JOBS=2"

echo "=== 清理旧 build ==="
rm -rf build dist *.egg-info

echo "=== 设置编译环境变量 ==="
export CUDA_HOME=/opt/cuda12.1
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH

export CC=/usr/bin/gcc-12
export CXX=/usr/bin/g++-12

# RTX 3080 架构 (8.6) - 只编译目标架构
export FLASH_ATTN_CUDA_ARCHS="86"
export TORCH_CUDA_ARCH_LIST="8.6"

# 限制 CUDA 模块加载
export CUDA_MODULE_LOADING=LAZY

echo "CUDA_HOME: $CUDA_HOME"
echo "GCC: $CC"
echo "MAX_JOBS: $MAX_JOBS"
echo "FLASH_ATTN_CUDA_ARCHS: $FLASH_ATTN_CUDA_ARCHS"

echo "=== 开始编译并安装 ==="
echo "如果编译中断，请尝试: export MAX_JOBS=1 后重新运行"

# 使用 pip 安装并限制内存
/home/dministrator/anaconda3/envs/dl/bin/pip install -v --no-build-isolation -e . 2>&1 | tee /root/flash_build.log || {
    echo "编译失败，尝试单线程重试..."
    export MAX_JOBS=1
    rm -rf build dist *.egg-info
    /home/dministrator/anaconda3/envs/dl/bin/pip install -v --no-build-isolation -e . 2>&1 | tee /root/flash_build.log.retry
}

echo "=== 验证安装 ==="
cd ~
/home/dministrator/anaconda3/envs/dl/bin/python -c "import torch; import flash_attn; print(f'FlashAttention 版本: {flash_attn.__version__}')" || {
    echo "验证失败，检查日志: /root/flash_build.log"
    exit 1
}

echo "=== 编译完成 ==="
echo "编译日志保存于: /root/flash_build.log"
