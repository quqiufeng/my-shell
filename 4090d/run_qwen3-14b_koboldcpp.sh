#!/bin/bash
#
# =============================================================
# Qwen3-14B (KoboldCpp) API 启动脚本 (4090D 24GB)
# =============================================================
#
# 【启动方式】
#   cd /opt/my-shell/4090d
#   nohup ./run_qwen3-14b_koboldcpp.sh > /tmp/14b_koboldcpp.log 2>&1 &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/14b_koboldcpp.log
#
# 【停止服务】
#   pkill -f koboldcpp.py
#
# 【测试API】
#   curl http://localhost:11434/v1/models
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "Qwen3-14B-Q4_K_M.gguf", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'
#
# 【性能测试】
#   cd /opt/my-shell
#   python3 test_api.py
#
# =============================================================
# OpenCode 配置文件 (~/.config/opencode/opencode.json)
# =============================================================
# {
#   "$schema": "https://opencode.ai/config.json",
#   "model": "openai/Qwen3-14B-Q4_K_M.gguf",
#   "provider": {
#     "openai": {
#       "npm": "@ai-sdk/openai-compatible",
#       "name": "Local Models",
#       "options": {
#         "baseURL": "http://localhost:11434/v1",
#         "apiKey": "dummy"
#       },
#       "models": {
#         "Qwen3-14B-Q4_K_M.gguf": {
#           "name": "Qwen3-14B-KoboldCpp Q4 (4090D)",
#           "maxContextWindow": 131072,
#           "maxOutputTokens": 32768
#         }
#       }
#     }
#   }
# }
#
# 【使用 opencode】
#   opencode -m openai/Qwen3-14B-Q4_K_M.gguf
#
# =============================================================

export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/root/miniconda3/pkgs/libstdcxx-15.2.0-h39759b7_7/lib:/usr/lib/wsl/lib:$LD_LIBRARY_PATH

MODEL_DIR="/opt/gguf/Qwen3-14B-Q4_K_M.gguf"
KOBOLDCPP_DIR="/opt/koboldcpp"

echo "=============================="
echo "启动 Qwen3-14B Q4_K_M (KoboldCpp) API 服务"
echo "地址: http://0.0.0.0:11434"
echo "上下文: 128K (131072)"
echo "GPU层数: 99"
echo "Flash Attention: on"
echo "Jinja模板: 自动检测 (qwen3)"
echo "=============================="

cd "$KOBOLDCPP_DIR"

python koboldcpp.py \
  --model "$MODEL_DIR" \
  --port 11434 \
  --host 0.0.0.0 \
  --gpulayers 99 \
  --contextsize 131072 \
  --flashattention \
  --quiet \
  --jinja \
  --chat-template-kwargs '{"enable_thinking":false}' &

sleep 10

INSTANCE_ID=${XGC_INSTANCE_ID:-$(hostname)}

echo ""
echo "=============================="
echo "服务已启动!"
echo "=============================="
echo "对内地址: http://localhost:11434"
echo "对外地址: http://${INSTANCE_ID}-11434.container.x-gpu.com/v1/"
echo "=============================="
echo ""
echo "调试命令:"
echo "curl -s http://localhost:11434/v1/chat/completions \\"
echo '  -H "Content-Type: application/json" \'
echo '  -d '"'"'{"model": "Qwen3-14B-Q4_K_M.gguf", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'"'"''
echo ""
echo "性能参数:"
echo "  模型: Qwen3-14B-Q4_K_M.gguf"
echo "  框架: KoboldCpp"
echo "  上下文: 128K"
echo "  最大输出: 32K"
echo "  GPU层数: 99"
echo "  Flash Attention: on"
echo "  Chat模板: jinja自动检测 (qwen3)"
echo "  思考模式: 关闭 (enable_thinking=false)"
