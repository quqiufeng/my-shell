#!/bin/bash
# =============================================================================
# exllamav2 编译脚本 - RTX 3080 (CUDA 8.6 / sm_86)
# =============================================================================
#
# 【编译注意事项 / 踩坑记录】
#
# 1. PyTorch CUDA 版本 vs 系统 nvcc 版本必须匹配
#    - PyTorch: CUDA 12.1 (cu121) - 来自 pip 安装的 torch 2.4.1+cu121
#    - 系统 CUDA: /usr/lib/nvidia-cuda-toolkit 是 CUDA 12.0 版本 (PyTorch 12.1 兼容)
#    - /usr/local/cuda (默认) 是 CUDA 11.8，不能用！会导致 _Float32 错误
#
# 2. 正确的编译环境变量
#    - CUDA_HOME=/usr/lib/nvidia-cuda-toolkit  (CUDA 12 路径)
#    - PATH=/usr/lib/nvidia-cuda-toolkit/bin:$PATH  (使用 CUDA 12 的 nvcc)
#    - CUDA_ARCHITECTURES=86  (RTX 3080 的 compute capability)
#
# 3. 常见错误
#    - "unsupported GNU version! gcc versions later than 11" → 使用 --allow-unsupported-compiler
#    - "_Float32 not declared" → 用错了 CUDA 11.8 的 nvcc，需用 CUDA 12 的
#    - JIT 编译卡住 → 清理 ~/.cache/torch_extensions 和 site-packages 下的 .so
#
# 4. 清理旧编译
#    - rm -rf ~/.cache/torch_extensions/exllamav2_ext
#    - rm -f site-packages/exllamav2/*.so
#    - rm -rf build/ exllamav2.egg-info/
#
# =============================================================================

set -e

echo "=== 编译安装 exllamav2 (RTX 3080) ==="

cd /opt

# 1. 克隆源码
if [ ! -d "exllamav2" ]; then
  echo "克隆 exllamav2 源码..."
  git clone https://github.com/turboderp/exllamav2.git
else
  echo "使用已有源码..."
  cd exllamav2
  git pull
  cd ..
fi

# 2. 安装依赖
echo "安装 Python 依赖..."
cd /opt/exllamav2
/home/dministrator/anaconda3/envs/dl/bin/pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host=mirrors.aliyun.com

# 3. 清理旧的 build
echo "清理旧的 build..."
rm -rf build exllamav2.egg-info
rm -f /home/dministrator/anaconda3/envs/dl/lib/python3.10/site-packages/exllamav2/*.so
rm -rf ~/.cache/torch_extensions/exllamav2_ext 2>/dev/null || true

# 4. 设置 CUDA 12 编译器并编译
# PyTorch 使用 CUDA 12.1, 需要用 CUDA 12 版本的 nvcc
# 注意: CUDA_HOME 必须指向 CUDA 12, 不能用 /usr (那是 CUDA 11.8)
echo "编译 exllamav2 (CUDA 12.0, sm_86)..."
export CUDA_HOME=/usr/lib/nvidia-cuda-toolkit
export PATH=/usr/lib/nvidia-cuda-toolkit/bin:$PATH
export CUDA_ARCHITECTURES=86
export TORCH_CUDA_ARCH_LIST="8.6"
export MAKEFLAGS="-j2"
/home/dministrator/anaconda3/envs/dl/bin/python setup.py build

# 5. 安装
echo "安装 exllamav2..."
/home/dministrator/anaconda3/envs/dl/bin/pip install .

# 6. 复制编译好的 .so 文件到 site-packages (关键步骤: pip install 不会自动复制)
# 并修复权限问题
echo "复制编译好的 .so 文件..."
if [ -f "build/lib.linux-x86_64-cpython-310/exllamav2_ext.cpython-310-x86_64-linux-gnu.so" ]; then
    cp build/lib.linux-x86_64-cpython-310/exllamav2_ext.cpython-310-x86_64-linux-gnu.so /home/dministrator/anaconda3/envs/dl/lib/python3.10/site-packages/exllamav2/
    chown dministrator:dministrator /home/dministrator/anaconda3/envs/dl/lib/python3.10/site-packages/exllamav2/*.so
    echo "✓ .so 文件已复制到 site-packages 并修复权限"
else
    echo "✗ 未找到编译好的 .so 文件"
    exit 1
fi

echo "=== exllamav2 安装完成 ==="
echo ""
echo "测试导入 (CUDA 12 编译, sm_86):"
/home/dministrator/anaconda3/envs/dl/bin/python -c "from exllamav2.model import ExLlamaV2; print('OK')"
