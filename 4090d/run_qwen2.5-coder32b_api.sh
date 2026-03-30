#!/bin/bash

# =============================================================================
# Qwen2.5-Coder-32B GGUF 模型启动脚本 (直接对接 OpenCode，无需 LiteLLM)
# =============================================================================

export LD_LIBRARY_PATH=/opt/llama.cpp/bin:/opt/llama.cpp/build/lib:$LD_LIBRARY_PATH

MODEL_DIR="/opt/gguf/qwen2.5-coder-32b-instruct-q4_k_m.gguf"
MODEL_NAME="qwen2.5-coder-32b-instruct-q4_k_m.gguf"
KV_CACHE="q4_0"
CTX_SIZE=65536

if [ ! -f "$MODEL_DIR" ]; then
  echo "错误: 模型文件不存在: $MODEL_DIR"
  exit 1
fi

LLAMA_SERVER="/opt/llama.cpp/bin/llama-server"

# 日志文件
LOG_FILE="/opt/my-shell/4090d/qwen_api.log"

echo "=============================="
echo "启动 Qwen2.5-Coder-32B API 服务"
echo "模型: $MODEL_NAME"
echo "地址: http://0.0.0.0:11434"
echo "上下文: $CTX_SIZE"
echo "GPU层数: 80"
echo "=============================="

# 启动 llama-server
# 关键参数:
# --jinja: 启用 Jinja 模板，正确处理工具调用
# --temp 0: 降低温度，防止随机性导致 JSON 解析失败
$LLAMA_SERVER \
  -m "$MODEL_DIR" \
  --host 0.0.0.0 \
  --port 11434 \
  --n-gpu-layers 80 \
  --ctx-size $CTX_SIZE \
  --batch-size 1024 \
  --ubatch-size 512 \
  --flash-attn on \
  --cache-type-k "$KV_CACHE" \
  --cache-type-v "$KV_CACHE" \
  --threads 14 \
  --no-mmap \
  --mlock \
  --jinja \
  --temp 0 \
  2>&1 | tee "$LOG_FILE" &

LLAMA_PID=$!

# 等待服务启动
sleep 5

# 检查服务是否启动成功
for i in {1..30}; do
  if curl -s http://localhost:11434/v1/models > /dev/null 2>&1; then
    break
  fi
  sleep 1
done

INSTANCE_ID=${XGC_INSTANCE_ID:-$(hostname)}

echo ""
echo "=============================="
echo "服务已启动!"
echo "=============================="
echo "API 地址: http://localhost:11434"
echo "对外地址: http://${INSTANCE_ID}-11434.container.x-gpu.com/v1/"
echo "日志文件: $LOG_FILE"
echo "PID: $LLAMA_PID"
echo "=============================="
echo ""
echo "OpenCode 配置:"
echo '{'
echo '  "$schema": "https://opencode.ai/config.json",'
echo '  "model": "openai/qwen2.5-coder-32b-gguf",'
echo '  "provider": {'
echo '    "openai": {'
echo '      "npm": "@ai-sdk/openai-compatible",'
echo '      "name": "llama.cpp (local)",'
echo '      "options": {'
echo '        "baseURL": "http://localhost:11434/v1",'
echo '        "apiKey": "dummy"'
echo '      },'
echo '      "models": {'
echo '        "qwen2.5-coder-32b-gguf": {'
echo '          "name": "Qwen2.5-Coder-32B-GGUF",'
echo '          "maxContextWindow": 65536,'
echo '          "maxOutputTokens": 8192'
echo '        }'
echo '      }'
echo '    }'
echo '  }'
echo '}'
echo ""
echo "调试命令:"
echo "curl -s http://localhost:11434/v1/chat/completions \\"
echo '  -H "Content-Type: application/json" \\'
echo '  -d '"'"'{"model": "qwen2.5-coder-32b-gguf", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'"'"''
echo ""
echo "性能参数:"
echo "  模型: $MODEL_NAME"
echo "  上下文: $CTX_SIZE"
echo "  GPU层数: 80"
echo "  KV缓存: $KV_CACHE"
echo "  Flash Attention: on"
echo "  Jinja模板: on"
echo "  Temperature: 0"

# 保存 PID 到文件
echo $LLAMA_PID > /tmp/llama_server.pid

# ==========================================
# 性能测试 (使用 usage 字段获取准确 token 数)
# ==========================================
# 测试1: 红黑树
# python3 -c "
# import requests, time
# url = 'http://localhost:11434/v1/chat/completions'
# data = {'model': 'qwen2.5-coder-32b-gguf', 'messages': [{'role': 'user', 'content': '用Python实现一个红黑树'}], 'max_tokens': 800, 'stream': False}
# t = time.time()
# r = requests.post(url, json=data, timeout=60).json()
# elapsed = time.time() - t
# gen_tokens = r['usage']['completion_tokens']
# print(f'{gen_tokens} tokens / {elapsed:.2f}s = {gen_tokens/elapsed:.1f} tokens/s')
# "
