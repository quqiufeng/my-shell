#!/bin/bash

export LD_LIBRARY_PATH=/opt/llama.cpp/bin:/opt/llama.cpp/build/lib:$LD_LIBRARY_PATH
export GGML_CUDA_FORCE_MMQ=1

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
  --batch-size 512 \
  --flash-attn on \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --threads 16 \
  --parallel 1 \
  --no-mmap \
  --mlock \
  --temp 0.6 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.0 \
  --log-disable \
  --jinja \
  --chat-template-file /opt/my-shell/qwen35-chat-template-corrected.jinja \
  --reasoning-format deepseek \
  --rope-scaling yarn \
  --rope-scale 4 \
  --yarn-orig-ctx 32768 \
  --context-shift \
  --metrics \
  --chat-template-kwargs '{"enable_thinking":false}' &

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
echo "  KV缓存: q4_0"
echo "  Batch: 512"
echo "  并行: 1 (单序列优化)"
echo "  Flash Attention: on"
echo "  Temperature: 0.6"
echo "  Top-P: 0.95"
echo "  Top-K: 20"
echo "  Reasoning格式: deepseek"
echo "  Chat模板: qwen35-chat-template-corrected.jinja"
echo "  思考模式: 关闭"
