#!/bin/bash
set -e
# =============================================================================
# CosyVoice 环境设置脚本 (语音合成 TTS)
#
# 模型文件目录: /data/models/
#   所有预训练模型下载到此目录, 包含:
#     - Fun-CosyVoice3-0.5B  (最新版, 0.5B 参数, 推荐)
#     - CosyVoice-300M       (通用版, 300M 参数)
#     - CosyVoice-300M-SFT   (SFT 微调版)
#     - CosyVoice-300M-Instruct (指令版)
#     - CosyVoice-ttsfrd     (发音资源包)
#
# 模型下载方式:
#   from modelscope import snapshot_download
#   snapshot_download('FunAudioLLM/Fun-CosyVoice3-0.5B-2512',
#                     local_dir='/data/models/Fun-CosyVoice3-0.5B')
#   snapshot_download('iic/CosyVoice-300M-SFT',
#                     local_dir='/data/models/CosyVoice-300M-SFT')
#   snapshot_download('iic/CosyVoice-300M-Instruct',
#                     local_dir='/data/models/CosyVoice-300M-Instruct')
#   snapshot_download('iic/CosyVoice-300M',
#                     local_dir='/data/models/CosyVoice-300M')
#   snapshot_download('iic/CosyVoice-ttsfrd',
#                     local_dir='/data/models/CosyVoice-ttsfrd')
#
# 也可用 git lfs 从 HuggingFace 下载:
#   git clone https://huggingface.co/FunAudioLLM/CosyVoice-300M-SFT
#   git clone https://huggingface.co/FunAudioLLM/CosyVoice-300M-Instruct
#   git clone https://huggingface.co/FunAudioLLM/CosyVoice-300M
#
# 运行 WebUI:
#   /data/venv/bin/python3 webui.py --port 50000 \
#     --model_dir /data/models/Fun-CosyVoice3-0.5B
# =============================================================================

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

# 确保子模块初始化
git submodule update --init --recursive

# 2. 安装系统依赖 (FFmpeg required for torchcodec)
echo "安装 FFmpeg 系统依赖..."
sudo DEBIAN_FRONTEND=noninteractive apt update && sudo DEBIAN_FRONTEND=noninteractive apt install -y ffmpeg

# 3. 安装所有 Python 依赖
echo "安装 Python 依赖..."
$VENV_PIP install --upgrade pip

# Matcha-TTS 依赖
$VENV_PIP install -r third_party/Matcha-TTS/requirements.txt

# CosyVoice 核心依赖 (torchaudio 必须 pin 到 2.9.x 匹配 torch 2.9.0)
$VENV_PIP install \
  hyperpyyaml \
  onnxruntime \
  openai-whisper \
  transformers \
  x-transformers \
  pyarrow \
  pyworld \
  torchcodec \
  pytorch-lightning \
  torchmetrics

$VENV_PIP install torchaudio==2.9.0 --index-url https://download.pytorch.org/whl/cu126

# 4. 下载模型到 /data/models (若已存在则跳过)
echo "下载预训练模型到 /data/models..."
# 模型文件目录
mkdir -p /data/models
$VENV_PIP install modelscope
$VENV_PYTHON -c "
from modelscope import snapshot_download
import os
models = [
    ('FunAudioLLM/Fun-CosyVoice3-0.5B-2512', '/data/models/Fun-CosyVoice3-0.5B'),
    ('iic/CosyVoice-300M-SFT', '/data/models/CosyVoice-300M-SFT'),
    ('iic/CosyVoice-300M-Instruct', '/data/models/CosyVoice-300M-Instruct'),
    ('iic/CosyVoice-300M', '/data/models/CosyVoice-300M'),
    ('iic/CosyVoice-ttsfrd', '/data/models/CosyVoice-ttsfrd'),
]
for repo, local in models:
    if not os.path.exists(local):
        print(f'下载 {repo}...')
        snapshot_download(repo, local_dir=local)
    else:
        print(f'已存在: {local}')
"

echo "=== CosyVoice 环境设置完成 ==="
echo ""
echo "运行 webui:"
echo "  cd $COSY_DIR"
# 模型文件目录
echo "  $VENV_PYTHON webui.py --port 50000 --model_dir /data/models/Fun-CosyVoice3-0.5B"
