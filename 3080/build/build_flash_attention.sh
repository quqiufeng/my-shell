#!/bin/bash
set -e

# =============================================================================
# FlashAttention 安装脚本
# 目标: RTX 3080 (sm_86), Ubuntu 24.04, CUDA 12.6, Python 3.12
# 策略: 优先装预编译 wheel, 没有则源码编译 (走 setup.py)
# =============================================================================
# 方法一: 预编译 wheel (推荐, ~30 秒)
# -------------------------------------------------------------------------
# flash-attn 在 GitHub releases 上提供预编译 wheel, 但需要 torch 版本匹配:
#
#   最新 wheel: flash_attn-2.8.3+cu12torch2.9cxx11abiTRUE-cp312-cp312-*.whl
#   对应环境:  Python 3.12, torch 2.9.x, CUDA 12.x, CXX11ABI=True
#
# 如果当前 torch 版本太新 (如 2.12), 需先降级:
#
#   pip install torch==2.9.0 --index-url https://download.pytorch.org/whl/cu126
#
# 查看所有可用 wheel (按版本筛选):
#   curl -s "https://github.com/Dao-AILab/flash-attention/releases/expanded_assets/v2.8.3" \
#     | grep -oP 'flash_attn-[^"]*\.whl' | sort -u
#
# 下载并安装:
#   pip install \
#     https://github.com/Dao-AILab/flash-attention/releases/download/v2.8.3/flash_attn-2.8.3+cu12torch2.9cxx11abiTRUE-cp312-cp312-linux_x86_64.whl
#
# 可用 torch 版本: 2.4, 2.5, 2.6, 2.7, 2.8, 2.9 (cp39~cp313, cxx11abi 均有)
# =============================================================================
# 方法二: 源码编译 (如无匹配 wheel, ~1-2 小时)
# -------------------------------------------------------------------------
# 踩坑记录:
#
# 1. GCC 版本:
#    - Ubuntu 24.04 默认 gcc-13, CUDA 12.6 对其支持不佳
#    - cicc 阶段可能异常慢 (单个 .cu 文件 >20 分钟 vs gcc-12 ~2 分钟)
#    - 解决: export CC=/usr/bin/gcc-12 CXX=/usr/bin/g++-12
#    - 安装: sudo apt install gcc-12 g++-12
#
# 2. ptxas -O3 极慢 (核心问题):
#    - fwd_split 内核的 .ptx 文件巨大, ptxas 默认 -O3 优化每个文件需 30-50 分钟
#    - 且每个 ptxas 进程吃 ~5GB RAM, MAX_JOBS=3 时 ~15GB 会 OOM
#    - 解决: 修改 setup.py, 在 nvcc_flags 加 -Xptxas=-O1
#
# 3. MAX_JOBS 调优:
#    - 6 核 + 23GB RAM: MAX_JOBS=2, NVCC_THREADS=2 最佳
#    - MAX_JOBS=6 -> OOM + swap 卡死
#    - MAX_JOBS=1 -> 太慢 (fwd_split 单文件 40 分钟)
#
# 4. 架构代码:
#    - RTX 3080 = sm_86, 但 setup.py 只认 80/90/100/110/120
#    - sm_80 向后兼容 sm_86, 用 FLASH_ATTN_CUDA_ARCHS="80"
#
# 5. 跳过 fwd_split:
#    - 如不需要 split-KV 功能, 可注释 setup.py 357-380 行的 flash_fwd_split_* 文件
#    - 总共 24 个文件, 占 90%+ 编译时间
#    - 不影响常规推理, 仅训练长序列时需要
# =============================================================================

if [ ! -d "/opt/flash-attention" ]; then
    echo "=== 克隆 flash-attention ==="
    git clone https://github.com/Dao-AILab/flash-attention.git /opt/flash-attention
fi

cd /opt/flash-attention

# 检查内存
echo "=== 系统资源检查 ==="
free -h
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
echo "总内存: ${TOTAL_MEM}MB"

# 编译参数: 6 核 CPU + 23GB RAM 最优配置
export NVCC_THREADS=2
export MAX_JOBS=2
echo "=== 编译配置 ==="
echo "NVCC_THREADS=2 (每个编译任务2线程)"
echo "MAX_JOBS=2 (2个并行编译任务)"
echo "总并行: 4线程"

echo "=== 清理旧 build ==="
rm -rf build dist *.egg-info

echo "=== 设置编译环境变量 ==="
export CUDA_HOME=/data/cuda
export PATH=$CUDA_HOME/bin:/data/venv/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH

export CC=/usr/bin/gcc-12
export CXX=/usr/bin/g++-12

# RTX 3080 架构 (8.6) - 只编译目标架构
export FLASH_ATTN_CUDA_ARCHS="80"
export TORCH_CUDA_ARCH_LIST="8.6"

# 限制 CUDA 模块加载
export CUDA_MODULE_LOADING=LAZY

echo "CUDA_HOME: $CUDA_HOME"
echo "GCC: $CC (gcc-12 for CUDA 12.6 compatibility)"
echo "MAX_JOBS: $MAX_JOBS"
echo "FLASH_ATTN_CUDA_ARCHS: $FLASH_ATTN_CUDA_ARCHS"

echo "=== 开始编译并安装 ==="
echo "如果编译中断，请尝试: export MAX_JOBS=1 后重新运行"

VENV_PYTHON=/data/venv/bin/python3
VENV_PIP=/data/venv/bin/pip

echo "=== 确保 torch 已安装 ==="
$VENV_PYTHON -c "import torch" 2>/dev/null || $VENV_PIP install torch --index-url https://download.pytorch.org/whl/cu126

echo "=== 安装编译依赖 ==="
$VENV_PIP install wheel setuptools pybind11

# === 优先尝试预编译 wheel ===
FA_VERSION=$($VENV_PYTHON -c "import torch; v = torch.__version__.split('+')[0]; print(f'cu12torch{v}')" 2>/dev/null || echo "cu12torch2.9")
WHEEL_URL="https://github.com/Dao-AILab/flash-attention/releases/download/v2.8.3/flash_attn-2.8.3+${FA_VERSION}cxx11abiTRUE-cp312-cp312-linux_x86_64.whl"
echo "=== 尝试预编译 wheel: $WHEEL_URL ==="
if curl -sI "$WHEEL_URL" 2>/dev/null | grep -q "200\|302"; then
    $VENV_PIP install "$WHEEL_URL" && {
        echo "=== wheel 安装成功 ==="
        cd /
        $VENV_PYTHON -c "import torch; import flash_attn; print(f'FlashAttention 版本: {flash_attn.__version__}')"
        exit 0
    }
fi

# === wheel 不可用, 回退到源码编译 ===
echo "=== wheel 不可用, 走源码编译 ==="
$VENV_PIP install -v --no-build-isolation -e . 2>&1 || {
    echo "编译失败，尝试单线程重试..."
export MAX_JOBS=1
    rm -rf build dist *.egg-info
    $VENV_PIP install -v --no-build-isolation -e . 2>&1
}

echo "=== 验证安装 ==="
cd /
$VENV_PYTHON -c "import torch; import flash_attn; print(f'FlashAttention 版本: {flash_attn.__version__}')" || {
    echo "验证失败"
    exit 1
}

echo "=== 编译完成 ==="
echo "编译日志保存于: /root/flash_build.log"
