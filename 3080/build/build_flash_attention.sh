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
#   3. 验证: /data/cuda-11.8/bin/nvcc --version -> release 11.8
#   4. 重要: 不要依赖 /usr/local/cuda 符号链接（可能被其他进程修改），直接用 /data/cuda-11.8 绝对路径
#
# 【问题4: GCC 版本不兼容】
# CUDA 11.8 最高支持 GCC 11
# Ubuntu 24.04 默认 GCC 13
# 错误: "unsupported GNU version! gcc versions later than 11 are not supported"
# 解决:
#   1. 安装 GCC 11: sudo apt-get install -y gcc-11 g++-11
#   2. 设置环境变量: export CC=/usr/bin/gcc-11 && export CXX=/usr/bin/g++-11
#
# 【问题5: PyTorch 自动检测 CUDA 架构（关键坑）】
# 错误: "nvcc fatal: Unsupported gpu architecture 'compute_120'"
# 原因: flash-attn 的 FLASH_ATTN_CUDA_ARCHS 只控制 flash-attn 自己的架构列表
#       但 PyTorch 的 cpp_extension.py 会读取 TORCH_CUDA_ARCH_LIST
#       如果没设置，会自动检测所有可见 GPU 的 capability 并加入编译参数
#       环境中有其他卡（如 RTX 4090 sm_120）时，会把 compute_120 加入
#       但 CUDA 11.8 不支持 compute_120，所以报错
# 解决: export TORCH_CUDA_ARCH_LIST="8.6" (RTX 3080 的 capability)
#       这样 PyTorch 只编译 sm_86 兼容的 sm_80
# 验证: 在编译命令中能看到 -gencode arch=compute_80,code=sm_80
#
# 【问题6: undefined symbol 错误（链接失败）】
# 错误: ImportError: .../flash_attn_2_cuda.cpython-312-x86_64-linux-gnu.so: 
#       undefined symbol: _ZN5flash12run_mha_bwd_IN7cutlass10bfloat16_tELi256ELb1EEEvRNS_16Flash_bwd_paramsEP11CUstream_st
# 原因: 编译过程中断（被 SIGKILL 杀掉，code 137），导致某些 .cu 文件没编译完
#       但 install 步骤跑了，生成不完整的 .so 文件
#       缺失的符号对应 flash_bwd_hdim256_bf16_causal_sm80.cu
# 解决:
#   1. 检查缺失的 .o 文件: ls /opt/flash-attention/build/temp.linux-x86_64-cpython-312/csrc/flash_attn/src/*.o
#   2. 重新执行编译命令，ninja 会增量编译缺失的文件
#   3. 如果 build 目录损坏，需要 rm -rf build 后全新编译
#
# 【问题7: 编译超时】
# 问题: 单个 .cu 文件编译需 2-30 分钟，bash 命令 120 秒超时杀死进程
# 解决:
#   1. 后台运行: nohup ... > log 2>&1 &
#   2. 避免 SIGHUP: setsid 或 nohup
#   3. 预计时间: 4-8 小时（hdim256 系列特别慢）
#
# 【问题8: ninja 构建工具】
# 警告: "Attempted to use ninja as the BuildExtension backend but we could not find ninja"
# 解决: pip install ninja (可选，没有也能编译，只是慢一点)
#
# 【完整环境变量总结】（最终方案）
#   export CUDA_HOME=/data/cuda-11.8        # CUDA 11.8 (直接绝对路径)
#   export PATH=/data/cuda-11.8/bin:$PATH   # 优先使用 CUDA 11.8 的 nvcc
#   export CC=/usr/bin/gcc-11               # GCC 11
#   export CXX=/usr/bin/g++-11              # G++ 11
#   export TORCH_CUDA_ARCH_LIST="8.6"       # ★ 关键：只编译 sm_86
#   export FLASH_ATTN_CUDA_ARCHS="86"       # flash-attn 自己的架构列表
#   export FLASH_ATTENTION_FORCE_BUILD=1    # 强制源码编译
#   export MAX_JOBS=4                       # 并行任务数
#   export NVCC_THREADS=2                   # 每任务线程数
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
# 当前环境没有预编译 wheel（cu118torch2.4.0cp312），必须源码编译
# =============================================================================
# 方法二: 源码编译 (如无匹配 wheel, 预计 4-8 小时)
# -------------------------------------------------------------------------
# 踩坑记录:
#
# 1. GCC 版本:
#    - Ubuntu 24.04 默认 gcc-13, CUDA 11.8 只支持到 gcc-11
#    - 错误: "unsupported GNU version! gcc versions later than 11 are not supported"
#    - 解决: export CC=/usr/bin/gcc-11 CXX=/usr/bin/g++-11
#    - 安装: sudo apt install gcc-11 g++-11
#
# 2. PyTorch 自动检测 CUDA 架构（关键）:
#    - PyTorch cpp_extension 读取 TORCH_CUDA_ARCH_LIST
#    - 没设置时会自动检测所有可见 GPU 的 capability
#    - 环境中有 RTX 4090 (sm_120) 时会加入 compute_120
#    - CUDA 11.8 不支持 compute_120
#    - 错误: "nvcc fatal: Unsupported gpu architecture 'compute_120'"
#    - 解决: export TORCH_CUDA_ARCH_LIST="8.6"
#
# 3. ptxas -O3 极慢:
#    - fwd_split_hdim256 系列内核巨大，ptxas 默认 -O3 优化每个文件需 30-50 分钟
#    - 且每个 ptxas 进程吃 ~5GB RAM
#    - 解决: 修改 setup.py: sed -i 's/-O3/-O1/g' /opt/flash-attention/setup.py
#    - MAX_JOBS=4 时 ~20GB 内存足够
#
# 4. MAX_JOBS 调优:
#    - 23GB RAM + 单架构: MAX_JOBS=4, NVCC_THREADS=2
#    - 避免超时: 使用 nohup + & 后台运行
#    - 预计时间: 4-8 小时（hdim256 系列特别慢）
#
# 5. 编译中断处理:
#    - 如果被 SIGKILL 杀掉（code 137，OOM 或手动 kill）
#    - 可能某些 .o 文件缺失，但 install 步骤会跑完，生成不完整 .so
#    - 错误: "undefined symbol: flash::run_mha_bwd<...>"
#    - 解决: 重新执行编译命令，ninja 增量编译缺失文件
#    - 不要随便 rm -rf build（会丢失已编译的 .o 文件）
#
# 6. CUDA 版本路径:
#    - 系统 /usr/local/cuda 可能指向 CUDA 12.6 (nvcc 12.6)
#    - PyTorch 编译用 CUDA 11.8
#    - 错误: "The detected CUDA version (12.6) mismatches the version that was used to compile PyTorch (11.8)"
#    - 解决: 直接使用 /data/cuda-11.8 绝对路径，不依赖 /usr/local/cuda 符号链接
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

# 编译参数: 4 任务并行，每任务 2 线程
# 23GB RAM 下，4 任务稳定（fwd_split_hdim256 单文件可能吃 5GB）
export NVCC_THREADS=2
export MAX_JOBS=4
echo "=== 编译配置 ==="
echo "NVCC_THREADS=2 (每任务 2 线程)"
echo "MAX_JOBS=4 (4 任务并行)"
echo "预计时间: 4-8 小时（hdim256 系列特别慢）"

# 重要：不要 rm -rf build！
# 如果之前编译中断，重新执行此脚本，ninja 会增量编译缺失的文件
# 只有当 build 目录损坏时才需要清理

echo "=== 设置编译环境变量 ==="
# 使用 CUDA 11.8 (匹配 PyTorch 2.4.0+cu118)
# 注意: /usr/local/cuda 可能指向 CUDA 12.6，直接用 /data/cuda-11.8
export CUDA_HOME=/data/cuda-11.8
export PATH=$CUDA_HOME/bin:/data/venv/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH

# GCC 11 (CUDA 11.8 最高支持)
export CC=/usr/bin/gcc-11
export CXX=/usr/bin/g++-11

# ★ 关键：只编译 RTX 3080 sm_86
# PyTorch 会自动检测所有可见 GPU 并加入架构列表
# 必须显式设置 TORCH_CUDA_ARCH_LIST 避免 compute_120 错误
export TORCH_CUDA_ARCH_LIST="8.6"
export FLASH_ATTN_CUDA_ARCHS="86"
export FLASH_ATTENTION_FORCE_BUILD=1

# 限制 CUDA 模块加载
export CUDA_MODULE_LOADING=LAZY

echo "CUDA_HOME: $CUDA_HOME"
echo "GCC: $CC (gcc-11 for CUDA 11.8 compatibility)"
echo "TORCH_CUDA_ARCH_LIST: $TORCH_CUDA_ARCH_LIST"
echo "FLASH_ATTN_CUDA_ARCHS: $FLASH_ATTN_CUDA_ARCHS"
echo "MAX_JOBS: $MAX_JOBS, NVCC_THREADS: $NVCC_THREADS"

echo "=== 开始编译并安装 ==="
echo "如果编译中断，请重新执行此脚本，ninja 会增量编译缺失的文件"
echo "不要 rm -rf build！"

VENV_PYTHON=/data/venv/bin/python3
VENV_PIP=/data/venv/bin/pip

echo "=== 确保 torch 已安装 ==="
$VENV_PYTHON -c "import torch" 2>/dev/null || $VENV_PIP install torch==2.4.0+cu118 --index-url https://download.pytorch.org/whl/cu118

echo "=== 安装编译依赖 ==="
$VENV_PIP install wheel setuptools pybind11 ninja

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
echo "编译时间较长(4-8小时)，使用后台运行..."

# 修改编译优化级别：-O3 → -O1（编译更快，运行稍慢）
# 检查是否已经修改过（避免重复 sed）
if grep -q '\-O1' /opt/flash-attention/setup.py; then
    echo "=== 编译优化级别已是 -O1，跳过修改 ==="
else
    echo "=== 修改编译优化级别: -O3 → -O1 ==="
    sed -i 's/-O3/-O1/g' /opt/flash-attention/setup.py
    echo "优化级别已改为 -O1（编译速度提升 30-50%）"
fi

# 确保日志文件可写
rm -f /tmp/flash_build.log
touch /tmp/flash_build.log
chmod 666 /tmp/flash_build.log

# 后台编译，避免终端超时
# ★ 关键：ninja 会增量编译，只会重新编译缺失的 .o 文件
nohup bash -c "
    cd /opt/flash-attention
    export CUDA_HOME=/data/cuda-11.8
    export PATH=/data/cuda-11.8/bin:\$PATH
    export CC=/usr/bin/gcc-11
    export CXX=/usr/bin/g++-11
    export TORCH_CUDA_ARCH_LIST='8.6'
    export FLASH_ATTN_CUDA_ARCHS='86'
    export FLASH_ATTENTION_FORCE_BUILD=1
    export MAX_JOBS=4
    export NVCC_THREADS=2
    exec > /tmp/flash_build.log 2>&1
    /data/venv/bin/python setup.py install
" > /dev/null 2>&1 &

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
        # 验证能正常导入
        $VENV_PYTHON -c "from flash_attn import flash_attn_func; print('flash_attn_func 导入成功')"
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
            echo ""
            echo "常见错误:"
            echo "  1. undefined symbol -> 编译被中断，某个 .o 文件缺失"
            echo "     解决: 重新执行此脚本，ninja 增量编译"
            echo "  2. nvcc fatal: Unsupported gpu architecture 'compute_120'"
            echo "     解决: 检查 TORCH_CUDA_ARCH_LIST 是否设置"
            exit 1
        fi
    fi
    # 显示当前进度
    o_count=$(ls /opt/flash-attention/build/temp.linux-x86_64-cpython-312/csrc/flash_attn/src/*.o 2>/dev/null | wc -l)
    echo -n " [$(date +%H:%M:%S) .o文件: ${o_count}/72]"
    sleep 60
done

# =============================================================================
# 手动编译命令（如需直接执行）
# =============================================================================
# 完整环境变量（重要！）：
#   export CUDA_HOME=/data/cuda-11.8
#   export PATH=/data/cuda-11.8/bin:$PATH
#   export CC=/usr/bin/gcc-11
#   export CXX=/usr/bin/g++-11
#   export TORCH_CUDA_ARCH_LIST="8.6"     # ★ 关键
#   export FLASH_ATTN_CUDA_ARCHS="86"
#   export FLASH_ATTENTION_FORCE_BUILD=1
#
# 命令：
#   cd /opt/flash-attention
#   source /data/venv/bin/activate
#   MAX_JOBS=4 NVCC_THREADS=2 python setup.py install
#
# 增量编译（编译中断后继续）：
#   直接重新执行上述命令，ninja 会自动检测缺失的 .o 文件并编译
#
# 完全重新编译（如果 build 目录损坏）：
#   cd /opt/flash-attention && rm -rf build
#   然后执行上述编译命令
# =============================================================================
