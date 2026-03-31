#!/bin/bash
# =============================================================================
# exllamav2 编译脚本 - RTX 3080 (CUDA 8.6 / sm_86)
# =============================================================================
#
# 【编译注意事项 / 踩坑记录】
#
# 1. PyTorch CUDA 版本 vs 系统 nvcc 版本必须匹配
#    - PyTorch: CUDA 12.1 (cu121) - 来自 pip 安装的 torch 2.4.1+cu121
#    - 系统 nvcc: /usr/bin/nvcc 是 CUDA 12.0 版本
#    - /usr/local/cuda (默认) 是 CUDA 11.8，不能用！会导致 _Float32 错误
#
# 2. 正确的编译环境变量
#    - CUDA_HOME=/usr  (指向 /usr/include/cuda_runtime.h 等 CUDA 12 头文件)
#    - PATH=/usr/bin:$PATH  (让 nvcc 使用 /usr/bin/nvcc 而非 /usr/local/cuda/bin/nvcc)
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
echo "编译 exllamav2 (CUDA 12.0, sm_86)..."
export CUDA_HOME=/usr
export PATH=/usr/bin:$PATH
export CUDA_ARCHITECTURES=86
export TORCH_CUDA_ARCH_LIST="8.6"
export MAKEFLAGS="-j2"
/home/dministrator/anaconda3/envs/dl/bin/python setup.py build

# 5. 安装
echo "安装 exllamav2..."
/home/dministrator/anaconda3/envs/dl/bin/pip install .

echo "=== exllamav2 安装完成 ==="
echo ""
echo "测试导入:"
/home/dministrator/anaconda3/envs/dl/bin/python -c "from exllamav2.model import ExLlamaV2; print('OK')"
