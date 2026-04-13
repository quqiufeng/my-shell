#!/bin/bash
#
# =============================================================
# Qwen3-14B-Claude-4.5-Opus-Distill (llama.cpp) API 启动脚本 (4090D 24GB)
# =============================================================
#
# 【基准测试数据】(2025-04-13, test_api.py 30题算法题, max_tokens=1024)
# ┌─────────────┬──────────┬────────────┬──────────────────────────────┐
# │ 上下文大小  │ 平均速度 │ 总token数  │ 备注                         │
# ├─────────────┼──────────┼────────────┼──────────────────────────────┤
# │ 80K         │ 89.4     │ 30720      │ batch=2048, threads=16       │
# │ 80K         │ 89.4     │ 30720      │ batch=2048, threads=16, prio2│
# └─────────────┴──────────┴────────────┴──────────────────────────────┘
# 对比: KoboldCpp 同模型约 74-75 tok/s, llama.cpp 快 ~20%
# 测试环境: NVIDIA GeForce RTX 4090 D 24GB, CUDA compute 8.9
# 模型: Qwen3-14B-Claude-4.5-Opus-Distill.q4_k_m.gguf
#
# 【优化要点】
#   - ctx-size: 81920 (80K)
#   - batch-size: 2048 (4096会OOM)
#   - ubatch-size: 2048
#   - threads: 16
#   - --parallel 1: 减少slot开销
#   - --prio 2: 高优先级
#   - --flash-attn on + cache-type-k/v f16
#   - --mlock + --no-mmap
# =============================================================
#
# 【启动方式】
#   cd /opt/my-shell/4090d
#   nohup ./run_qwen3-14b-claude-45-opus-distill_llama.sh > /tmp/14b_claude45_llama.log 2>&1 &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/14b_claude45_llama.log
#
# 【停止服务】
#   pkill -f llama-server
#
# 【测试API】
#   curl http://localhost:11434/v1/models
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "Qwen3-14B-Claude-4.5-Opus-Distill.q4_k_m.gguf", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'
#
# 【性能测试】
#   cd /opt/my-shell
#   MODEL="openai/Qwen3-14B-Claude-4.5-Opus-Distill.q4_k_m.gguf" python3 test_api.py
#
# =============================================================
# OpenCode 配置文件 (~/.config/opencode/opencode.json)
# =============================================================
# {
#   "$schema": "https://opencode.ai/config.json",
#   "model": "openai/Qwen3-14B-Claude-4.5-Opus-Distill.q4_k_m.gguf",
#   "provider": {
#     "openai": {
#       "npm": "@ai-sdk/openai-compatible",
#       "name": "Local Models",
#       "options": {
#         "baseURL": "http://localhost:11434/v1",
#         "apiKey": "dummy"
#       },
#       "models": {
#         "Qwen3-14B-Claude-4.5-Opus-Distill.q4_k_m.gguf": {
#           "name": "Qwen3-14B-Claude-4.5-Opus-Distill Q4 (4090D)",
#           "maxContextWindow": 81920,
#           "maxOutputTokens": 32768
#         }
#       }
#     }
#   }
# }
#
# 【使用 opencode】
#   opencode -m openai/Qwen3-14B-Claude-4.5-Opus-Distill.q4_k_m.gguf
#
# =============================================================

export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/root/miniconda3/pkgs/libstdcxx-15.2.0-h39759b7_7/lib:/usr/lib/wsl/lib:$LD_LIBRARY_PATH

# 4090D 24GB 显存优化参数
MODEL_DIR="/opt/gguf/Qwen3-14B-Claude-4.5-Opus-Distill.q4_k_m.gguf"
LLAMA_SERVER="/opt/llama.cpp/bin/llama-server"

# 4090D 可以支持更大的上下文和 batch size
NGL=99              # GPU层数 (全部加载到GPU)
CTX=81920           # 上下文 80K (4090D 24GB 支持)
BATCH=2048          # batch size (14B模型最佳值, 4096会OOM)
UBATCH=2048         # micro batch size
THREADS=16          # CPU线程数

PORT=11434

echo "=============================="
echo "启动 Qwen3-14B-Claude-4.5-Opus-Distill Q4_K_M (llama.cpp) API 服务"
echo "地址: http://0.0.0.0:$PORT"
echo "模型: Qwen3-14B-Claude-4.5-Opus-Distill.q4_k_m.gguf"
echo "上下文: $CTX"
echo "GPU层数: $NGL"
echo "Batch Size: $BATCH"
echo "uBatch Size: $UBATCH"
echo "Threads: $THREADS"
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
