#!/bin/bash
set -e

echo "=== 编译安装 exllamav2 (使用 /opt/cuda 编译器) ==="

cd /opt

# 1. 克隆源码
if [ ! -d "exllamav2" ]; then
  echo "克隆 exllamav2 源码..."
  git clone https://github.com/turboderp/exllamav2.git
else
  echo "更新源码..."
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
rm -rf build

# 4. 设置 CUDA 编译器并编译
echo "编译 exllamav2..."
export CUDA_HOME=/usr/lib/nvidia-cuda-toolkit
export CUDA_ARCHITECTURES=86
export TORCH_CUDA_ARCH_LIST="8.6"
export MAKEFLAGS="-j2"
/home/dministrator/anaconda3/envs/dl/bin/python setup.py build

# 5. 安装
echo "安装 exllamav2..."
/home/dministrator/anaconda3/envs/dl/bin/pip install .

echo "=== exllamav2 安装完成 ==="
