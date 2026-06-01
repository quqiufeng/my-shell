#!/bin/bash
set -euo pipefail
#
# =============================================================
# Qwen3-14B-AWQ (vLLM) API 启动脚本 (RTX 3080 20GB)
# =============================================================
#
# 【模型主页】https://huggingface.co/Qwen/Qwen3-14B-AWQ
#
# 【模型介绍】
#   Qwen3-14B-AWQ 是 Qwen3-14B 的 AWQ INT4 量化版本
#   - 基础模型: Qwen3-14B, Architecture: qwen3
#   - 量化方式: AWQ 4-bit (Activation-aware Weight Quantization)
#   - 模型大小: ~8.5GB (Safetensors 格式, 目录结构)
#   - 参数量: 14.8B (非嵌入层 13.2B)
#   - 层数: 40, Attention Heads (GQA): 40 (Q) / 8 (KV)
#   - 上下文: 原生 32K，YaRN 扩展至 128K tokens
#   - Tool Call: 支持，兼容 OpenAI function calling 格式
#   - 思考模式: 支持 enable_thinking 和 /think /no_think 切换
#   - 许可证: Apache 2.0 (可商用)
#
# 【与 llama.cpp GGUF 对比】(RTX 3080 20GB)
#   ┌──────────────┬────────────────────┬─────────────────────────────┐
#   │ 特性         │ vLLM (AWQ)         │ llama.cpp (GGUF Q4_K_M)     │
#   ├──────────────┼────────────────────┼─────────────────────────────┤
#   │ 吞吐量       │ 高 (PagedAttention │ 中等                        │
#   │              │  + Continuous      │                             │
#   │              │    Batching)       │                             │
#   │ KV Cache     │ fp16 (不可量化)     │ 支持 q4_0 量化              │
#   │ 128K 上下文  │ ❌ OOM (需 ~21GB   │ ✅ 流畅运行                 │
#   │              │    KV cache)       │                             │
#   │ 64K 上下文   │ ⚠️ 极限 (batch=1)  │ ✅ 轻松运行                 │
#   │ 32K 上下文   │ ✅ 推荐            │ ✅ 推荐                     │
#   │ 启动速度     │ 较慢 (需编译 CUDA)  │ 较快                        │
#   │ API 兼容性   │ OpenAI 标准        │ OpenAI 标准                 │
#   │ Tool Call    │ 支持               │ 支持 (需 jinja template)    │
#   └──────────────┴────────────────────┴─────────────────────────────┘
#   - vLLM 优势: 高并发吞吐量、生产级服务框架、自动批处理
#   - vLLM 劣势: KV Cache 默认 fp16，3080 20GB 无法跑 128K
#   - 建议: 32K-64K 上下文且需要高吞吐时用 vLLM；128K 用 llama.cpp
#
# 【显存分析】(RTX 3080 20GB, AWQ INT4, KV Cache fp16)
#   - 模型权重: ~8.5GB
#   - KV Cache: ~160 KB/token (fp16, 40 layers, 8 KV heads)
#     * 32K: ~5.2GB, 总计 ~13-15GB (安全, batch>=1)
#     * 64K: ~10.5GB, 总计 ~18-20GB (极限, 仅 batch=1)
#     * 128K: ~21GB, 总计 ~29GB+ (OOM)
#   - 结论: 3080 20GB 上 vLLM 建议 32K；64K 为极限值
#
# 【上下文配置】(RTX 3080 20GB)
#   - 32K: 推荐, 模型 ~8.5GB + KV cache ~5.2GB, 余量 ~6GB
#   - 64K: 极限, 模型 ~8.5GB + KV cache ~10.5GB, 余量 ~1GB
#     * 必须设置 --gpu-memory-utilization 0.93
#     * 必须保证无其他显存占用程序
#   - 128K: 不可用 (vLLM KV cache fp16 导致 OOM)
#
# 【降级建议】(若启动时 OOM)
#   - 将 CTX 从 65536 降为 32768
#   - 降低 --gpu-memory-utilization 到 0.85
#   - 关闭浏览器/视频播放器等显存占用程序
#   - 或改用 llama.cpp 版本跑 128K
#
# 【优化要点】
#   - max-model-len: 32768 (32K, 推荐) 或 65536 (64K, 极限)
#   - gpu-memory-utilization: 0.85 (32K) 或 0.93 (64K)
#   - tensor-parallel-size: 1 (单卡)
#   - enable-reasoning: 解析 <think>...</think> 思考块
#   - reasoning-parser: deepseek_r1 (兼容 Qwen3 思考格式)
#   - chat-template-content-format: auto (自动处理 chat template)
#   - rope-scaling: YaRN (64K 时需要 factor=2.0)
#
# 【思考模式切换】(Qwen3 独有特性)
#   vLLM 通过 API 参数控制：
#   - 默认 enable_thinking=True，模型输出 <think>...</think>
#   - 设置 enable_thinking=False 关闭思考模式
#   - 用户输入中加 /think 或 /no_think 进行软切换
#
#   示例:
#   {"role": "user", "content": "计算 123 * 456"}           # 默认思考
#   {"role": "user", "content": "你好 /no_think"}             # 不思考
#
# 【推荐采样参数】
#   - 思考模式: temperature=0.6, top_p=0.95, top_k=20, min_p=0
#   - 非思考模式: temperature=0.7, top_p=0.8, top_k=20, min_p=0
#   - presence_penalty: 1.5 (量化模型推荐，抑制重复)
#   - 不要用贪心解码 (会导致性能下降和无限重复)
# =============================================================
#
# 【启动方式】(必须用 setsid，否则终端关闭会终止服务)
#   cd /opt/my-shell/3080
#   setsid nohup ./qwen3-14b_vllm.sh > /tmp/qwen3_14b_vllm.log 2>&1 < /dev/null &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/qwen3_14b_vllm.log
#
# 【停止服务】
#   pkill -f "vllm serve.*Qwen3-14B-AWQ"
#
# 【测试API】
#   curl http://localhost:11434/v1/models
#
#   # 基础对话
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "Qwen3-14B-AWQ", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'
#
#   # 思考模式测试
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "Qwen3-14B-AWQ", "messages": [{"role": "user", "content": "计算 123 * 456"}], "max_tokens": 512, "temperature": 0.6}'
#
#   # Tool Call 测试 (函数调用)
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{
#       "model": "Qwen3-14B-AWQ",
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
#   "model": "openai/Qwen3-14B-AWQ",
#   "provider": {
#     "openai": {
#       "npm": "@ai-sdk/openai-compatible",
#       "name": "Local Models",
#       "options": {
#         "baseURL": "http://localhost:11434/v1",
#         "apiKey": "dummy"
#       },
#       "models": {
#         "Qwen3-14B-AWQ": {
#           "name": "Qwen3-14B AWQ (3080 20GB vLLM)",
#           "maxContextWindow": 32768,
#           "maxOutputTokens": 32768
#         }
#       }
#     }
#   }
# }
#
# 【使用 opencode】
#   opencode -m openai/Qwen3-14B-AWQ
#
# =============================================================

# 快速环境检查
if ! command -v nvidia-smi &> /dev/null; then
    echo "警告: nvidia-smi 未找到, 请确认 CUDA 驱动已安装"
fi
VLLM_BIN="/data/venv/bin/vllm"
if [[ ! -x "$VLLM_BIN" ]]; then
    echo "错误: vllm 未找到: $VLLM_BIN"
    echo "请先安装: /data/venv/bin/pip install vllm"
    exit 1
fi

# 检查 vLLM 版本
VLLM_VERSION=$($VLLM_BIN --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "0.0.0")
if [[ "$VLLM_VERSION" < "0.8.5" ]]; then
    echo "警告: vLLM 版本 $VLLM_VERSION, 建议 >= 0.8.5 以获得完整的 Qwen3 支持"
fi

export LD_LIBRARY_PATH=/data/cuda/lib64:/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}

# =============================================================
# 模型配置
# =============================================================
# ⚠️ 请下载模型后修改此路径
# 方式1: 使用 HuggingFace 模型ID (首次启动会自动下载)
# MODEL_NAME="Qwen/Qwen3-14B-AWQ"
#
# 方式2: 使用本地绝对路径 (推荐, 避免重复下载)
MODEL_NAME="/data/models/Qwen3-14B-AWQ"

# RTX 3080 20GB 上下文配置
# vLLM KV cache 为 fp16，3080 20GB 无法跑 128K (需要 ~29GB)
# 经实测，推荐配置如下：
#   - 32K (32768): 推荐, 模型 ~8.5GB + KV cache ~5.2GB, 余量 ~6GB, 稳定
#   - 48K (49152): 极限, 模型 ~8.5GB + KV cache ~7.8GB, 余量 ~3GB, batch=1
#   - 64K+: 不可用 (OOM)
CTX=32768

# 显存使用比例
# 32K: 0.85 (安全，留余量给系统和其他进程)
# 48K: 0.90 (极限，必须关闭浏览器等 GPU 程序)
GPU_UTIL=0.85

PORT=11434

echo "=============================="
echo "启动 Qwen3-14B-AWQ (vLLM) API 服务"
echo "地址: http://0.0.0.0:$PORT"
echo "模型: $MODEL_NAME"
echo "上下文: $CTX"
echo "显存使用: ${GPU_UTIL}"
echo "推理框架: vLLM ${VLLM_VERSION}"
echo "思考模式: 支持 (enable-reasoning)"
echo "Tool Call: 支持"
echo "=============================="
echo ""

# 检查模型路径是否存在
if [[ ! -d "$MODEL_NAME" ]]; then
    echo "错误: 模型目录不存在: $MODEL_NAME"
    echo ""
    echo "请下载 Qwen3-14B-AWQ 模型:"
    echo "  huggingface-cli download Qwen/Qwen3-14B-AWQ --local-dir /data/models/Qwen3-14B-AWQ"
    echo ""
    echo "或修改此脚本中的 MODEL_NAME 为 HuggingFace 模型ID:"
    echo '  MODEL_NAME="Qwen/Qwen3-14B-AWQ"'
    exit 1
fi

# 检查关键文件
if [[ ! -f "$MODEL_NAME/config.json" ]]; then
    echo "错误: 模型目录缺少 config.json，可能不是有效的 HuggingFace 模型目录"
    exit 1
fi

# 构建 vLLM 启动参数
VLLM_ARGS=(
  --host 0.0.0.0
  --port "$PORT"
  --tensor-parallel-size 1
  --gpu-memory-utilization "$GPU_UTIL"
  --max-model-len "$CTX"
  --enable-reasoning
  --reasoning-parser deepseek_r1
  --chat-template-content-format auto
)

# 64K 上下文需要启用 YaRN
if [[ "$CTX" -gt 32768 ]]; then
    echo "启用 YaRN 上下文扩展: 32K -> $CTX"
    if [[ "$CTX" -eq 65536 ]]; then
        VLLM_ARGS+=(
          --rope-scaling '{"rope_type":"yarn","factor":2.0,"original_max_position_embeddings":32768}'
        )
    elif [[ "$CTX" -eq 131072 ]]; then
        echo "警告: 128K 上下文在 RTX 3080 20GB 上会 OOM (vLLM KV cache fp16 无法量化)"
        echo "建议改用 llama.cpp 版本 (支持 KV cache q4_0 量化)"
        VLLM_ARGS+=(
          --rope-scaling '{"rope_type":"yarn","factor":4.0,"original_max_position_embeddings":32768}'
        )
    fi
fi

echo "启动命令: $VLLM_BIN serve \"$MODEL_NAME\" ${VLLM_ARGS[*]}"
echo ""

exec "$VLLM_BIN" serve "$MODEL_NAME" "${VLLM_ARGS[@]}"

# vLLM 会自动处理 AWQ 量化和 Qwen3 chat template
# 思考模式通过 enable_thinking 参数控制 (默认 True)
