#!/bin/bash
set -e

echo "=== 设置 CosyVoice 环境 (语音合成 TTS) ==="

cd /opt

# 1. 克隆源码
if [ ! -d "CosyVoice" ]; then
  echo "克隆 CosyVoice 源码..."
  git clone --recursive https://github.com/FunAudioLLM/CosyVoice.git
  cd CosyVoice
  git submodule update --init --recursive
else
  echo "更新源码..."
  cd CosyVoice
  git pull
  git submodule update --init --recursive
fi

# 2. 创建 conda 环境
echo "创建 cosyvoice conda 环境..."
source ~/miniconda3/etc/profile
conda create -n cosyvoice -y python=3.10

# 3. 安装依赖
echo "安装 Python 依赖..."
source ~/miniconda3/bin/activate cosyvoice
pip install -r third_party/Matcha-TTS/requirements.txt -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host=mirrors.aliyun.com

# 核心依赖 (兼容版本)
pip install 'transformers>=4.30,<4.40' 'huggingface_hub>=0.20,<0.24' \
  x-transformers pyarrow pyworld torchcodec \
  -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host=mirrors.aliyun.com

# 4. 下载模型
echo "下载预训练模型..."
mkdir -p pretrained_models
pip install modelscope -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host=mirrors.aliyun.com
python -c "
from modelscope import snapshot_download
snapshot_download('FunAudioLLM/Fun-CosyVoice3-0.5B-2512', local_dir='pretrained_models/Fun-CosyVoice3-0.5B')
"

echo "=== CosyVoice 环境设置完成 ==="
echo ""
echo "使用方法 (推荐 Docker):"
echo "  docker run -d --gpus all -p 50000:50000 \\"
echo "    -v /opt/CosyVoice/pretrained_models:/workspace/pretrained_models \\"
echo "    ghcr.io/funaudio/cosyvoice:latest \\"
echo "    python webui.py --port 50000 --model_dir /workspace/pretrained_models/Fun-CosyVoice3-0.5B"
