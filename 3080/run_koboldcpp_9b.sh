#!/bin/bash

MODEL_DIR="/opt/image/Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled/Qwen3.5-9B.Q4_K_M.gguf"
KOBOLDCPP="/opt/koboldcpp/koboldcpp_cublas.so"

export LD_LIBRARY_PATH=/usr/lib/wsl/lib:$LD_LIBRARY_PATH

echo "=============================="
echo "启动 Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled API 服务 (KoboldCpp)"
echo "地址: http://0.0.0.0:11434"
echo "模型: Qwen3.5-9B-Q4_K_M.gguf"
echo "上下文: 64K"
echo "GPU层数: 35"
echo "=============================="

python /opt/koboldcpp/koboldcpp.py \
  "$MODEL_DIR" \
  11434 \
  --contextsize 65536 \
  --gpulayers 35 \
  --threads 12 \
  --batchsize 256 \
  --flashattention
