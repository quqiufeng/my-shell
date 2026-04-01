#!/bin/bash

# KoboldCpp 启动脚本 - Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled
# 使用 koboldcpp 框架，比 llama.cpp 更省内存

MODEL_DIR="/opt/image/Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled/Qwen3.5-9B.Q4_K_M.gguf"
KOBOLDCPP_DIR="/opt/koboldcpp"

export LD_LIBRARY_PATH=/usr/lib/wsl/lib:$LD_LIBRARY_PATH

echo "=============================="
echo "启动 Qwen3.5-9B-Claude (KoboldCpp)"
echo "地址: http://0.0.0.0:11434"
echo "模型: Qwen3.5-9B.Q4_K_M.gguf"
echo "框架: KoboldCpp (比 llama.cpp 更省内存)"
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

cd "$KOBOLDCPP_DIR"

python koboldcpp.py \
  --model "$MODEL_DIR" \
  --port 11434 \
  --host 0.0.0.0 \
  --gpulayers 35 \
  --contextsize 65536 \
  --flashattention \
  --quiet

# 参数说明:
# --gpulayers 35: GPU 层数
# --contextsize 65536: 上下文长度 (64K)
# --flashattention: 启用 Flash Attention
# --quiet: 减少日志输出
