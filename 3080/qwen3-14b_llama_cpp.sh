#!/bin/bash
set -euo pipefail
#
# =============================================================
# Qwen3-14B (llama.cpp) API 启动脚本 (RTX 3080 20GB)
# =============================================================
#
# 【推荐首选】3080 上 14B 模型最优方案
# llama.cpp > KoboldCpp (快 ~20%)
# =============================================================
#
# 测试环境: NVIDIA GeForce RTX 3080 20GB, CUDA compute 8.6
# 模型: Qwen3-14B-Q4_K_M.gguf
#
# 【Chat Template 来源】
#   https://huggingface.co/froggeric/Qwen-Fixed-Chat-Templates
#   修复官方 Qwen template 的 agentic loop、KV cache 失效等问题
#   使用方式: --jinja --chat-template-file chat_template.jinja
#
# 【基准测试数据】(2025-05-30, test_api.py 6/30题算法题, max_tokens=1024)
# ┌──────────┬──────────┬────────────┬────────────────────────────────────┐
# │ 平均速度 │ 总token数 │ 总耗时     │ 配置                               │
# ├──────────┼──────────┼────────────┼────────────────────────────────────┤
# │ 58.1     │ 6120     │ 105.82s    │ ctx=128K, batch=512, threads=6,    │
# │ tok/s    │          │            │ cache-type-k/v=q4_0, flash-attn=on │
# │          │          │            │ rope-scaling=yarn, scale=4         │
# └──────────┴──────────┴────────────┴────────────────────────────────────┘
#
# 【上下文配置】(RTX 3080 20GB)
#   - 128K: 当前配置, 余量紧张 (~1.75GB KV cache), 依赖KV cache量化
#   - 96K: 安全余量充足 (模型 ~8.5GB + KV cache ~1.3GB)
#   - 如果不开启 KV cache 量化, 128K 会需要 ~14GB KV cache 导致 OOM
# 【降级建议】(若启动时 OOM)
#   - 将 -c 131072 降为 98304 (96k)
#   - 关闭浏览器/视频播放器等显存占用程序
#
# 【优化要点】
#   - ctx-size: 131072 (128K, 通过YaRN扩展, 原生32K)
#   - batch-size: 512 (保守值, 降低显存压力)
#   - ubatch-size: 512
#   - cache-type-k/v: q4_0 (核心省显存参数, 20GB 跑 128K 的关键)
#   - flash-attn on: 必须开启, 大幅降低长文本显存压力并提升速度
#   - threads: 6 (匹配 3500X 6核)
#   - --parallel 1 --slots 1: 减少slot开销
#   - --prio 2: 高优先级
#   - --mlock + --no-mmap
#   - --no-warmup: 跳过启动warmup, 大幅缩短启动时间
#   - --defrag-thold 0.1: KV cache 碎片整理阈值
#   - --temp 0.6: 通用平衡温度 (Qwen3 推荐值)
#   - --top-p 0.95
#   - --min-p 0.0: 关闭过滤 (通用对话需要多样性)
#   - --repeat-penalty 1.0: 轻微或不设置
# =============================================================
#
# 【启动方式】
#   cd /opt/my-shell/3080
#   nohup ./qwen3-14b_llama_cpp.sh > /tmp/qwen3_14b_llama.log 2>&1 &
#   echo $!  # 记录PID
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
#       "Qwen3-14B-Q4_K_M.gguf": {
#           "name": "Qwen3-14B Q4 (3080 20GB)",
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

# RTX 3080 20GB 显存优化参数
MODEL_DIR="/data/models/Qwen3-14B-Q4_K_M.gguf"
LLAMA_SERVER="/opt/llama.cpp/build/bin/llama-server"

# RTX 3080 14B 模型参数 (20GB 显存, 96K 安全上下文)
NGL=99              # GPU层数 (全部加载到GPU)
CTX=131072          # 上下文 128K (3080 20GB 极限值, 依赖KV cache量化)
BATCH=512           # batch size (保守值, 降低显存压力)
UBATCH=512          # micro batch size
THREADS=6           # CPU线程数 (匹配 3500X 6核)

PORT=11434

echo "=============================="
echo "启动 Qwen2.5-Coder-14B Q4_K_M (llama.cpp) API 服务"
echo "地址: http://0.0.0.0:$PORT"
echo "模型: Qwen3-14B-Q4_K_M.gguf"
echo "上下文: $CTX"
echo "GPU层数: $NGL"
echo "Batch Size: $BATCH"
echo "uBatch Size: $UBATCH"
echo "Threads: $THREADS"
echo "KV Cache: q4_0"
echo "=============================="
echo ""

exec $LLAMA_SERVER \
  -m "$MODEL_DIR" \
  --host 0.0.0.0 \
  --port $PORT \
  --reasoning off \
  --jinja \
  --chat-template-file /opt/my-shell/3080/chat_template.jinja \
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
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --defrag-thold 0.1 \
  --rope-scaling yarn \
  --rope-scale 4 \
  --yarn-orig-ctx 32768 \
  --timeout 300 \
  --metrics

# 注意: 使用模型内置的chat template，不指定自定义模板
