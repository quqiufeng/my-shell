#!/bin/bash
# =============================================================================
# exllamav3 编译脚本 - RTX 3080 (sm_86), CUDA 12.6
# 虚拟环境: /data/venv (Python 3.12, torch 2.9.0+cu126)
# =============================================================================

set -e

echo "=== 编译安装 exllamav3 (RTX 3080, CUDA 12.6) ==="

VENV_PYTHON=/data/venv/bin/python3
VENV_PIP=/data/venv/bin/pip
EXLLAMA_DIR=/opt/exllamav3

# 1. 克隆源码
if [ ! -d "$EXLLAMA_DIR" ]; then
  echo "克隆 exllamav3 源码..."
  git clone https://github.com/turboderp-org/exllamav3.git "$EXLLAMA_DIR"
fi

cd "$EXLLAMA_DIR"
git pull

# 2. 安装依赖
echo "安装 Python 依赖..."
$VENV_PIP install -r requirements.txt

# 3. 清理旧的 build
echo "清理旧的 build..."
rm -rf build exllamav3.egg-info

# 4. 设置编译环境并编译
echo "编译 exllamav3 (CUDA 12.6, sm_86)..."
export CUDA_HOME=/data/cuda
export PATH=/data/cuda/bin:/data/venv/bin:$PATH
export CC=/usr/bin/gcc-12
export CXX=/usr/bin/g++-12
export CUDA_ARCHITECTURES=86
export TORCH_CUDA_ARCH_LIST="8.6"
export NVCCFLAGS="-gencode arch=compute_86,code=sm_86"
export MAKEFLAGS="-j$(nproc)"
$VENV_PYTHON setup.py build

# 5. 安装
echo "安装 exllamav3..."
$VENV_PIP install .

echo "=== exllamav3 安装完成 ==="
echo ""
echo "测试导入:"
$VENV_PYTHON -c "from exllamav3.model import ExLlamaV3; print('OK')"
