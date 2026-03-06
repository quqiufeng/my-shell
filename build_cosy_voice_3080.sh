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

# 3. 创建 conda 环境并激活
echo "创建 cosyvoice conda 环境..."
eval "$($HOME/anaconda3/bin/conda shell.bash hook)"
conda create -n cosyvoice -y python=3.10
conda activate cosyvoice

# 4. 安装所有 Python 依赖
echo "安装 Python 依赖..."
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

# 5. 安装 CUDA、cuDNN、TensorRT (语音加速)
echo "安装 CUDA 12.1..."
conda install -y cuda=12.1 -c nvidia

echo "安装 cuDNN 8.9..."
conda install -y cudnn=8.9 -c nvidia

echo "安装 TensorRT 8.6.1..."
pip install tensorrt==8.6.1 --no-build-isolation -i https://pypi.nvidia.com --trusted-host=pypi.nvidia.com

echo "编译 TensorRT 引擎 (加速推理)..."
python -c "
import sys
sys.path.append('third_party/Matcha-TTS')
from cosyvoice.cli.cosyvoice import AutoModel
AutoModel(model_dir='pretrained_models/CosyVoice-300M-SFT', load_jit=True, load_trt=True, fp16=True)
"

echo "编译 Fun-CosyVoice3-0.5B TensorRT 引擎 (v2声音克隆)..."
python -c "
import sys
sys.path.append('third_party/Matcha-TTS')
from cosyvoice.cli.cosyvoice import AutoModel
AutoModel(model_dir='pretrained_models/Fun-CosyVoice3-0.5B', load_trt=True, fp16=True)
"

# 5. 下载模型到 /opt/image
echo "下载预训练模型到 /opt/image..."
mkdir -p /opt/image
pip install modelscope -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host=mirrors.aliyun.com
python -c "
from modelscope import snapshot_download
snapshot_download('FunAudioLLM/Fun-CosyVoice3-0.5B-2512', local_dir='/opt/image/Fun-CosyVoice3-0.5B')
"
python -c "
from modelscope import snapshot_download
snapshot_download('FunAudioLLM/CosyVoice-300M-SFT', local_dir='/opt/image/CosyVoice-300M-SFT')
"

# 6. 编译 TensorRT 引擎 (加速推理)
echo "编译 CosyVoice-300M-SFT TensorRT 引擎..."
python -c "
import sys
sys.path.append('third_party/Matcha-TTS')
from cosyvoice.cli.cosyvoice import AutoModel
AutoModel(model_dir='/opt/image/CosyVoice-300M-SFT', load_jit=True, load_trt=True, fp16=True)
"

echo "编译 Fun-CosyVoice3-0.5B TensorRT 引擎..."
python -c "
import sys
sys.path.append('third_party/Matcha-TTS')
from cosyvoice.cli.cosyvoice import AutoModel
AutoModel(model_dir='/opt/image/Fun-CosyVoice3-0.5B', load_trt=True, fp16=True)
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
