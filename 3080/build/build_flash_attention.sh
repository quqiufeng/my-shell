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
# 解决: 直接修改 setup.py 硬编码为只编译 ["80"] (兼容 RTX 3080 sm_86)
#       文件: /opt/flash-attention/setup.py 第73-74行
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
#   export CUDA_HOME=/data/cuda-11.8        # CUDA 11.8 (直接指向安装路径)
#   export PATH=/data/cuda-11.8/bin:$PATH   # 优先使用 CUDA 11.8 的 nvcc
#   export CC=/usr/bin/gcc-11               # GCC 11
#   export CXX=/usr/bin/g++-11              # G++ 11
#   # FLASH_ATTN_CUDA_ARCHS 不需要，setup.py 已硬编码 ["80"]
#   export MAX_JOBS=2                       # 双线程
#   export NVCC_THREADS=2                   # 双线程
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
#    - setup.py 已硬编码只编译 sm_80，大幅减少了编译目标数量
#    - ptxas -O3 极慢，已改为 -O1
#    - 23GB RAM + 单架构: MAX_JOBS=2, NVCC_THREADS=2 稳定
#
# 3. MAX_JOBS 调优:
#    - 23GB RAM + 单架构 (sm_80): MAX_JOBS=2, NVCC_THREADS=2
#    - 避免超时: 使用 setsid 后台运行
#    - 预计时间: 20-40 分钟
#
# 4. 架构代码:
#    - RTX 3080 = sm_86, 但 setup.py 默认编译 80/90/100/110/120
#    - CUDA 11.8 不支持 compute_120
#    - 错误: "nvcc fatal: Unsupported gpu architecture 'compute_120'"
#    - 解决: 直接修改 setup.py 硬编码 ["80"] (sm_80 兼容 sm_86)
#
# 5. CUDA 版本路径:
#    - 系统 /usr/local/cuda 可能指向 CUDA 12.6 (nvcc 12.6)
#    - PyTorch 编译用 CUDA 11.8
#    - 错误: "The detected CUDA version (12.6) mismatches the version that was used to compile PyTorch (11.8)"
#    - 解决: 直接使用 /data/cuda-11.8 路径，不依赖 /usr/local/cuda 符号链接
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

# 编译参数: 双线程编译（setup.py 已硬编码 sm_80，编译量大幅减少）
# 23GB RAM + 修改后的 setup.py 只编译一个架构，双线程稳定
export NVCC_THREADS=2
export MAX_JOBS=2
echo "=== 编译配置 ==="
echo "NVCC_THREADS=2 (双线程)"
echo "MAX_JOBS=2 (双任务)"
echo "setup.py 已硬编码只编译 sm_80"
echo "预计时间: 20-40 分钟"

echo "=== 清理旧 build ==="
rm -rf build dist *.egg-info

echo "=== 设置编译环境变量 ==="
# 使用 CUDA 11.8 (匹配 PyTorch 2.4.0+cu118)
# 注意: /usr/local/cuda 可能指向 CUDA 12.6，直接用 /data/cuda-11.8
export CUDA_HOME=/data/cuda-11.8
export PATH=$CUDA_HOME/bin:/data/venv/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH

# GCC 11 (CUDA 11.8 最高支持)
export CC=/usr/bin/gcc-11
export CXX=/usr/bin/g++-11

# RTX 3080 架构 (8.6) - setup.py 已硬编码为只编译 sm_80
# export FLASH_ATTN_CUDA_ARCHS="80"  # 不需要，setup.py 已修改
export TORCH_CUDA_ARCH_LIST="8.6"

# 限制 CUDA 模块加载
export CUDA_MODULE_LOADING=LAZY

echo "CUDA_HOME: $CUDA_HOME"
echo "GCC: $CC (gcc-11 for CUDA 11.8 compatibility)"
echo "MAX_JOBS: $MAX_JOBS"
echo "NVCC_THREADS: $NVCC_THREADS"
echo "架构: setup.py 硬编码 [80] (兼容 sm_86 RTX 3080)"

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
# 注意: setup.py 已硬编码为只编译 sm_80，无需 FLASH_ATTN_CUDA_ARCHS
setsid bash -c "
    cd /opt/flash-attention
    export CUDA_HOME=/data/cuda-11.8
    export PATH=/data/cuda-11.8/bin:\$PATH
    export CC=/usr/bin/gcc-11
    export CXX=/usr/bin/g++-11
    export MAX_JOBS=2
    export NVCC_THREADS=2
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
# 注意: setup.py 已硬编码为只编译 sm_80，无需 FLASH_ATTN_CUDA_ARCHS 环境变量
# cd /opt/flash-attention && rm -rf build
# export CUDA_HOME=/data/cuda-11.8
# export PATH=/data/cuda-11.8/bin:$PATH
# source /data/venv/bin/activate
# MAX_JOBS=2 NVCC_THREADS=2 python setup.py install
# =============================================================================
