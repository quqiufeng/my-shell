#!/bin/bash
#
# 【模型信息】
# 模型: Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled (GGUF Q4_K_M)
# 框架: KoboldCpp v1.111.1
# 显存占用: ~8GB (RTX 3080 10GB)
# 上下文: 128K (131072 tokens)
# KV量化: q4_0 (--quantkv 1)
#
# 【性能测试数据 - 30个高难度提示词】
# 平均速度: 62.2 tok/s
# 最快: 快速排序 64.8 tok/s
# 最慢: 贪心算法 55.8 tok/s
# 典型速度: 60-65 tok/s
# 总耗时: 494.07s / 30720 tokens
#
# 【OpenCode 配置】
# 配置文件路径: ~/.opencode/opencode.json
#
# ```json
# {
#   "$schema": "https://opencode.ai/config.json",
#   "model": "openai/Qwen3.5-9B.Q4_K_M.gguf",
#   "provider": {
#     "openai": {
#       "npm": "@ai-sdk/openai-compatible",
#       "name": "Local Models",
#       "options": {
#         "baseURL": "http://localhost:11434/v1",
#         "apiKey": "dummy"
#       },
#       "models": {
#         "Qwen3.5-9B.Q4_K_M.gguf": {
#           "name": "Qwen3.5-9B-KoboldCpp Q4 (本地3080)",
#           "maxContextWindow": 131072,
#           "maxOutputTokens": 4096
#         }
#       }
#     }
#   }
# }
# ```
#

MODEL_DIR="/opt/image/Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled/Qwen3.5-9B.Q4_K_M.gguf"
KOBOLDCPP_DIR="/opt/koboldcpp"
JINJA_TEMPLATE="/home/dministrator/my-shell/qwen35-chat-template-corrected.jinja"

export LD_LIBRARY_PATH=/usr/lib/wsl/lib:$LD_LIBRARY_PATH

echo "=============================="
echo "启动 Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled API 服务 (KoboldCpp)"
echo "地址: http://0.0.0.0:11434"
echo "模型: Qwen3.5-9B.Q4_K_M.gguf"
echo "上下文: 128K (131072 tokens)"
echo "GPU层数: 35"
echo "Flash Attention: on"
echo "Jinja 模板: qwen35-chat-template-corrected.jinja"
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
  --contextsize 131072 \
  --quantkv 1 \
  --flashattention \
  --quiet \
  --jinja \
  --chat-template "$JINJA_TEMPLATE" \
  --chat-template-kwargs '{"enable_thinking":false}'
