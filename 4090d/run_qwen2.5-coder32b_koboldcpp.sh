#!/bin/bash

# =============================================================================
# Qwen2.5-Coder-32B GGUF 模型启动脚本 (koboldcpp 版本)
# =============================================================================

# 强制使用系统 libstdc++，避免 miniconda 的版本不兼容
export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/opt/cuda/lib64:$LD_LIBRARY_PATH
# 禁用 miniconda 的 libstdc++
unset LD_PRELOAD

MODEL_DIR="/opt/gguf/qwen2.5-coder-32b-instruct-q4_k_m.gguf"
MODEL_NAME="qwen2.5-coder-32b-instruct-q4_k_m.gguf"
CTX_SIZE=32768

if [ ! -f "$MODEL_DIR" ]; then
  echo "错误: 模型文件不存在: $MODEL_DIR"
  exit 1
fi

KOBOLDCPP_DIR="/opt/koboldcpp"

if [ ! -d "$KOBOLDCPP_DIR" ]; then
  echo "错误: koboldcpp 目录不存在: $KOBOLDCPP_DIR"
  echo "请先运行: ./build_koboldcpp.sh"
  exit 1
fi

# 日志文件
LOG_FILE="/opt/my-shell/4090d/koboldcpp_api.log"

echo "=============================="
echo "启动 Qwen2.5-Coder-32B API 服务"
echo "后端: koboldcpp (CUDA 优化版)"
echo "模型: $MODEL_NAME"
echo "地址: http://0.0.0.0:11434"
echo "上下文: $CTX_SIZE"
echo "GPU层数: 80"
echo "=============================="

cd "$KOBOLDCPP_DIR"

# 启动 koboldcpp
# 关键参数:
# --model: 模型路径
# --port: API 端口
# --gpulayers: GPU 层数
# --contextsize: 上下文长度
# --flashattention: 启用 FlashAttention
# --usecublas: 启用 cuBLAS 加速
# --nomodel: 命令行模式（无 GUI）
/usr/bin/python3 koboldcpp.py \
  --model "$MODEL_DIR" \
  --port 11434 \
  --gpulayers 80 \
  --contextsize $CTX_SIZE \
  --flashattention \
  --usecublas \
  --tensor_split 1.0 \
  --blasbatchsize 512 \
  --nomodel \
  2>&1 | tee "$LOG_FILE" &

KOBOLD_PID=$!

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
echo "PID: $KOBOLD_PID"
echo "=============================="
echo ""
echo "OpenCode 配置:"
echo '{'
echo '  "$schema": "https://opencode.ai/config.json",'
echo '  "model": "openai/qwen2.5-coder-32b-gguf",'
echo '  "provider": {'
echo '    "openai": {'
echo '      "npm": "@ai-sdk/openai-compatible",'
echo '      "name": "koboldcpp (local)",'
echo '      "options": {'
echo '        "baseURL": "http://localhost:11434/v1",'
echo '        "apiKey": "dummy"'
echo '      },'
echo '      "models": {'
echo '        "qwen2.5-coder-32b-gguf": {'
echo '          "name": "Qwen2.5-Coder-32B-GGUF (koboldcpp)",'
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
echo "  Flash Attention: on"
echo "  cuBLAS: on"
echo "  后端: koboldcpp (比 llama.cpp 快 20-30%)"

# 保存 PID 到文件
echo $KOBOLD_PID > /tmp/koboldcpp_server.pid

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
