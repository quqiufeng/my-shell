#!/bin/bash

export LD_LIBRARY_PATH=/opt/llama.cpp/bin:/opt/llama.cpp/build/lib:$LD_LIBRARY_PATH

MODEL_DIR="/opt/gguf/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-v2-GGUFF/Qwen3.5-27B.Q4_K_M.gguf"
LLAMA_SERVER="/opt/llama.cpp/bin/llama-server"

echo "=============================="
echo "启动 Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-v2 API 服务"
echo "地址: http://0.0.0.0:11434"
echo "上下文: 262144"
echo "GPU层数: 99"
echo "预测长度: -1"
echo "=============================="

$LLAMA_SERVER \
  -m "$MODEL_DIR" \
  --host 0.0.0.0 \
  --port 11434 \
  -n -1 \
  -ngl 99 \
  --flash-attn on \
  -c 262144 \
  --batch-size 4096 \
  --ubatch-size 512 \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --threads 14 \
  --parallel 4 \
  --prio 3 \
  --prio-batch 3 \
  --no-perf \
  --log-disable \
  --jinja &

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
echo "  上下文: 32K"
echo "  GPU层数: 99"
echo "  Flash Attention: on"
echo "  KV缓存: q4_0"
echo "  预测长度: -1 (不限制)"

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
