#!/bin/bash
set -euo pipefail
#
# =============================================================
# Qwopus3.6-27B-v2-MTP (llama.cpp) API 启动脚本 (4090D 24GB)
# =============================================================
#
# 【模型主页】https://huggingface.co/Jackrong/Qwopus3.6-27B-v2-MTP-GGUF
#
# 【模型介绍】
#   Qwopus3.6-27B-v2-MTP 是基于 Qwen3.6-27B 的 MTP 推理增强微调模型
#   - 架构: Dense Transformer / 27 Billion Parameters
#   - 核心能力: Multi-Token Prediction (MTP) 推测解码加速
#   - 训练: Trace Inversion & Negentropy 重构推理轨迹
#   - 特点: 保持 27B 推理深度的同时显著提升生成速度
#   - 评估: 30题综合基准 10.46 T/s (对比 Qwen3.6-27B 6.29 T/s, 1.66x)
#   - 输出: Token 效率提升 27.7%, 更紧凑的推理输出
#
# 【MTP 说明】
#   - 本脚本作为普通 GGUF 运行 (llama.cpp 目前不原生支持 MTP 推测解码)
#   - 如需 MTP 加速, 需配合支持 draft model 的推理后端 (如 vLLM, SGLang)
#   - GGUF 内含 MTP heads, 兼容 llama.cpp 标准推理
#
# 【多模态说明】
#   - 模型支持 Image-Text-to-Text (Qwen3.6 vision 能力)
#   - llama.cpp 对 vision 支持有限, 本脚本仅启用文本 API
#   - 如需 vision, 请使用 vLLM / SGLang / Transformers
# =============================================================
#
# 【基准测试数据】(模型作者, GB10, 30题综合基准)
# ┌─────────────┬──────────┬────────────┬──────────────────────────────┐
# │ 领域        │ Qwen3.6  │ MTP v2     │ 加速比                       │
# ├─────────────┼──────────┼──────────┼──────────────────────────────┤
# │ Logic       │ 6.33 T/s │ 10.77 T/s  │ 1.70x                        │
# │ Coding      │ 6.26 T/s │ 10.27 T/s  │ 1.64x                        │
# │ DevOps      │ 6.29 T/s │ 10.39 T/s  │ 1.65x                        │
# │ Math        │ 6.29 T/s │ 11.00 T/s  │ 1.75x                        │
# │ Edge        │ 6.48 T/s │ 8.28 T/s   │ 1.28x                        │
# │ 整体        │ 6.29 T/s │ 10.46 T/s  │ 1.66x                        │
# └─────────────┴──────────┴──────────┴──────────────────────────────┘
# 测试环境: GB10 dedicated server, llama-server context=49152
# 模型: Qwopus3.6-27B-v2-MTP-Q4_K_M.gguf
#
# 【显存估算】(Q4_K_M 量化)
#   - 模型权重: ~16.8GB
#   - 128K KV cache (q4_0 量化): ~5-6GB
#   - 总计: ~22-23GB (4090D 24GB 可行)
#
# 【上下文配置】(4090D 24GB)
#   - 128K: 可行, 依赖 KV cache 量化 (-ctk/-ctv q4_0)
#   - 模型权重 ~16.8GB, 128K KV cache 量化后约需 5-6GB
#   - 若 OOM, 建议降至 98304 (96k) 或 65536 (64k)
# 【降级建议】
#   - 将 -c 131072 降为 98304 或 65536
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
#   - --no-warmup: 跳过启动 warmup, 大幅缩短启动时间
#   - --temp 0.6: 推理模型需要适度温度激活思维链 (作者测试用 1.0)
#   - --top-p 0.95: 保持一定多样性
#   - --min-p 0.05: 过滤低概率废话
#   - --repeat-penalty 1.1: 防止长循环代码陷入死循环
# =============================================================
#
# 【启动方式】(必须用 setsid，否则终端关闭会终止服务)
#   cd /opt/my-shell/4090d
#   setsid nohup ./run_qwopus3.6-27b-v2-mtp_llama.sh > /tmp/27b_qwopus36_mtp_llama.log 2>&1 < /dev/null &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/27b_qwopus36_mtp_llama.log
#
# 【停止服务】
#   pkill -f "llama-server.*Qwopus3.6-27B-v2-MTP"
#
# 【测试API】
#   curl http://localhost:11435/v1/models
#   curl -s http://localhost:11435/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "Qwopus3.6-27B-v2-MTP-Q4_K_M.gguf", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'
#
# 【性能测试】
#   cd /opt/my-shell
#   MODEL="openai/Qwopus3.6-27B-v2-MTP-Q4_K_M.gguf" \
#   BASE_URL="http://localhost:11435/v1" python3 test_api.py
#
# =============================================================
# OpenCode 配置文件 (~/.config/opencode/opencode.json)
# =============================================================
# {
#   "$schema": "https://opencode.ai/config.json",
#   "model": "openai/Qwopus3.6-27B-v2-MTP-Q4_K_M.gguf",
#   "provider": {
#     "openai": {
#       "npm": "@ai-sdk/openai-compatible",
#       "name": "Local Models",
#       "options": {
#         "baseURL": "http://localhost:11435/v1",
#         "apiKey": "dummy"
#       },
#       "models": {
#         "Qwopus3.6-27B-v2-MTP-Q4_K_M.gguf": {
#           "name": "Qwopus3.6-27B-v2-MTP Q4_K_M (4090D)",
#           "maxContextWindow": 131072,
#           "maxOutputTokens": 32768
#         }
#       }
#     }
#   }
# }
#
# 【使用 opencode】
#   opencode -m openai/Qwopus3.6-27B-v2-MTP-Q4_K_M.gguf
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

export LD_LIBRARY_PATH=/opt/llama.cpp/bin:/usr/lib/x86_64-linux-gnu:/root/miniconda3/pkgs/libstdcxx-15.2.0-h39759b7_7/lib:/usr/lib/wsl/lib:${LD_LIBRARY_PATH:-}

# 4090D 24GB 显存优化参数
MODEL_DIR="/opt/gguf/Qwopus3.6-27B-v2-MTP-Q4_K_M.gguf"
LLAMA_SERVER="/opt/llama.cpp/bin/llama-server"
CHAT_TEMPLATE="/opt/my-shell/4090d/qwopus35-27b-chat-template.jinja"

# 4090D 27B 模型参数 (24GB 显存极限, 128K 上下文)
NGL=99              # GPU层数 (全部加载到GPU)
CTX=131072          # 上下文 128K (4090D 24GB 极限值, 依赖KV cache量化)
BATCH=512           # batch size (27B在128K上下文下的平衡值)
UBATCH=512          # micro batch size
THREADS=16          # CPU线程数

PORT=11435

echo "=============================="
echo "启动 Qwopus3.6-27B-v2-MTP Q4_K_M (llama.cpp) API 服务"
echo "地址: http://0.0.0.0:$PORT"
echo "模型: Qwopus3.6-27B-v2-MTP-Q4_K_M.gguf"
echo "上下文: $CTX"
echo "GPU层数: $NGL"
echo "Batch Size: $BATCH"
echo "uBatch Size: $UBATCH"
echo "Threads: $THREADS"
echo "KV Cache: q4_0"
echo "Flash Attention: on"
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
  --no-warmup \
  --parallel 1 \
  --temp 0.6 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.05 \
  --repeat-penalty 1.1 \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --metrics

# 使用模型内置的 Qwen3.6 chat template (GGUF 自带)
