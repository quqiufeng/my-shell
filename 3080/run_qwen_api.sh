#!/bin/bash

MODEL_DIR="$HOME/Qwen3.5-9B-Q6_K.gguf"
LLAMA_SERVER="$HOME/llama.cpp/build/bin/llama-server"

export LD_LIBRARY_PATH=/usr/lib/wsl/lib:$LD_LIBRARY_PATH

echo "=============================="
echo "启动 Qwen3.5-9B API 服务 (3080 10GB 优化版)"
echo "地址: http://0.0.0.0:11434"
echo "上下文: 20480"
echo "GPU层数: 40"
echo "Batch Size: 512"
echo "Flash Attention: on"
echo "KV Cache: q4_0"
echo "Threads: 14"
echo "=============================="
echo ""
echo "⚠️ Windows 端口转发命令 (在 Windows PowerShell 管理员运行):"
echo "# 删除旧转发:"
echo "netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=11434"
echo ""
echo "# 添加新转发 (转发到 WSL2):"
echo "netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=11434 connectaddress=172.23.212.172 connectport=11434"
echo ""
echo "# 查看转发状态:"
echo "netsh interface portproxy show all"
echo "=============================="
echo ""

$LLAMA_SERVER \
  -m "$MODEL_DIR" \
  --host 0.0.0.0 \
  --port 11434 \
  -ngl 40 \
  -c 20480 \
  --batch-size 512 \
  --flash-attn on \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --threads 14 \
  --log-disable &
