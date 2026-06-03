#!/bin/bash
set -e

# =============================================================================
# FlashAttention 安装脚本
# 目标: RTX 3080 (sm_86), Ubuntu 24.04, CUDA 11.8 (PyTorch 2.4.0+cu118), Python 3.12
# 策略: 优先装预编译 wheel, 没有则源码编译 (走 setup.py)
# =============================================================================
# 完整环境配置兼容性解决过程:
# -------------------------------------------------------------------------
# 
# 【问题1: PyTorch CUDA 版本不匹配】
# 初始环境: PyTorch 2.11.0+cu130 (CUDA 13.0)
# 问题: flash-attn 没有 cu130 的预编译 wheel，且编译时与系统 CUDA 冲突
# 解决: 
#   1. 下载 PyTorch 2.4.0+cu118 wheel (torch-2.4.0+cu118-cp312-cp312-linux_x86_64.whl)
#   2. 强制安装: pip install torch-2.4.0+cu118-cp312-cp312-linux_x86_64.whl --force-reinstall
#   3. 验证: python -c "import torch; print(torch.version.cuda)" -> 11.8
#
# 【问题2: exllamav2 需要匹配 PyTorch CUDA 版本】
# 初始: exllamav2 为 cu130 编译，与 PyTorch cu118 不兼容
# 解决:
#   1. 从 GitHub releases 下载 exllamav2-0.3.2+cu118.torch2.4.0-cp312-cp312-linux_x86_64.whl
#   2. 强制安装: pip install exllamav2-0.3.2+cu118.torch2.4.0-cp312-cp312-linux_x86_64.whl --force-reinstall
#   注意: 安装 exllamav2 时会自动升级 PyTorch 回 cu130，需要再次强制降级
#
# 【问题3: 系统 CUDA 版本与 PyTorch 不匹配】
# 系统默认: /usr/local/cuda -> /data/cuda (CUDA 12.6)
# PyTorch: CUDA 11.8
# 问题: nvcc 检测 CUDA 12.6，但 PyTorch 编译用 11.8 -> 报错 "CUDA version mismatch"
# 解决:
#   1. 下载 CUDA 11.8 toolkit: wget https://developer.download.nvidia.com/compute/cuda/11.8.0/local_installers/cuda_11.8.0_520.61.05_linux.run
#   2. 安装到 /data/cuda-11.8: sh cuda_11.8.0_520.61.05_linux.run --silent --toolkit --override --installpath=/data/cuda-11.8
#   3. 修改符号链接: rm -f /usr/local/cuda && ln -s /data/cuda-11.8 /usr/local/cuda
#   4. 验证: /usr/local/cuda/bin/nvcc --version -> release 11.8
#
# 【问题4: GCC 版本不兼容】
# CUDA 11.8 最高支持 GCC 11
# Ubuntu 24.04 默认 GCC 13
# 错误: "unsupported GNU version! gcc versions later than 11 are not supported"
# 解决:
#   1. 安装 GCC 11: sudo apt-get install -y gcc-11 g++-11
#   2. 设置环境变量: export CC=/usr/bin/gcc-11 && export CXX=/usr/bin/g++-11
#
# 【问题5: GPU 架构 compute_120 不支持】
# 错误: "nvcc fatal: Unsupported gpu architecture 'compute_120'"
# 原因: flash-attn setup.py 默认编译 80/90/100/110/120，但 CUDA 11.8 不支持 120
# 解决: export FLASH_ATTN_CUDA_ARCHS="80" (只编译 sm_80，兼容 RTX 3080 sm_86)
#
# 【问题6: 编译超时】
# 问题: 单个 .cu 文件编译需 2-5 分钟，bash 命令 120 秒超时杀死进程
# 解决:
#   1. 单线程编译: export MAX_JOBS=1 && export NVCC_THREADS=1
#   2. 后台运行: setsid bash -c "..." &
#   3. 预计时间: 30-60 分钟
#
# 【问题7: ninja 构建工具】
# 警告: "Attempted to use ninja as the BuildExtension backend but we could not find ninja"
# 解决: pip install ninja (可选，没有也能编译，只是慢一点)
#
# 【完整环境变量总结】
#   export CUDA_HOME=/usr/local/cuda        # CUDA 11.8
#   export PATH=/usr/local/cuda/bin:$PATH   # 优先使用 CUDA 11.8 的 nvcc
#   export CC=/usr/bin/gcc-11               # GCC 11
#   export CXX=/usr/bin/g++-11              # G++ 11
#   export FLASH_ATTN_CUDA_ARCHS="80"       # 只编译 sm_80
#   export MAX_JOBS=1                       # 单线程
#   export NVCC_THREADS=1                   # 单线程
#
# =============================================================================
# 方法一: 预编译 wheel (推荐, ~30 秒)
# -------------------------------------------------------------------------
# flash-attn 在 GitHub releases 上提供预编译 wheel, 但需要 torch 版本匹配:
#
#   当前环境:  Python 3.12, torch 2.4.0+cu118, CUDA 11.8
#
# 查看所有可用 wheel:
#   curl -s "https://github.com/Dao-AILab/flash-attention/releases/expanded_assets/v2.8.3" \
#     | grep -oP 'flash_attn-[^"]*\.whl' | sort -u
#
# 当前环境没有预编译 wheel，必须源码编译
# =============================================================================
# 方法二: 源码编译 (如无匹配 wheel, ~30-60 分钟)
# -------------------------------------------------------------------------
# 踩坑记录:
#
# 1. GCC 版本:
#    - Ubuntu 24.04 默认 gcc-13, CUDA 11.8 只支持到 gcc-11
#    - 错误: "unsupported GNU version! gcc versions later than 11 are not supported"
#    - 解决: export CC=/usr/bin/gcc-11 CXX=/usr/bin/g++-11
#    - 安装: sudo apt install gcc-11 g++-11
#
# 2. ptxas -O3 极慢:
#    - fwd_split 内核的 .ptx 文件巨大, ptxas 默认 -O3 优化每个文件需 30-50 分钟
#    - 且每个 ptxas 进程吃 ~5GB RAM, MAX_JOBS=3 时 ~15GB 会 OOM
#    - 解决: 单线程编译 MAX_JOBS=1, NVCC_THREADS=1
#
# 3. MAX_JOBS 调优:
#    - 23GB RAM + 单线程: MAX_JOBS=1, NVCC_THREADS=1
#    - 避免超时: 使用 setsid 后台运行
#    - 预计时间: 30-60 分钟
#
# 4. 架构代码:
#    - RTX 3080 = sm_86, 但 setup.py 默认编译 80/90/100/110/120
#    - CUDA 11.8 不支持 compute_120
#    - 错误: "nvcc fatal: Unsupported gpu architecture 'compute_120'"
#    - 解决: FLASH_ATTN_CUDA_ARCHS="80" (sm_80 兼容 sm_86)
#
# 5. CUDA 版本路径:
#    - 必须确保 /usr/local/cuda 指向 CUDA 11.8 (不是 12.6)
#    - 错误: "The detected CUDA version (12.6) mismatches the version that was used to compile PyTorch (11.8)"
#    - 解决: rm -f /usr/local/cuda && ln -s /data/cuda-11.8 /usr/local/cuda
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

# 编译参数: 单线程编译（避免OOM和系统崩溃）
# 23GB RAM 下，单线程最稳定，虽然慢一点
export NVCC_THREADS=1
export MAX_JOBS=1
echo "=== 编译配置 ==="
echo "NVCC_THREADS=1 (单线程，避免内存耗尽)"
echo "MAX_JOBS=1 (单任务，最稳定)"
echo "预计时间: 30-60 分钟"

echo "=== 清理旧 build ==="
rm -rf build dist *.egg-info

echo "=== 设置编译环境变量 ==="
# 使用 CUDA 11.8 (匹配 PyTorch 2.4.0+cu118)
export CUDA_HOME=/usr/local/cuda
export PATH=$CUDA_HOME/bin:/data/venv/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH

# GCC 11 (CUDA 11.8 最高支持)
export CC=/usr/bin/gcc-11
export CXX=/usr/bin/g++-11

# RTX 3080 架构 (8.6) - 只编译目标架构
export FLASH_ATTN_CUDA_ARCHS="80"
export TORCH_CUDA_ARCH_LIST="8.6"

# 限制 CUDA 模块加载
export CUDA_MODULE_LOADING=LAZY

echo "CUDA_HOME: $CUDA_HOME"
echo "GCC: $CC (gcc-11 for CUDA 11.8 compatibility)"
echo "MAX_JOBS: $MAX_JOBS"
echo "FLASH_ATTN_CUDA_ARCHS: $FLASH_ATTN_CUDA_ARCHS"

echo "=== 开始编译并安装 ==="
echo "如果编译中断，请尝试: export MAX_JOBS=1 后重新运行"

VENV_PYTHON=/data/venv/bin/python3
VENV_PIP=/data/venv/bin/pip

echo "=== 确保 torch 已安装 ==="
$VENV_PYTHON -c "import torch" 2>/dev/null || $VENV_PIP install torch==2.4.0+cu118 --index-url https://download.pytorch.org/whl/cu118

echo "=== 安装编译依赖 ==="
$VENV_PIP install wheel setuptools pybind11

# === 优先尝试预编译 wheel (cu118 torch2.4.0) ===
WHEEL_URL="https://github.com/Dao-AILab/flash-attention/releases/download/v2.8.3/flash_attn-2.8.3+cu118torch2.4.0-cp312-cp312-linux_x86_64.whl"
echo "=== 尝试预编译 wheel: $WHEEL_URL ==="
if curl -sI "$WHEEL_URL" 2>/dev/null | grep -q "200\|302"; then
    $VENV_PIP install "$WHEEL_URL" && {
        echo "=== wheel 安装成功 ==="
        cd /
        $VENV_PYTHON -c "import torch; import flash_attn; print(f'FlashAttention 版本: {flash_attn.__version__}')"
        exit 0
    }
fi
echo "=== 预编译 wheel 不可用 ==="

# === wheel 不可用, 回退到源码编译 ===
echo "=== wheel 不可用, 走源码编译 ==="
echo "编译时间较长(30-60分钟)，使用后台运行..."

# 修改编译优化级别：-O3 → -O1（编译更快，运行稍慢）
echo "=== 修改编译优化级别: -O3 → -O1 ==="
sed -i 's/-O3/-O1/g' /opt/flash-attention/setup.py
echo "优化级别已改为 -O1（编译速度提升 30-50%）"

# 确保日志文件可写
rm -f /tmp/flash_build.log
touch /tmp/flash_build.log
chmod 666 /tmp/flash_build.log

# 后台编译，避免终端超时
setsid bash -c "
    cd /opt/flash-attention
    export PATH=/usr/local/cuda/bin:\$PATH
    export CUDA_HOME=/usr/local/cuda
    export CC=/usr/bin/gcc-11
    export CXX=/usr/bin/g++-11
    export FLASH_ATTN_CUDA_ARCHS=\"80\"
    export MAX_JOBS=1
    export NVCC_THREADS=1
    exec > /tmp/flash_build.log 2>&1
    /data/venv/bin/python setup.py install
" &

BUILD_PID=$!
echo "编译进程 PID: $BUILD_PID"
echo "日志: tail -f /tmp/flash_build.log"
echo ""
echo "等待编译完成..."

# 等待编译完成
while true; do
    if $VENV_PYTHON -c "import flash_attn" 2>/dev/null; then
        echo ""
        echo "=== 编译完成 ==="
        $VENV_PYTHON -c "import flash_attn; print(f'FlashAttention 版本: {flash_attn.__version__}')"
        exit 0
    fi
    if ! ps -p $BUILD_PID > /dev/null 2>&1; then
        echo ""
        echo "编译进程已结束"
        if $VENV_PYTHON -c "import flash_attn" 2>/dev/null; then
            echo "=== 编译成功 ==="
            $VENV_PYTHON -c "import flash_attn; print(f'FlashAttention 版本: {flash_attn.__version__}')"
            exit 0
        else
            echo "=== 编译失败 ==="
            echo "查看日志: tail -50 /tmp/flash_build.log"
            exit 1
        fi
    fi
    echo -n "."
    sleep 30
done

# =============================================================================
# 手动编译命令（如需直接执行）
# =============================================================================
# cd /opt/flash-attention
# sed -i 's/-O3/-O1/g' setup.py
# PATH=/usr/local/cuda/bin:$PATH CUDA_HOME=/usr/local/cuda \
#   CC=/usr/bin/gcc-11 CXX=/usr/bin/g++-11 \
#   FLASH_ATTN_CUDA_ARCHS="80" MAX_JOBS=2 NVCC_THREADS=2 \
#   /data/venv/bin/python setup.py install
# =============================================================================
