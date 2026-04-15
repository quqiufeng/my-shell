#!/bin/bash
set -euo pipefail
#
# =============================================================
# Qwopus3.5-27B-v3 (llama.cpp) API 启动脚本 (4090D 24GB)
# =============================================================
#
# 【推荐首选】4090D 上 27B 模型最优方案
# llama.cpp > KoboldCpp (快 ~20%)
# =============================================================
#
# 【基准测试数据】(2025-04-14, test_api.py 算法题, max_tokens=1024)
# ┌─────────────┬──────────┬────────────┬──────────────────────────────┐
# │ 上下文大小  │ 平均速度 │ 总token数  │ 备注                         │
# ├─────────────┼──────────┼────────────┼──────────────────────────────┤
# │ 128K        │ ~39.9    │ ~19456     │ batch=512, threads=16,       │
# │             │          │            │ cache-type-k/v=q4_0, fa=on   │
# └─────────────┴──────────┴────────────┴──────────────────────────────┘
# 测试环境: NVIDIA GeForce RTX 4090 D 24GB, CUDA compute 8.9
# 模型: Qwopus3.5-27B-v3-Q4_K_S.gguf
# 速度波动: 39.0 - 40.4 tok/s (极差仅 1.4 tok/s, 稳定性极高)
#
# 【上下文配置】(4090D 24GB)
#   - 128K: 可行, 依赖 KV cache 量化 (-ctk/-ctv q4_0)
#   - 模型权重 ~15.6GB, 128K KV cache 量化后约需 5GB
#   - 如果不开启 KV cache 量化, 128K 会瞬间吃掉 16G 显存导致 OOM
# 【降级建议】(若启动时 OOM)
#   - 将 -c 131072 降为 98304 (96k)
#   - 关闭浏览器/视频播放器等显存占用程序
#
# 【优化要点】
#   - ctx-size: 131072 (128K, 4090D 24GB 极限值)
#   - batch-size: 512 (27B 在 128K 上下文下的平衡值)
#   - ubatch-size: 512
#   - cache-type-k/v: q4_0 (核心省显存参数, 24GB 跑 128K 的关键)
#   - flash-attn on: 必须开启, 大幅降低长文本显存压力并提升速度
#   - threads: 16
#   - --parallel 1 --slots 1: 减少 slot 开销
#   - --prio 2: 高优先级
#   - --mlock + --no-mmap
#   - --no-warmup: 跳过启动warmup, 大幅缩短启动时间
#   - --defrag-thold 0.1: KV cache 碎片整理阈值
#   - --temp 0.2: 低温度, 写代码需要极高确定性
#   - --min-p 0.05: 过滤低概率废话, 适合复杂代码生成
#   - --repeat-penalty 1.1: 防止长循环代码陷入死循环
# =============================================================
#
# 【启动方式】
#   cd /opt/my-shell/4090d
#   nohup ./run_qwopus3.5-27b-v3_llama.sh > /tmp/27b_qwopus_llama.log 2>&1 &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/27b_qwopus_llama.log
#
# 【停止服务】
#   pkill -f llama-server
#
# 【测试API】
#   curl http://localhost:11434/v1/models
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "Qwopus3.5-27B-v3-Q4_K_S.gguf", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'
#
# 【性能测试】
#   cd /opt/my-shell
#   MODEL="openai/Qwopus3.5-27B-v3-Q4_K_S.gguf" python3 test_api.py
#
# =============================================================
# OpenCode 配置文件 (~/.config/opencode/opencode.json)
# =============================================================
# {
#   "$schema": "https://opencode.ai/config.json",
#   "model": "openai/Qwopus3.5-27B-v3-Q4_K_S.gguf",
#   "provider": {
#     "openai": {
#       "npm": "@ai-sdk/openai-compatible",
#       "name": "Local Models",
#       "options": {
#         "baseURL": "http://localhost:11434/v1",
#         "apiKey": "dummy"
#       },
#       "models": {
#         "Qwopus3.5-27B-v3-Q4_K_S.gguf": {
#           "name": "Qwopus3.5-27B-v3 Q4_K_S (4090D)",
#           "maxContextWindow": 131072,
#           "maxOutputTokens": 32768
#         }
#       }
#     }
#   }
# }
#
# 【使用 opencode】
#   opencode -m openai/Qwopus3.5-27B-v3-Q4_K_S.gguf
#
# =============================================================

# 快速环境检查
if ! command -v nvidia-smi &> /dev/null; then
    echo "警告: nvidia-smi 未找到, 请确认 CUDA 驱动已安装"
fi
if [[ ! -x "/opt/llama.cpp/bin/llama-server" ]]; then
    echo "错误: /opt/llama.cpp/bin/llama-server 不存在或不可执行"
    exit 1
fi

export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/root/miniconda3/pkgs/libstdcxx-15.2.0-h39759b7_7/lib:/usr/lib/wsl/lib:${LD_LIBRARY_PATH:-}

# 4090D 24GB 显存优化参数
MODEL_DIR="/opt/gguf/Qwopus3.5-27B-v3-Q4_K_S.gguf"
LLAMA_SERVER="/opt/llama.cpp/bin/llama-server"

# 4090D 27B 模型参数 (24GB 显存极限, 128K 上下文)
NGL=99              # GPU层数 (全部加载到GPU)
CTX=131072          # 上下文 128K (4090D 24GB 极限值, 依赖KV cache量化)
BATCH=512           # batch size (27B在128K上下文下的平衡值)
UBATCH=512          # micro batch size
THREADS=16          # CPU线程数

PORT=11434

echo "=============================="
echo "启动 Qwopus3.5-27B-v3 Q4_K_S (llama.cpp) API 服务"
echo "地址: http://0.0.0.0:$PORT"
echo "模型: Qwopus3.5-27B-v3-Q4_K_S.gguf"
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
  --temp 0.2 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.05 \
  --repeat-penalty 1.1 \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --metrics

# 注意: 使用模型内置的chat template，不指定自定义模板
