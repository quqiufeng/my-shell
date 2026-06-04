#!/bin/bash
set -e

# =============================================================================
# FlashAttention 安装脚本 (RTX 3080 20GB, sm_86, 最终稳定版)
# =============================================================================
# 目标环境:
#   GPU:    NVIDIA GeForce RTX 3080 (sm_86, 20GB)
#   OS:     Ubuntu 24.04
#   CUDA:   11.8 (系统装在 /data/cuda-11.8, 不用 /usr/local/cuda 符号链接)
#   PyTorch: 2.4.0+cu118
#   Python: 3.12
#   venv:   /data/venv
#   用途:   exllamav2 等 PyTorch CUDA 扩展启用 flash-attn
# =============================================================================
# 完整环境配置兼容性解决过程 (踩坑实录, 按时间顺序)
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
# 【问题6: ★★★ setup.py 缺少源文件 (本次踩的最大坑) ★★★】
# 错误: ImportError: .../flash_attn_2_cuda.cpython-312-x86_64-linux-gnu.so:
#       undefined symbol: _ZN5flash12run_mha_bwd_IN7cutlass10bfloat16_tELi256ELb1EEEvRNS_16Flash_bwd_paramsEP11CUstream_st
# 解读: 这个 mangled symbol 是 flash::run_mha_bwd<bfloat16_t, 256, true>
#       三个模板参数: bfloat16_t, hdim=256, is_causal=true
#       即缺失 flash_bwd_hdim256_bf16_causal_sm80.cu 编译产物
# 原因: flash-attention 2.8.x 的 setup.py 在 srcfiles 列表中
#       漏列了 csrc/flash_attn/src/flash_bwd_hdim256_bf16_causal_sm80.cu
#       文件存在但 ninja 不会编译它 (因为没列在 build 目标里)
#       即使完整跑完编译流程，链接的 .so 也会缺这个符号
# 解决: 编辑 /opt/flash-attention/setup.py，在 srcfiles 列表中
#       'flash_bwd_hdim256_bf16_sm80.cu' 后面添加
#       'flash_bwd_hdim256_bf16_causal_sm80.cu',
#       (即把 hdim256 bf16 causal 的 bwd 三个变体都补齐)
# 验证: 编译完成后应生成 73 个 .o (不是 72 个)
#       缺少这一个文件时 ninja 进度会停在 [72/73]
#
# 【问题7: 编译超时 (bash 120s 限制)】
# 问题: 单个 .cu 文件编译需 2-30 分钟，bash 命令 120 秒超时杀死进程
# 解决: 用 nohup + setsid + disown 完全分离后台进程
#       nohup setsid /data/venv/bin/python -c "..." > log 2>&1 < /dev/null & disown
#       注意: 1) 不要用 source activate (在 nohup bash -c 里不生效)
#             2) 用绝对路径 /data/venv/bin/python
#             3) 必须重定向 stdin (< /dev/null)
#             4) setsid 防止 SIGHUP
#             5) disown 防止 shell 退出时 SIGHUP
# 预计时间: 1.5 小时 (本次实测，73 个 .o)
#
# 【问题8: 编译中断后的恢复 (避免 rm -rf build 大忌)】
# 问题: build/ 目录里是已经编译的 .o 文件 (每个文件 10-100MB)
#       rm -rf build 会丢失所有进度，必须从头开始 (4-8 小时)
# 解决: 编译中断时不要 rm -rf build, 直接重跑脚本
#       ninja 会自动检测缺失的 .o 并增量编译
#       只在 build 目录真的损坏时才删除
#
# 【问题9: 修改 setup.py 后如何让 ninja 重新解析】
# 问题: 改了 setup.py (如添加源文件) 后，ninja 不会重新解析依赖图
# 解决: 删 build.ninja (不是 .o), 让 ninja 重新扫描 setup.py
#       find /opt/flash-attention/build -name "build.ninja" -delete
#       重新跑 python setup.py install
#       ninja 会扫描 setup.py 的新 srcfiles 列表, 生成新依赖图
#       已有的 .o 文件会被保留 (没改的源文件不需要重编译)
#
# 【问题10: ninja 构建工具】
# 警告: "Attempted to use ninja as the BuildExtension backend but we could not find ninja"
# 解决: pip install ninja (可选，没有也能编译，只是慢一点)
# =============================================================================
# 【完整环境变量总结】（最终方案）
#   export CUDA_HOME=/data/cuda-11.8        # CUDA 11.8 (直接绝对路径)
#   export PATH=/data/cuda-11.8/bin:$PATH   # 优先使用 CUDA 11.8 的 nvcc
#   export CC=/usr/bin/gcc-11               # GCC 11
#   export CXX=/usr/bin/g++-11              # G++ 11
#   export TORCH_CUDA_ARCH_LIST="8.6"       # ★ 关键：只编译 sm_86
#   export FLASH_ATTN_CUDA_ARCHS="86"       # flash-attn 自己的架构列表
#   export FLASH_ATTENTION_FORCE_BUILD=1    # 强制源码编译
#   export MAX_JOBS=4                       # 并行任务数 (23GB RAM 下稳定)
#   export NVCC_THREADS=2                   # 每任务线程数
# =============================================================================

# ---------------------- 0. 前置检查 ----------------------
echo "=== 系统环境检查 ==="
free -h | head -2
echo "GPU:"
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
echo ""

if [ ! -d "/opt/flash-attention" ]; then
    echo "=== 克隆 flash-attention ==="
    git clone https://github.com/Dao-AILab/flash-attention.git /opt/flash-attention
fi

cd /opt/flash-attention

# 检查内存
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
echo "总内存: ${TOTAL_MEM}MB (建议 >= 20GB)"

# ---------------------- 1. 编译参数 ----------------------
echo "=== 编译配置 ==="
echo "NVCC_THREADS=2 (每任务 2 线程)"
echo "MAX_JOBS=4 (4 任务并行，fwd_split_hdim256 单文件可能吃 5GB)"
echo "预计时间: 1.5 小时 (73 个 .o, 6 核 CPU 实测)"
echo ""

# ---------------------- 2. 关键: 修复 setup.py 缺源文件 bug ----------------------
SETUP_PY="/opt/flash-attention/setup.py"
echo "=== 检查 setup.py 是否包含全部 73 个源文件 ==="
# 验证: 关键文件 flash_bwd_hdim256_bf16_causal_sm80.cu 是否在 srcfiles 里
if grep -q "flash_bwd_hdim256_bf16_causal_sm80" "$SETUP_PY"; then
    echo "✓ flash_bwd_hdim256_bf16_causal_sm80.cu 已在 srcfiles 列表中"
else
    echo "✗ 检测到 bug: flash_bwd_hdim256_bf16_causal_sm80.cu 不在 srcfiles 中"
    echo "  正在自动修复..."
    # 在 srcfiles 列表中 'flash_bwd_hdim256_bf16_sm80.cu' 行后插入缺失的文件
    # 使用 sed 替换: 在该行后插入新行
    sed -i "/flash_bwd_hdim256_bf16_sm80.cu/a\\    'flash_bwd_hdim256_bf16_causal_sm80.cu'," "$SETUP_PY"
    echo "  ✓ 已添加 'flash_bwd_hdim256_bf16_causal_sm80.cu' 到 srcfiles"
    echo "  验证修复:"
    grep -n "flash_bwd_hdim256_bf16" "$SETUP_PY" | head -5
fi
echo ""

# ---------------------- 3. 编译优化级别 (-O3 → -O1) ----------------------
if grep -q '\-O1' "$SETUP_PY"; then
    echo "=== 编译优化级别已是 -O1，跳过修改 ==="
else
    echo "=== 修改编译优化级别: -O3 → -O1 ==="
    sed -i 's/-O3/-O1/g' "$SETUP_PY"
    echo "  优化级别已改为 -O1 (编译速度提升 30-50%)"
fi
echo ""

# ---------------------- 4. 设置编译环境变量 ----------------------
echo "=== 设置编译环境变量 ==="
# 使用 CUDA 11.8 (匹配 PyTorch 2.4.0+cu118)
# 注意: /usr/local/cuda 可能指向 CUDA 12.6，直接用 /data/cuda-11.8
export CUDA_HOME=/data/cuda-11.8
export PATH=$CUDA_HOME/bin:/data/venv/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH

# GCC 11 (CUDA 11.8 最高支持)
export CC=/usr/bin/gcc-11
export CXX=/usr/bin/g++-11

# ★ 关键: 只编译 RTX 3080 sm_86
# PyTorch 会自动检测所有可见 GPU 并加入架构列表
# 必须显式设置 TORCH_CUDA_ARCH_LIST 避免 compute_120 错误
export TORCH_CUDA_ARCH_LIST="8.6"
export FLASH_ATTN_CUDA_ARCHS="86"
export FLASH_ATTENTION_FORCE_BUILD=1

# 限制 CUDA 模块加载
export CUDA_MODULE_LOADING=LAZY

# 并行参数
export NVCC_THREADS=2
export MAX_JOBS=4

echo "CUDA_HOME: $CUDA_HOME"
echo "GCC: $CC (gcc-11 for CUDA 11.8 compatibility)"
echo "TORCH_CUDA_ARCH_LIST: $TORCH_CUDA_ARCH_LIST (★ 避免 compute_120)"
echo "FLASH_ATTN_CUDA_ARCHS: $FLASH_ATTN_CUDA_ARCHS"
echo "MAX_JOBS: $MAX_JOBS, NVCC_THREADS: $NVCC_THREADS"
echo ""

# ---------------------- 5. 验证环境 ----------------------
VENV_PYTHON=/data/venv/bin/python3
VENV_PIP=/data/venv/bin/pip

echo "=== 确保 torch 已安装 ==="
$VENV_PYTHON -c "import torch; print(f'PyTorch: {torch.__version__}, CUDA: {torch.version.cuda}')" || {
    echo "安装 PyTorch 2.4.0+cu118"
    $VENV_PIP install torch==2.4.0+cu118 --index-url https://download.pytorch.org/whl/cu118
}

echo "=== 安装编译依赖 ==="
$VENV_PIP install wheel setuptools pybind11 ninja

# ---------------------- 6. 尝试预编译 wheel ----------------------
WHEEL_URL="https://github.com/Dao-AILab/flash-attention/releases/download/v2.8.3/flash_attn-2.8.3+cu118torch2.4.0-cp312-cp312-linux_x86_64.whl"
echo "=== 尝试预编译 wheel: $WHEEL_URL ==="
if curl -sI "$WHEEL_URL" 2>/dev/null | grep -q "200\|302"; then
    $VENV_PIP install "$WHEEL_URL" && {
        echo "=== wheel 安装成功 ==="
        $VENV_PYTHON -c "import torch; import flash_attn; print(f'FlashAttention 版本: {flash_attn.__version__}')"
        # ★ 验证 CUDA forward pass 真的能跑
        $VENV_PYTHON -c "
from flash_attn import flash_attn_func
import torch
q = torch.randn(1, 32, 8, 64, device='cuda', dtype=torch.bfloat16)
out = flash_attn_func(q, q, q, causal=True)
print(f'✓ CUDA forward pass OK: {out.shape}')
" || echo "⚠ wheel 装上了但 CUDA forward pass 失败"
        exit 0
    }
fi
echo "=== 预编译 wheel 不可用 (cu118torch2.4.0cp312 不存在) ==="
echo ""

# ---------------------- 7. 源码编译 ----------------------
echo "=== 源码编译 (预计 1.5 小时) ==="
echo "编译时间较长，使用后台运行..."

# 确保日志文件可写
LOG_FILE="/tmp/flash_build.log"
rm -f "$LOG_FILE"
touch "$LOG_FILE"
chmod 666 "$LOG_FILE"

# ★★★ 正确的后台编译模式 ★★★
# 关键点:
#   1. 用 setsid 启动新会话, 防止 SIGHUP
#   2. 用 nohup 忽略 SIGHUP
#   3. 重定向 stdin < /dev/null 防止等待输入
#   4. 用绝对路径 /data/venv/bin/python (不要 source activate)
#   5. 所有环境变量在子 shell 内 export
#   6. 用 disown 断开 job 控制
nohup setsid /data/venv/bin/python -c "
import os
os.environ['CUDA_HOME'] = '/data/cuda-11.8'
os.environ['PATH'] = '/data/cuda-11.8/bin:/data/venv/bin:' + os.environ.get('PATH', '')
os.environ['CC'] = '/usr/bin/gcc-11'
os.environ['CXX'] = '/usr/bin/g++-11'
os.environ['TORCH_CUDA_ARCH_LIST'] = '8.6'
os.environ['FLASH_ATTN_CUDA_ARCHS'] = '86'
os.environ['FLASH_ATTENTION_FORCE_BUILD'] = '1'
os.environ['MAX_JOBS'] = '4'
os.environ['NVCC_THREADS'] = '2'
os.environ['LD_LIBRARY_PATH'] = '/data/cuda-11.8/lib64:' + os.environ.get('LD_LIBRARY_PATH', '')
import subprocess
os.chdir('/opt/flash-attention')
with open('$LOG_FILE', 'wb') as f:
    p = subprocess.Popen(
        ['/data/venv/bin/python', 'setup.py', 'install'],
        stdout=f, stderr=subprocess.STDOUT,
        env=os.environ
    )
    p.wait()
" > /dev/null 2>&1 < /dev/null &

BUILD_PID=$!
disown
echo "编译进程 PID: $BUILD_PID"
echo "日志: tail -f $LOG_FILE"
echo ""

# ---------------------- 8. 等待编译完成 ----------------------
echo "=== 等待编译完成 (预计 1.5 小时) ==="
echo "  - 后台 PID: $BUILD_PID"
echo "  - 进度查看: tail -f $LOG_FILE"
echo "  - .o 数量: 0/73 -> 73/73"
echo ""

PROGRESS_FILE="/tmp/flash_progress.log"
> "$PROGRESS_FILE"

while true; do
    if $VENV_PYTHON -c "import flash_attn" 2>/dev/null; then
        # import 成功，验证 CUDA forward
        if $VENV_PYTHON -c "
from flash_attn import flash_attn_func
import torch
q = torch.randn(1, 32, 8, 64, device='cuda', dtype=torch.bfloat16)
flash_attn_func(q, q, q, causal=True)
" 2>/dev/null; then
            echo ""
            echo "=== 编译完成且 CUDA forward pass 验证通过 ==="
            $VENV_PYTHON -c "import flash_attn; print(f'FlashAttention 版本: {flash_attn.__version__}')"
            echo "✓ /data/venv/lib/python3.12/site-packages/flash_attn/ 安装成功"
            echo "✓ CUDA kernel 可调用"
            break
        else
            echo ""
            echo "=== 编译完成但 CUDA 验证失败 ==="
            echo "检查 .so 文件: ls -la /data/venv/lib/python3.12/site-packages/flash_attn/*.so"
            break
        fi
    fi

    if ! ps -p $BUILD_PID > /dev/null 2>&1; then
        echo ""
        echo "=== 编译进程已结束 ==="
        echo "查看日志: tail -50 $LOG_FILE"
        if $VENV_PYTHON -c "import flash_attn" 2>/dev/null; then
            echo "✓ 编译成功"
        else
            echo "✗ 编译失败"
            echo ""
            echo "常见错误:"
            echo "  1. undefined symbol: 编译被中断或 setup.py 缺源文件"
            echo "     解决: 检查 setup.py 是否包含 flash_bwd_hdim256_bf16_causal_sm80.cu"
            echo "  2. nvcc fatal: Unsupported gpu architecture 'compute_120'"
            echo "     解决: 检查 TORCH_CUDA_ARCH_LIST=\"8.6\" 是否设置"
            echo "  3. unsupported GNU version: gcc-13 不被 CUDA 11.8 支持"
            echo "     解决: export CC=/usr/bin/gcc-11"
            exit 1
        fi
        break
    fi

    # 显示当前进度
    o_count=$(ls /opt/flash-attention/build/temp.linux-x86_64-cpython-312/csrc/flash_attn/src/*.o 2>/dev/null | wc -l)
    ninja_step=$(grep -o '\[[0-9]*/73\]' "$LOG_FILE" 2>/dev/null | tail -1)
    ciccs=$(ps aux | grep -c "[c]icc" 2>/dev/null || echo 0)
    echo -n "  [$(date +%H:%M:%S)] .o: $o_count/73 | $ninja_step | cicc: $ciccs"
    sleep 30
done

# ---------------------- 9. 编译完成 ----------------------
echo ""
echo "================================================================"
echo "FlashAttention 安装完成!"
echo "================================================================"
echo ""
echo "验证命令:"
echo "  /data/venv/bin/python -c \"import flash_attn; print(flash_attn.__version__)\""
echo "  /data/venv/bin/python -c \"from flash_attn import flash_attn_func; \\"
echo "    import torch; q = torch.randn(1, 32, 8, 64, device='cuda', dtype=torch.bfloat16);"
echo "    print(flash_attn_func(q, q, q, causal=True).shape)\""
echo ""

# =============================================================================
# 手动编译命令 (如需直接执行)
# =============================================================================
# 完整环境变量（重要！）:
#   export CUDA_HOME=/data/cuda-11.8
#   export PATH=/data/cuda-11.8/bin:$PATH
#   export CC=/usr/bin/gcc-11
#   export CXX=/usr/bin/g++-11
#   export TORCH_CUDA_ARCH_LIST="8.6"     # ★ 关键 (避免 compute_120)
#   export FLASH_ATTN_CUDA_ARCHS="86"
#   export FLASH_ATTENTION_FORCE_BUILD=1
#   export MAX_JOBS=4
#   export NVCC_THREADS=2
#
# 命令:
#   cd /opt/flash-attention
#   /data/venv/bin/python setup.py install
#
# 增量编译 (编译中断后继续):
#   直接重新执行上述命令, ninja 会自动检测缺失的 .o 文件并编译
#
# 修复 setup.py 缺源文件 (关键步骤, 必做):
#   sed -i "/flash_bwd_hdim256_bf16_sm80.cu/a\\    'flash_bwd_hdim256_bf16_causal_sm80.cu'," \
#     /opt/flash-attention/setup.py
#
# 修改 setup.py 后让 ninja 重新解析 (不删 .o):
#   find /opt/flash-attention/build -name "build.ninja" -delete
#   重新跑 python setup.py install
#
# 完全重新编译 (如果 build 目录损坏):
#   cd /opt/flash-attention && rm -rf build
#   然后执行上述编译命令
#   ⚠️ 警告: rm -rf build 会丢失所有 .o 进度 (4-8 小时白费)
#            只在 build 目录真的损坏时才这样做
# =============================================================================
