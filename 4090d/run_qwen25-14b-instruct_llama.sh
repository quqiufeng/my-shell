#!/bin/bash
set -euo pipefail
#
# =============================================================
# Qwen2.5-14B-Instruct (llama.cpp) API 启动脚本 (4090D 24GB)
# =============================================================
#
# 【模型主页】https://huggingface.co/bartowski/Qwen2.5-14B-Instruct-GGUF
#
# 【模型介绍】
#   Qwen2.5-14B-Instruct 是阿里云通义千问团队的通用指令模型
#   - 基础模型: Qwen2.5-14B, Architecture: qwen2
#   - 核心能力: 代码生成、工具调用 (Tool Call)、多轮对话、中文理解
#   - 特点: 14B 参数量，Q4_K_M 量化约 8.5GB，速度优异
#   - Tool Call: ✅ 原生支持，兼容 OpenAI function calling 格式
#   - 上下文: 原生支持 128K tokens
#   - 训练数据: 高达 18T tokens，覆盖多语言、代码、数学等
#   - 评估亮点:
#     * MMLU: 79.8+ (14B 级别领先)
#     * HumanEval: 75+ (代码能力)
#     * MT-Bench: 8.2+ (对话质量)
#     * 工具调用准确率: 90%+ (function calling)
#   - 许可证: Apache 2.0 (可商用)
#   
#   GGUF 量化版本由 bartowski 提供，使用 imatrix 校准
#   - Q4_K_M: 推荐平衡点 (8.5GB, 质量损失 <3%)
#   - 支持 llama.cpp 原生加载，无需转换
#
# 【推荐】4090D 上支持 Tool Call 的 14B 模型首选方案
# llama.cpp 全载 GPU，128K 上下文流畅运行
#
# 【基准测试数据】(2025-05-31, test_api.py 30题算法题, max_tokens=1024)
# ┌─────────────┬──────────┬────────────┬──────────────────────────────┐
# │ 上下文大小  │ 平均速度 │ 总token数  │ 备注                         │
# ├─────────────┼──────────┼────────────┼──────────────────────────────┤
# │ 128K        │ 78.9     │ 22028      │ batch=1024, threads=16,      │
# │             │          │            │ cache-type-k/v=q8_0, fa=on   │
# └─────────────┴──────────┴────────────┴──────────────────────────────┘
# 速度范围: 77.5 - 80.0 tok/s (非常稳定)
# 测试环境: NVIDIA GeForce RTX 4090 D 24GB, CUDA compute 8.9
# 模型: Qwen2.5-14B-Instruct-Q4_K_M.gguf
# =============================================================
#
# 【上下文配置】(4090D 24GB)
#   - 128K: 可行, 14B Q4_K_M 权重约 8.5GB
#   - 需要 KV cache 量化 (--cache-type-k/v q8_0) 才能在 24GB 跑 128K
#   - 若启动时 OOM，可降级为 q4_0 或将上下文降为 96K
#
# 【优化要点】
#   - ctx-size: 131072 (128K, 4090D 24GB 轻松胜任)
#   - batch-size: 1024 (14B 模型可适当增大)
#   - ubatch-size: 1024
#   - flash-attn on: 必须开启
#   - threads: 16
#   --parallel 1 --slots 1
#   --prio 2
#   --mlock + --no-mmap
#   --no-warmup
#   --cache-type-k/v: q8_0 (128K 下需要 KV cache 量化)
#   --flash-attn on: 必须开启
#   --temp 0.7: 通用对话平衡温度
#   --top-p 0.95
#   --min-p 0.05
#   --repeat-penalty 1.1
#
# 【Chat Template】
#   使用 GGUF 内置的 Qwen2.5-Instruct chat template
#   - 原生支持 <tool> 和 <tool_call> 标签
#   - 兼容 OpenAI function calling schema
#   - 支持多轮 tool use 对话
#
# 【使用建议】
#   1. Tool Call 温度建议 0.5-0.8 (本脚本使用 0.7)
#   2. 复杂任务可用 system prompt 设定角色
#   3. 代码生成任务建议明确指定语言和框架
# =============================================================
#
# 【启动方式】(必须用 setsid，否则终端关闭会终止服务)
#   cd /opt/my-shell/4090d
#   setsid nohup ./run_qwen25-14b-instruct_llama.sh > /tmp/14b_qwen25_llama.log 2>&1 < /dev/null &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/14b_qwen25_llama.log
#
# 【停止服务】
#   pkill -f "llama-server.*Qwen2.5-14B-Instruct"
#
# 【测试API】
#   curl http://localhost:11435/v1/models
#
#   # 基础对话
#   curl -s http://localhost:11435/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "Qwen2.5-14B-Instruct-Q4_K_M.gguf", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'
#
#   # Tool Call 测试 (函数调用)
#   curl -s http://localhost:11435/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{
#       "model": "Qwen2.5-14B-Instruct-Q4_K_M.gguf",
#       "messages": [{"role": "user", "content": "北京现在天气如何？"}],
#       "tools": [{
#         "type": "function",
#         "function": {
#           "name": "get_weather",
#           "description": "获取指定城市的天气",
#           "parameters": {
#             "type": "object",
#             "properties": {"city": {"type": "string", "description": "城市名"}},
#             "required": ["city"]
#           }
#         }
#       }],
#       "max_tokens": 512
#     }'
#
# =============================================================
# OpenCode 配置文件 (~/.config/opencode/opencode.json)
# =============================================================
# {
#   "$schema": "https://opencode.ai/config.json",
#   "model": "openai/Qwen2.5-14B-Instruct-Q4_K_M.gguf",
#   "provider": {
#     "openai": {
#       "npm": "@ai-sdk/openai-compatible",
#       "name": "Local Models",
#       "options": {
#         "baseURL": "http://localhost:11435/v1",
#         "apiKey": "dummy"
#       },
#       "models": {
#         "Qwen2.5-14B-Instruct-Q4_K_M.gguf": {
#           "name": "Qwen2.5-14B-Instruct Q4_K_M (4090D llama.cpp)",
#           "maxContextWindow": 131072,
#           "maxOutputTokens": 32768
#         }
#       }
#     }
#   }
# }
#
# 【使用 opencode】
#   opencode -m openai/Qwen2.5-14B-Instruct-Q4_K_M.gguf
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
MODEL_DIR="/opt/gguf/Qwen2.5-14B-Instruct-Q4_K_M.gguf"
LLAMA_SERVER="/opt/llama.cpp/bin/llama-server"

# 4090D 14B 模型参数 (24GB 显存充裕, 128K 上下文轻松运行)
NGL=99              # GPU层数 (全部加载到GPU)
CTX=131072          # 上下文 128K (4090D 24GB 轻松胜任)
BATCH=1024          # batch size (14B模型可适当增大)
UBATCH=1024         # micro batch size
THREADS=16          # CPU线程数

PORT=11435

echo "=============================="
echo "启动 Qwen2.5-14B-Instruct Q4_K_M (llama.cpp) API 服务"
echo "地址: http://0.0.0.0:$PORT"
echo "模型: Qwen2.5-14B-Instruct-Q4_K_M.gguf"
echo "上下文: $CTX"
echo "GPU层数: $NGL"
echo "Batch Size: $BATCH"
echo "uBatch Size: $UBATCH"
echo "Threads: $THREADS"
echo "Tool Call: 支持"
echo "=============================="
echo ""

# 检查模型文件是否存在
if [[ ! -f "$MODEL_DIR" ]]; then
    echo "错误: 模型文件不存在: $MODEL_DIR"
    echo "请先下载模型:"
    echo "  https://huggingface.co/bartowski/Qwen2.5-14B-Instruct-GGUF"
    exit 1
fi

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
  --temp 0.7 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.05 \
  --repeat-penalty 1.1 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --metrics

# 使用 GGUF 内置的 Qwen2.5-Instruct chat template (原生支持 Tool Call)
