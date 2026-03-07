#!/bin/bash

MODEL_TYPE="${1:-q3}"

if [ "$MODEL_TYPE" = "q3" ]; then
  MODEL_DIR="/opt/gguf/qwen2.5-coder-32b-instruct-q3_k_m.gguf"
  MODEL_NAME="qwen2.5-coder-32b-instruct-q3_k_m.gguf"
  KV_CACHE="q4_0"
  CTX_SIZE=65536
else
  MODEL_DIR="/opt/gguf/qwen2.5-coder-32b-instruct-q4_k_m.gguf"
  MODEL_NAME="qwen2.5-coder-32b-instruct-q4_k_m.gguf"
  KV_CACHE="q4_0"
  CTX_SIZE=32768
fi

if [ ! -f "$MODEL_DIR" ]; then
  echo "错误: 模型文件不存在: $MODEL_DIR"
  exit 1
fi

export LD_LIBRARY_PATH=/opt/llama.cpp/bin:/opt/llama.cpp/build/lib:$LD_LIBRARY_PATH
LLAMA_SERVER="/opt/llama.cpp/bin/llama-server"

echo "=============================="
echo "启动 Qwen2.5-Coder-32B API 服务"
echo "模型: $MODEL_NAME"
echo "地址: http://0.0.0.0:11434"
echo "上下文: $CTX_SIZE"
echo "GPU层数: 99"
echo "=============================="

$LLAMA_SERVER \
  -m "$MODEL_DIR" \
  --host 0.0.0.0 \
  --port 11434 \
  --n-gpu-layers 99 \
  --ctx-size $CTX_SIZE \
  --batch-size 4096 \
  --flash-attn on \
  --cache-type-k "$KV_CACHE" \
  --cache-type-v "$KV_CACHE" \
  --threads 14 \
  --log-disable &

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
echo '  -H "Content-Type: application/json" \\'
echo '  -d '"'"'{"model": "'"$MODEL_NAME"'", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'"'"''
echo ""
echo "性能参数:"
echo "  模型: $MODEL_NAME"
echo "  上下文: $CTX_SIZE"
echo "  GPU层数: 99"
echo "  KV缓存: $KV_CACHE"
echo "  Flash Attention: on"

# ==========================================
# 测试命令 (curl)
# ==========================================
# 非流式测试:
# curl -s http://localhost:11434/v1/chat/completions \
#   -H "Content-Type: application/json" \
#   -d '{
#     "model": "'"$MODEL_NAME"'",
#     "messages": [{"role": "user", "content": "用Python实现一个支持并发请求的异步HTTP客户端，包含连接池、限流、重试机制，并给出完整的使用示例"}],
#     "max_tokens": 1000
#   }'
# 
# 流式测试:
# curl -N http://localhost:11434/v1/chat/completions \
#   -H "Content-Type: application/json" \
#   -d '{
#     "model": "'"$MODEL_NAME"'",
#     "messages": [{"role": "user", "content": "用Python实现一个支持并发请求的异步HTTP客户端，包含连接池、限流、重试机制，并给出完整的使用示例"}],
#     "max_tokens": 1000,
#     "stream": true
#   }'
# 
# 性能测试:
# time curl -s http://localhost:11434/v1/chat/completions \
#   -H "Content-Type: application/json" \
#   -d '{
#     "model": "'"$MODEL_NAME"'",
#     "messages": [{"role": "user", "content": "用Python写一个快速排序函数"}],
#     "max_tokens": 200
#   }' | jq -r '.usage'
