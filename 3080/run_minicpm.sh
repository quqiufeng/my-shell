#!/bin/bash

MODEL_DIR="/opt/image/Model-7.6B-Q4_K_M.gguf"
MMPRJ_DIR="/opt/image/mmproj-model-f16.gguf"
LLAMA_SERVER="$HOME/llama.cpp/build/bin/llama-server"

export LD_LIBRARY_PATH=/usr/lib/wsl/lib:$LD_LIBRARY_PATH

echo "=============================="
echo "启动 MiniCPM-o 2.6 API 服务 (3080 10GB)"
echo "地址: http://0.0.0.0:11434"
echo "模型: Model-7.6B-Q4_K_M.gguf"
echo "视觉组件: mmproj-model-f16.gguf"
echo "GPU层数: 99 (全部到GPU)"
echo "上下文: 8192"
echo "Flash Attention: on"
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
  --mmproj "$MMPRJ_DIR" \
  --host 0.0.0.0 \
  --port 11434 \
  -ngl 99 \
  -c 8192 \
  --batch-size 256 \
  --flash-attn on \
  --threads 12 \
  --parallel 1 \
  --n-predict 4096
