#!/bin/bash
set -e

echo "=== 设置 CosyVoice 环境 (语音合成 TTS) ==="
echo "虚拟环境: /data/venv (Python 3.12, torch 2.9.0+cu126)"

export CC=/usr/bin/gcc-12
export CXX=/usr/bin/g++-12

VENV_PYTHON=/data/venv/bin/python3
VENV_PIP=/data/venv/bin/pip

# 1. 克隆源码
COSY_DIR=/opt/CosyVoice
if [ ! -d "$COSY_DIR" ]; then
  echo "克隆 CosyVoice 源码..."
  git clone --recursive https://github.com/FunAudioLLM/CosyVoice.git "$COSY_DIR"
fi
cd "$COSY_DIR"

if [ -d ".git" ]; then
  echo "更新源码..."
  git pull
  git submodule update --init --recursive
fi

# 2. 安装系统依赖 (FFmpeg required for torchcodec)
echo "安装 FFmpeg 系统依赖..."
sudo apt update && sudo apt install -y ffmpeg

# 3. 安装所有 Python 依赖
echo "安装 Python 依赖..."
$VENV_PIP install --upgrade pip

# Matcha-TTS 依赖
$VENV_PIP install -r third_party/Matcha-TTS/requirements.txt

# CosyVoice 核心依赖
$VENV_PIP install \
  hyperpyyaml \
  onnxruntime \
  openai-whisper \
  transformers \
  x-transformers \
  pyarrow \
  pyworld \
  torchcodec \
  torchaudio \
  pytorch-lightning \
  torchmetrics

# 4. 下载模型到 /opt/image
echo "下载预训练模型到 /opt/image..."
mkdir -p /opt/image
$VENV_PIP install modelscope
$VENV_PYTHON -c "
from modelscope import snapshot_download
snapshot_download('FunAudioLLM/Fun-CosyVoice3-0.5B-2512', local_dir='/opt/image/Fun-CosyVoice3-0.5B')
"
$VENV_PYTHON -c "
from modelscope import snapshot_download
snapshot_download('FunAudioLLM/CosyVoice-300M-SFT', local_dir='/opt/image/CosyVoice-300M-SFT')
"

echo "=== CosyVoice 环境设置完成 ==="
echo ""
echo "运行 webui:"
echo "  cd $COSY_DIR"
echo "  $VENV_PYTHON webui.py --port 50000 --model_dir /opt/image/Fun-CosyVoice3-0.5B"
