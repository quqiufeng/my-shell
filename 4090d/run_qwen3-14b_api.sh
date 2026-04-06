#!/bin/bash
#
# =============================================================
# Qwen3-14B API 启动脚本 (4090D 24GB)
# =============================================================
#
# 【启动方式】
#   cd /opt/my-shell/4090d
#   nohup ./run_qwen3-14b_api.sh > /tmp/14b.log 2>&1 &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/14b.log
#
# 【停止服务】
#   killall -9 llama-server
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
#   "model": "llama.cpp/Qwen3-14B",
#   "provider": {
#     "llama.cpp": {
#       "npm": "@ai-sdk/openai-compatible",
#       "options": { "baseURL": "http://localhost:11434/v1" },
#       "models": {
#         "Qwen3-14B": {
#           "name": "Qwen3-14B-Q4_K_M.gguf",
#           "maxContextWindow": 131072,
#           "maxOutputTokens": 32768,
#           "options": { "num_ctx": 131072 }
#         }
#       }
#     }
#   }
# }
#
# 【使用 opencode】
#   opencode -m llama.cpp/Qwen3-14B
#
# 【性能数据】(4090D 24GB, 128K上下文)
#   ~88 tokens/s (q8_0 KV缓存)
#   测试命令: python3 test_api.py
#   测试结果: 约88 tok/s (30个高难度算法题)
#
# =============================================================

export LD_LIBRARY_PATH=/opt/llama.cpp/bin:/opt/llama.cpp/build/lib:$LD_LIBRARY_PATH
export GGML_CUDA_FORCE_MMQ=1
export GGML_CUDA_NO_VMM=1

MODEL_DIR="/opt/gguf/Qwen3-14B-Q4_K_M.gguf"
LLAMA_SERVER="/opt/llama.cpp/bin/llama-server"

echo "=============================="
echo "启动 Qwen3-14B API 服务"
echo "地址: http://0.0.0.0:11434"
echo "上下文: 128K"
echo "GPU层数: 全部"
echo "=============================="

$LLAMA_SERVER \
  -m "$MODEL_DIR" \
  --host 0.0.0.0 \
  --port 11434 \
  --n-gpu-layers 99 \
  -c 131072 \
  -n 32768 \
  --batch-size 256 \
  --flash-attn on \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --threads 8 \
  --parallel 1 \
  --no-mmap \
  --mlock \
  --temp 0.0 \
  --top-p 1.0 \
  --top-k 1 \
  --repeat-penalty 1.1 \
  --log-disable \
  --jinja \
  --chat-template-file /opt/my-shell/qwen35-chat-template-corrected.jinja \
  --reasoning-format none \
  --rope-scaling yarn \
  --rope-scale 4 \
  --yarn-orig-ctx 32768 \
  --context-shift \
  --metrics \
  --chat-template-kwargs "{\"enable_thinking\":false}" &

sleep 40

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
echo '  -d '"'"'{"model": "Qwen3-14B", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'"'"''
echo ""
echo "性能参数:"
echo "  模型: Qwen3-14B-Q4_K_M.gguf"
echo "  上下文: 128K"
echo "  最大输出: 32K"
echo "  GPU层数: 99"
echo "  KV缓存: q8_0 (平衡)"
echo "  Batch: 256"
echo "  并行: 1 (单序列优化)"
echo "  Flash Attention: on"
echo "  Temperature: 0.0"
echo "  Top-P: 1.0"
echo "  Top-K: 1"
echo "  Repeat Penalty: 1.1"
echo "  Reasoning格式: deepseek"
echo "  Chat模板: qwen35-chat-template-corrected.jinja"
echo "  思考模式: 关闭"
