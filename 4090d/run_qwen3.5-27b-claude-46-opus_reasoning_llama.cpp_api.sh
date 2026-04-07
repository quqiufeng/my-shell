#!/bin/bash
#
# =============================================================
# Qwen3.5-27B-Claude-4.6-Opus-Reasoning (llama.cpp) API 脚本 (4090D 24GB)
# =============================================================
#
# 【启动方式】
#   cd /opt/my-shell/4090d
#   nohup ./run_qwen3.5-27b-claude-46-opus_reasoning_llama.cpp_api.sh > /tmp/27b_llama.log 2>&1 &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/27b_llama.log
#
# 【停止服务】
#   killall -9 llama-server
#
# 【测试API】
#   curl http://localhost:11434/v1/models
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-v2", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'
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
#   "model": "llama.cpp/Qwen3.5-27B-Claude-46-Opus-Reasoning",
#   "provider": {
#     "llama.cpp": {
#       "npm": "@ai-sdk/openai-compatible",
#       "options": { "baseURL": "http://localhost:11434/v1" },
#       "models": {
#         "Qwen3.5-27B-Claude-46-Opus-Reasoning": {
#           "name": "Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-v2",
#           "maxContextWindow": 262144,
#           "maxOutputTokens": 32768,
#           "options": { "num_ctx": 262144 }
#         }
#       }
#     }
#   }
# }
#
# 【使用 opencode】
#   opencode -m llama.cpp/Qwen3.5-27B-Claude-46-Opus-Reasoning
#
# =============================================================

export LD_LIBRARY_PATH=/opt/llama.cpp/bin:/opt/llama.cpp/build/lib:$LD_LIBRARY_PATH
export GGML_CUDA_FORCE_MMQ=1
export GGML_CUDA_NO_VMM=1

MODEL_DIR="/opt/gguf/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-v2-GGUFF/Qwen3.5-27B.Q4_K_M.gguf"
LLAMA_SERVER="/opt/llama.cpp/bin/llama-server"

echo "=============================="
echo "启动 Qwen3.5-27B-Claude-4.6-Opus-Reasoning (llama.cpp) API 服务"
echo "地址: http://0.0.0.0:11434"
echo "上下文: 256K (262144)"
echo "GPU层数: 99"
echo "KV缓存: q4_0"
echo "Flash Attention: on"
echo "Jinja模板: qwen35-chat-template-corrected.jinja"
echo "=============================="

$LLAMA_SERVER \
  -m "$MODEL_DIR" \
  --host 0.0.0.0 \
  --port 11434 \
  --n-gpu-layers 99 \
  -c 262144 \
  -n 32768 \
  --batch-size 4096 \
  --ubatch-size 512 \
  --flash-attn on \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --threads 14 \
  --parallel 4 \
  --prio 3 \
  --prio-batch 3 \
  --no-mmap \
  --mlock \
  --no-perf \
  --log-disable \
  --jinja \
  --chat-template-file /opt/my-shell/qwen35-chat-template-corrected.jinja \
  --reasoning-format none \
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
echo '  -d '"'"'{"model": "Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-v2", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'"'"''
echo ""
echo "性能参数:"
echo "  模型: Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-v2"
echo "  上下文: 256K"
echo "  最大输出: 32K"
echo "  GPU层数: 99"
echo "  KV缓存: q4_0"
echo "  Batch: 4096"
echo "  UBatch: 512"
echo "  并行: 4"
echo "  Flash Attention: on"
echo "  Temperature: 0.0"
echo "  Chat模板: qwen35-chat-template-corrected.jinja"
echo "  思考模式: 关闭 (enable_thinking=false)"

# ==========================================
# 测试命令 (curl)
# ==========================================
# 非流式测试:
# curl -s http://localhost:11434/v1/chat/completions \
#   -H "Content-Type: application/json" \
#   -d '{
#     "model": "Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-v2",
#     "messages": [{"role": "user", "content": "用Python实现一个支持并发请求的异步HTTP客户端，包含连接池、限流、重试机制，并给出完整的使用示例"}],
#     "max_tokens": 1000
#   }'
#
# 流式测试:
# curl -N http://localhost:11434/v1/chat/completions \
#   -H "Content-Type: application/json" \
#   -d '{
#     "model": "Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-v2",
#     "messages": [{"role": "user", "content": "用Python实现一个支持并发请求的异步HTTP客户端，包含连接池、限流、重试机制，并给出完整的使用示例"}],
#     "max_tokens": 1000,
#     "stream": true
#   }'
#
# 推理效率测试:
# time curl -s http://localhost:11434/v1/chat/completions \
#   -H "Content-Type: application/json" \
#   -d '{
#     "model": "Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-v2",
#     "messages": [{"role": "user", "content": "用Python写一个快速排序函数"}],
#     "max_tokens": 200
#   }' | jq -r '.usage'
