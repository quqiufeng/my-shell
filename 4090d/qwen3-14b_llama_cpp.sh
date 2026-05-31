#!/bin/bash
set -euo pipefail
#
# =============================================================
# Qwen3-14B (llama.cpp) API 启动脚本 (RTX 4090 D 24GB)
# =============================================================
#
# 【硬件环境】
#   - GPU: NVIDIA GeForce RTX 4090 D, 24GB VRAM, CUDA compute 8.9
#   - CPU: AMD EPYC 7542 32-Core x 2 Socket (64C/128T)
#   - RAM: 512GB
#   - 模型: Qwen3-14B-Q4_K_M.gguf (约 9GB)
#
# 【基准测试数据】(2025-05-31, test_api.py 29/30题算法题, max_tokens=1024)
# ┌──────────┬──────────┬────────────┬────────────────────────────────────┐
# │ 平均速度 │ 总token数 │ 总耗时     │ 配置                               │
# ├──────────┼──────────┼────────────┼────────────────────────────────────┤
# │ 90.4     │ 29696    │ 328.6s     │ ctx=131072, batch=1024, threads=16,│
# │ tok/s    │          │            │ cache-type-k/v=q8_0, flash-attn=on │
# │          │          │            │ rope-scaling=yarn, scale=4         │
# └──────────┴──────────┴────────────┴────────────────────────────────────┘
#
# 【上下文配置】(RTX 4090 D 24GB)
#   - 128K: 当前配置, 余量充足 (模型 ~9GB + KV cache ~2.5GB)
#   - 24GB 显存充裕, 可启用更高精度 KV cache (q8_0)
#
# 【优化要点】
#   - ctx-size: 131072 (128K, 4090D 24GB 轻松承载, 无需担心显存)
#   - batch-size: 1024 (24GB 显存充裕, 提升吞吐)
#   - ubatch-size: 1024
#   - cache-type-k/v: q8_0 (24GB 显存可承受更高精度)
#   - flash-attn on: 必须开启
#   - threads: 16 (服务器 128 线程)
#   - --parallel 1 --slots 1: 减少slot开销
#   - --prio 2: 高优先级
#   - --mlock + --no-mmap
#   - --no-warmup: 跳过启动warmup
#   - --defrag-thold 0.1: KV cache 碎片整理阈值
#   - --temp 0.6: 通用平衡温度 (Qwen3 推荐值)
#   - --top-p 0.95
#   - --min-p 0.0: 关闭过滤
#   - --repeat-penalty 1.0: 轻微或不设置
# =============================================================
#
# 【启动方式】(必须用 setsid，否则终端关闭会终止服务)
#   cd /opt/my-shell/4090d
#   setsid ./qwen3-14b_llama_cpp.sh > /tmp/qwen3_14b_llama.log 2>&1 &
#   echo $!  # 记录 PID
#
# 【查看日志】
#   tail -f /tmp/qwen3_14b_llama.log
#
# 【停止服务】
#   pkill -f llama-server
#
# 【测试API】
#   curl http://localhost:11434/v1/models
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "Qwen3-14B-Q4_K_M.gguf", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'
#
# 【性能测试】
#   cd /opt/my-shell
#   MODEL="openai/Qwen3-14B-Q4_K_M.gguf" python3 test_api.py
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
#       "Qwen3-14B-Q4_K_M.gguf": {
#           "name": "Qwen3-14B Q4 (4090D 24GB)",
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

# 快速环境检查
if ! command -v nvidia-smi &> /dev/null; then
    echo "警告: nvidia-smi 未找到, 请确认 CUDA 驱动已安装"
fi
if [[ ! -x "/opt/llama.cpp/build/bin/llama-server" ]]; then
    echo "错误: /opt/llama.cpp/build/bin/llama-server 不存在或不可执行"
    exit 1
fi

export LD_LIBRARY_PATH=/data/cuda/lib64:/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}

# RTX 4090 D 24GB 优化参数
MODEL_DIR="/opt/gguf/Qwen3-14B-Q4_K_M.gguf"
LLAMA_SERVER="/opt/llama.cpp/build/bin/llama-server"

# RTX 4090 D 14B 模型参数
NGL=99              # GPU层数 (全部加载到GPU)
CTX=131072          # 上下文 128K
BATCH=1024          # batch size (24GB 显存充裕)
UBATCH=1024         # micro batch size
THREADS=16          # CPU线程数 (服务器128线程)

PORT=11434

echo "=============================="
echo "启动 Qwen3-14B Q4_K_M (llama.cpp) API 服务"
echo "地址: http://0.0.0.0:$PORT"
echo "模型: $MODEL_DIR"
echo "上下文: $CTX"
echo "GPU层数: $NGL"
echo "Batch Size: $BATCH"
echo "uBatch Size: $UBATCH"
echo "Threads: $THREADS"
echo "KV Cache: q8_0"
echo "=============================="
echo ""

CHAT_TEMPLATE="/opt/my-shell/4090d/chat_template.jinja"

exec $LLAMA_SERVER \
  -m "$MODEL_DIR" \
  --host 0.0.0.0 \
  --port $PORT \
  --reasoning off \
  --jinja \
  --chat-template-file /opt/my-shell/4090d/qwen-template/chat_template.jinja \
  -ngl $NGL \
  -c $CTX \
  --batch-size $BATCH \
  --ubatch-size $UBATCH \
  --flash-attn on \
  --threads $THREADS \
  --threads-batch $THREADS \
  --prio 2 \
  --no-mmap \
  --mlock \
  --no-warmup \
  --parallel 1 \
  --temp 0.6 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.0 \
  --repeat-penalty 1.0 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --defrag-thold 0.1 \
  --rope-scaling yarn \
  --rope-scale 4 \
  --yarn-orig-ctx 32768 \
  --override-kv qwen3.context_length=int:131072 \
  --timeout 300 \
  --metrics
