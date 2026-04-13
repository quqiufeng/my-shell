#!/bin/bash
#
# =============================================================
# Qwen3.5-9B (llama.cpp) API 启动脚本 (4090D 24GB) - 优化版
# =============================================================
#
# 【性能数据】(4090D 24GB, 64K上下文, Q4_K_M模型)
#   速度: ~95-100 tokens/s
#   测试命令: python3 test_api.py
#   测试结果: 约95-100 tok/s (高难度算法题)
# =============================================================
#
# 【启动方式】
#   cd /opt/my-shell/4090d
#   nohup ./run_qwen3.5-9b_llama.sh > /tmp/9b_llama.log 2>&1 &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/9b_llama.log
#
# 【停止服务】
#   pkill -f llama-server
#
# 【测试API】
#   curl http://localhost:11434/v1/models
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "Qwopus3.5-9B-v3.Q4_K_M.gguf", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'
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
#   "model": "openai/Qwopus3.5-9B-v3.Q4_K_M.gguf",
#   "provider": {
#     "openai": {
#       "npm": "@ai-sdk/openai-compatible",
#       "name": "Local Models",
#       "options": {
#         "baseURL": "http://localhost:11434/v1",
#         "apiKey": "dummy"
#       },
#       "models": {
#         "Qwopus3.5-9B-v3.Q4_K_M.gguf": {
#           "name": "Qwen3.5-9B-llama.cpp Q4 (4090D)",
#           "maxContextWindow": 65536,
#           "maxOutputTokens": 32768
#         }
#       }
#     }
#   }
# }
#
# 【使用 opencode】
#   opencode -m openai/Qwopus3.5-9B-v3.Q4_K_M.gguf
#
# =============================================================

export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/root/miniconda3/pkgs/libstdcxx-15.2.0-h39759b7_7/lib:/usr/lib/wsl/lib:$LD_LIBRARY_PATH

# 4090D 24GB 显存优化参数
MODEL_DIR="/opt/gguf/Qwopus3.5-9B-v3.Q4_K_M.gguf"
LLAMA_SERVER="/root/llama.cpp/build/bin/llama-server"

# 4090D 可以支持更大的上下文和 batch size
NGL=99              # GPU层数 (全部加载到GPU)
CTX=65536           # 上下文 64K (4090D 24GB 支持)
BATCH=2048          # batch size (更大)
UBATCH=2048         # micro batch size
THREADS=16          # CPU线程数 (4090D有更多核心)

PORT=11434

echo "=============================="
echo "启动 Qwen3.5-9B Q4_K_M (llama.cpp) API 服务"
echo "地址: http://0.0.0.0:$PORT"
echo "模型: Qwopus3.5-9B-v3.Q4_K_M.gguf"
echo "上下文: $CTX"
echo "GPU层数: $NGL"
echo "Batch Size: $BATCH"
echo "uBatch Size: $UBATCH"
echo "Threads: $THREADS"
echo "目标: 95-100 tok/s"
echo "=============================="
echo ""

$LLAMA_SERVER \
  -m "$MODEL_DIR" \
  --host 0.0.0.0 \
  --port $PORT \
  -ngl $NGL \
  -c $CTX \
  --batch-size $BATCH \
  --ubatch-size $UBATCH \
  --flash-attn on \
  --threads $THREADS \
  --threads-batch $THREADS \
  --no-mmap \
  --mlock \
  --temp 0.6 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.00 \
  --cache-type-k f16 \
  --cache-type-v f16 \
  --metrics

# 注意: 使用模型内置的chat template，不指定自定义模板
