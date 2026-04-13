#!/bin/bash
#
# =============================================================
# Qwen3.5-9B (llama.cpp) API 启动脚本 (4090D 24GB) - 优化版
# =============================================================
#
# 【基准测试数据】(2025-04-13, test_api.py 30题算法题, max_tokens=1024)
# ┌─────────────┬──────────┬────────────┬────────────────────────┐
# │ 上下文大小  │ 平均速度 │ 总token数  │ 备注                   │
# ├─────────────┼──────────┼────────────┼────────────────────────┤
# │ 256K        │ 113.3    │ 30720      │ batch=4096, threads=16 │
# └─────────────┴──────────┴────────────┴────────────────────────┘
# 对比: KoboldCpp 同模型约 86.5 tok/s, llama.cpp 快 ~31%
# 测试环境: NVIDIA GeForce RTX 4090 D 24GB, CUDA compute 8.9
# 模型: Qwopus3.5-9B-v3.Q4_K_M.gguf
#
# 【优化要点】
#   - ctx-size: 262144 (256K)
#   - batch-size: 4096 (原2048)
#   - ubatch-size: 4096 (原2048)
#   - threads: 16 (最佳, 32无提升)
#   - --parallel 1: 减少slot开销
#   - --prio 2: 高优先级
#   - --flash-attn on + cache-type-k/v f16
#   - --mlock + --no-mmap
# =============================================================
#
# 【启动方式】
#   cd /opt/my-shell/4090d
#   nohup ./run_qwen3.5-9b_llama.sh > /tmp/9b_llama_256k.log 2>&1 &
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
MODEL_DIR="/opt/gguf/Qwopus3.5-9B-v3-GGUF/Qwopus3.5-9B-v3.Q4_K_M.gguf"
LLAMA_SERVER="/opt/llama.cpp/bin/llama-server"

# 4090D 可以支持更大的上下文和 batch size
NGL=99              # GPU层数 (全部加载到GPU)
CTX=262144          # 上下文 256K (4090D 24GB 极限测试)
BATCH=4096          # batch size (优化: 4096)
UBATCH=4096         # micro batch size (优化: 4096)
THREADS=16          # CPU线程数 (优化后: 16线程最佳)

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
echo "目标: 110+ tok/s"
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
  --prio 2 \
  --no-mmap \
  --mlock \
  --temp 0.6 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.00 \
  --cache-type-k f16 \
  --cache-type-v f16 \
  --metrics \
  --parallel 1

# 注意: 使用模型内置的chat template，不指定自定义模板
