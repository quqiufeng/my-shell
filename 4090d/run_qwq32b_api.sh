#!/bin/bash

export LD_LIBRARY_PATH=/opt/llama.cpp/bin:/opt/llama.cpp/build/lib:$LD_LIBRARY_PATH

MODEL_DIR="/opt/gguf/QwQ-32B-Q4_K_M.gguf"
LLAMA_SERVER="/opt/llama.cpp/bin/llama-server"

echo "=============================="
echo "启动 QwQ-32B API 服务 (深度思考模型)"
echo "地址: http://0.0.0.0:11434"
echo "上下文: 32768"
echo "GPU层数: 99"
echo "=============================="

$LLAMA_SERVER \
  -m "$MODEL_DIR" \
  --host 0.0.0.0 \
  --port 11434 \
  --n-gpu-layers 99 \
  --ctx-size 32768 \
  --batch-size 4096 \
  --flash-attn on \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --threads 14 \
  --temperature 0.6 \
  --top-p 0.95 \
  --min-p 0.05 \
  --repeat-penalty 1.0 \
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
echo '  -d '"'"'{"model": "QwQ-32B-Q4_K_M.gguf", "messages": [{"role": "system", "content": "You are a helpful and harmless assistant. You should think deeply before answering. Write your thought process within <thought> tags."}, {"role": "user", "content": "你好"}], "max_tokens": 16384, "temperature": 0.6, "stop": ["<|im_end|>", "<|endoftext|>"]}'"'"''
echo ""
echo "性能参数:"
echo "  模型: QwQ-32B-Q4_K_M.gguf"
echo "  上下文: 32K"
echo "  GPU层数: 99"
echo "  KV缓存: q4_0"
echo "  Flash Attention: on"
echo "  Temperature: 0.6"
echo "  Top-P: 0.95, Min-P: 0.05"
echo "  Repeat Penalty: 1.0 (关闭)"

# ==========================================
# 测试命令 (curl)
# ==========================================
# 非流式测试:
# curl -s http://localhost:11434/v1/chat/completions \
#   -H "Content-Type: application/json" \
#   -d '{
#     "model": "QwQ-32B-Q4_K_M.gguf",
#     "messages": [
#       {"role": "system", "content": "You are a helpful and harmless assistant. You should think deeply before answering. Write your thought process within <thought> tags."},
#       {"role": "user", "content": "用Python实现一个支持并发请求的异步HTTP客户端，包含连接池、限流、重试机制，并给出完整的使用示例"}
#     ],
#     "max_tokens": 16384,
#     "temperature": 0.6,
#     "stop": ["<|im_end|>", "<|endoftext|>"]
#   }'
# 
# 流式测试:
# curl -N http://localhost:11434/v1/chat/completions \
#   -H "Content-Type: application/json" \
#   -d '{
#     "model": "QwQ-32B-Q4_K_M.gguf",
#     "messages": [
#       {"role": "system", "content": "You are a helpful and harmless assistant. You should think deeply before answering. Write your thought process within <thought> tags."},
#       {"role": "user", "content": "用Python实现一个支持并发请求的异步HTTP客户端，包含连接池、限流、重试机制，并给出完整的使用示例"}
#     ],
#     "max_tokens": 16384,
#     "temperature": 0.6,
#     "stream": true,
#     "stop": ["<|im_end|>", "<|endoftext|>"]
#   }'
# 
# 性能测试:
# time curl -s http://localhost:11434/v1/chat/completions \
#   -H "Content-Type: application/json" \
#   -d '{
#     "model": "QwQ-32B-Q4_K_M.gguf",
#     "messages": [
#       {"role": "system", "content": "You are a helpful and harmless assistant. You should think deeply before answering. Write your thought process within <thought> tags."},
#       {"role": "user", "content": "用Python写一个快速排序函数"}
#     ],
#     "max_tokens": 16384,
#     "temperature": 0.6,
#     "stop": ["<|im_end|>", "<|endoftext|>"]
#   }' | jq -r '.usage'
