#!/bin/bash
set -e

echo "=== 设置 CosyVoice 环境 (语音合成 TTS) ==="

# 1. 克隆源码
if [ ! -d "$HOME/CosyVoice" ]; then
  echo "克隆 CosyVoice 源码..."
  git clone --recursive https://github.com/FunAudioLLM/CosyVoice.git $HOME/CosyVoice
fi
cd $HOME/CosyVoice

if [ -d ".git" ]; then
  echo "更新源码..."
  git pull
  git submodule update --init --recursive
fi

# 2. 安装系统依赖 (FFmpeg required for torchcodec)
echo "安装 FFmpeg 系统依赖..."
sudo apt update && sudo apt install -y ffmpeg

# 3. 创建 conda 环境
echo "创建 cosyvoice conda 环境..."
eval "$($HOME/anaconda3/bin/conda shell.bash hook)"
conda create -n cosyvoice -y python=3.10

# 4. 安装所有 Python 依赖 (一次性安装)
echo "安装 Python 依赖..."
conda activate cosyvoice
pip install --upgrade pip -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host=mirrors.aliyun.com

# Matcha-TTS 依赖
pip install -r third_party/Matcha-TTS/requirements.txt \
  -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host=mirrors.aliyun.com

# CosyVoice 核心依赖 (一次性安装所有包)
pip install \
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
  torchmetrics \
  -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host=mirrors.aliyun.com

# 5. 下载模型
echo "下载预训练模型..."
mkdir -p pretrained_models
pip install modelscope -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host=mirrors.aliyun.com
python -c "
from modelscope import snapshot_download
snapshot_download('FunAudioLLM/Fun-CosyVoice3-0.5B-2512', local_dir='pretrained_models/Fun-CosyVoice3-0.5B')
"

echo "=== CosyVoice 环境设置完成 ==="
echo ""
echo "激活环境:"
echo "  conda activate cosyvoice"
echo ""
echo "运行测试:"
echo "  cd ~/CosyVoice"
echo "  bash ~/my-shell/test_cosyvoice.sh"
echo ""
echo "运行 webui:"
echo "  cd ~/CosyVoice"
echo "  python webui.py --port 50000 --model_dir pretrained_models/Fun-CosyVoice3-0.5B"
