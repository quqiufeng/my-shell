#!/bin/bash
set -euo pipefail
#
# =============================================================
# DeepSeek-R1-Distill-Qwen-14B-AWQ (vLLM) API 启动脚本 (RTX 3080 20GB)
# =============================================================
#
# 【模型主页】https://huggingface.co/casperhansen/deepseek-r1-distill-qwen-14b-awq
#
# 【模型介绍】
#   DeepSeek-R1-Distill-Qwen-14B-AWQ 是 DeepSeek-R1 的蒸馏版本
#   - 基础模型: DeepSeek-R1-Distill-Qwen-14B, Architecture: qwen2
#   - 教师模型: DeepSeek-R1 (671B MoE)
#   - 量化方式: AWQ 4-bit (Activation-aware Weight Quantization)
#   - 模型大小: ~10GB (Safetensors 格式, 2 个分片)
#   - 参数量: 14B+ (48 层, 比标准 Qwen2.5-14B 多 8 层)
#   - 层数: 48, Attention Heads (GQA): 40 (Q) / 8 (KV)
#   - 上下文: 原生 128K tokens (max_position_embeddings=131072)
#     * 不需要 YaRN 扩展，原生支持长文本
#   - 思考模式: 始终思考 (R1 蒸馏特性，强制推理后回答)
#     * 不可关闭，所有回答都包含 <think>...</think>
#   - Tool Call: 支持
#   - 许可证: MIT (可商用)
#
# 【模型能力】
#   - 数学推理: 极强 (AIME 2024 72.0+, 超越 Qwen3-14B)
#   - 代码生成: 优秀 (支持复杂算法和调试)
#   - 逻辑推理: 深度思考，逐步推导
#   - 与原版 DeepSeek-R1 差距: 蒸馏版保留了大部分推理能力
#
# 【与 Qwen3-14B-AWQ 对比】(RTX 3080 20GB)
#   ┌──────────────┬─────────────────────────────┬─────────────────────────────┐
#   │ 特性         │ DeepSeek-R1-Distill-14B-AWQ │ Qwen3-14B-AWQ               │
#   ├──────────────┼─────────────────────────────┼─────────────────────────────┤
#   │ 架构         │ Qwen2 (48层)                │ Qwen3 (40层)                │
#   │ 思考模式     │ 始终思考 (强制)              │ 可切换 /think /no_think     │
#   │ 数学推理     │ ⭐⭐⭐⭐⭐ 极强               │ ⭐⭐⭐⭐ 强                  │
#   │ 代码生成     │ ⭐⭐⭐⭐⭐ 优秀               │ ⭐⭐⭐⭐ 良好                │
#   │ 原生上下文   │ 128K (无需扩展)              │ 32K (需 YaRN 扩到 128K)    │
#   │ 模型大小     │ ~10GB (48层稍大)            │ ~8.5GB                     │
#   │ Tool Call    │ 支持                        │ 支持                        │
#   │ 中文理解     │ ⭐⭐⭐⭐ 良好                │ ⭐⭐⭐⭐⭐ 优秀              │
#   └──────────────┴─────────────────────────────┴─────────────────────────────┘
#
# 【显存分析】(RTX 3080 20GB, AWQ INT4, KV Cache fp16, 48 层)
#   - 模型权重: ~10GB (比 Qwen3 多 8 层，权重稍大)
#   - KV Cache: ~192 KB/token (fp16, 48 layers, 8 KV heads, 5120 hidden)
#     * 16K: ~3.0GB, 总计 ~13-15GB (安全, 留足思考输出空间)
#     * 32K: ~6.1GB, 总计 ~16-18GB (可用但紧张)
#     * 48K: ~9.2GB, 总计 ~19-21GB (极限, batch=1, 容易 OOM)
#     * 64K+: OOM
#   - 结论: 3080 20GB 上 vLLM 建议 16K；32K 可用但 R1 思考输出长容易爆显存
#
# 【⚠️ 避坑要点】(RTX 3080 20GB 专用)
#   DeepSeek-R1 模型思考时会输出大量 <think>...</think> 标签
#   推理链 (CoT) 可能长达数千 token，远超普通模型输出
#   因此必须保守配置，给思考输出预留充足显存：
#   - max-model-len: 16384 (16K, 强烈推荐)
#     * 输入 + 输出 + 思考链总计不超过 16K
#     * 思考链本身可能占 4K-8K，留给输入和答案的空间需预留
#   - gpu-memory-utilization: 0.90 (给生成长思考链留余量)
#   - quantization: awq (必须显式指定，避免 vLLM 误判)
#   - served-model-name: 自定义别名，方便客户端调用
#
# 【VS Code Cline 插件兼容性】
#   - 客户端必须升级到最新版 Cline
#   - 新版会自动识别并折叠 <think>...</think> 标签
#   - 否则用户会看到大量思考过程的 "乱码"
#   - 服务端无需特殊配置，正常输出即可
#
# 【上下文配置】(RTX 3080 20GB)
#   - 16K: ⭐ 强烈推荐, 模型 ~10GB + KV cache ~3GB, 余量 ~7GB
#     * 给 R1 的长思考输出预留足够空间
#     * 多用户/长对话时也不易 OOM
#   - 32K: 可用但危险, 模型 ~10GB + KV cache ~6GB, 余量 ~4GB
#     * 一旦思考链过长 + 输入较长，极易触发 OOM
#   - 48K+: 不可用 (OOM)
#
# 【降级建议】(若启动时 OOM 或生成时崩溃)
#   - 将 CTX 从 32768 降为 16384
#   - 降低 --gpu-memory-utilization 到 0.85
#   - 缩短 max_tokens (比如 2048 而不是 4096)
#   - 或改用 llama.cpp 版本跑 128K (KV cache 可量化)
#
# 【优化要点】
#   - max-model-len: 16384 (16K, RTX 3080 20GB 推荐)
#   - gpu-memory-utilization: 0.90 (给思考输出留余量)
#   - quantization: awq (显式指定)
#   - served-model-name: deepseek-r1-14b (自定义别名)
#   - tensor-parallel-size: 1 (单卡)
#   - enable-reasoning: 必须开启，解析 <think>...</think>
#   - reasoning-parser: deepseek_r1 (兼容 R1 思考格式)
#   - 无需 rope-scaling: 原生 128K，不需要 YaRN
#
# 【思考模式】(R1 蒸馏特性)
#   DeepSeek-R1-Distill 模型始终处于思考模式：
#   - 所有回答都会先输出 <think>...推理过程...</think>
#   - 然后输出最终答案
#   - 不可关闭 (与 Qwen3 不同，没有 /no_think 选项)
#   - 多轮对话中，历史记录应去掉 thinking content
#
# 【推荐采样参数】(思考模式)
#   - temperature: 0.6
#   - top_p: 0.95
#   - top_k: 20
#   - min_p: 0
#   - presence_penalty: 1.5 (量化模型推荐，抑制重复)
#   - 不要用贪心解码 (会导致性能下降和无限重复)
#   - max_tokens: 32768 (给足思考空间)
# =============================================================
#
# 【启动方式】(必须用 setsid，否则终端关闭会终止服务)
#   cd /opt/my-shell/3080
#   setsid nohup ./deepseek-r1-distill-qwen-14b-awq_vllm.sh > /tmp/deepseek_r1_14b_vllm.log 2>&1 < /dev/null &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/deepseek_r1_14b_vllm.log
#
# 【停止服务】
#   pkill -f "vllm serve.*deepseek-r1-distill-qwen-14b-awq"
#
# 【测试API】
#   curl http://localhost:11434/v1/models
#
#   # 基础对话 (始终包含思考过程)
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "deepseek-r1-14b", "messages": [{"role": "user", "content": "计算 123 * 456"}], "max_tokens": 2048, "temperature": 0.6}'
#
#   # 数学推理测试
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{
#       "model": "deepseek-r1-14b",
#       "messages": [{"role": "user", "content": "解方程: 2x^2 - 5x + 3 = 0"}],
#       "max_tokens": 2048,
#       "temperature": 0.6
#     }'
#
#   # 代码生成测试
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{
#       "model": "deepseek-r1-14b",
#       "messages": [{"role": "user", "content": "用 Python 写一个快速排序算法，并解释原理"}],
#       "max_tokens": 2048,
#       "temperature": 0.6
#     }'
#
#   # Tool Call 测试 (函数调用)
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{
#       "model": "deepseek-r1-14b",
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
#       "max_tokens": 2048
#     }'
#
# =============================================================
# OpenCode 配置文件 (~/.config/opencode/opencode.json)
# =============================================================
# {
#   "$schema": "https://opencode.ai/config.json",
#   "model": "openai/deepseek-r1-distill-qwen-14b-awq",
#   "provider": {
#     "openai": {
#       "npm": "@ai-sdk/openai-compatible",
#       "name": "Local Models",
#       "options": {
#         "baseURL": "http://localhost:11434/v1",
#         "apiKey": "dummy"
#       },
#       "models": {
#         "deepseek-r1-distill-qwen-14b-awq": {
#           "name": "DeepSeek-R1-Distill-Qwen-14B-AWQ (3080 20GB vLLM)",
#           "maxContextWindow": 32768,
#           "maxOutputTokens": 32768
#         }
#       }
#     }
#   }
# }
#
# 【使用 opencode】
#   opencode -m openai/deepseek-r1-distill-qwen-14b-awq
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
    echo "警告: vLLM 版本 $VLLM_VERSION, 建议 >= 0.8.5 以获得完整的 Qwen2 支持"
fi

export LD_LIBRARY_PATH=/data/cuda/lib64:/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}

# =============================================================
# 模型配置
# =============================================================
# 本地模型路径 (已下载)
MODEL_NAME="/data/models/deepseek-r1-distill-qwen-14b-awq"

# RTX 3080 20GB 上下文配置
# ⚠️ DeepSeek-R1 思考链极长，必须保守配置防止 OOM
# 推荐配置如下：
#   - 16K (16384): ⭐ 强烈推荐, 模型 ~10GB + KV cache ~3GB, 余量 ~7GB
#     * 给 R1 的长思考输出 (4K-8K tokens) 预留充足空间
#     * 多用户/长对话场景安全稳定
#   - 32K (32768): 可用但危险, 思考链一长就爆显存
#   - 48K+: 不可用 (OOM)
CTX=16384

# 显存使用比例
# 16K: 0.90 (给思考输出留余量，避免生成时长文本导致 OOM)
# 如需更安全可降到 0.85
GPU_UTIL=0.90

PORT=11434

echo "=============================="
echo "启动 DeepSeek-R1-Distill-Qwen-14B-AWQ (vLLM) API 服务"
echo "地址: http://0.0.0.0:$PORT"
echo "模型: $MODEL_NAME"
echo "上下文: $CTX"
echo "显存使用: ${GPU_UTIL}"
echo "推理框架: vLLM ${VLLM_VERSION}"
echo "思考模式: 始终思考 (R1 蒸馏)"
echo "Tool Call: 支持"
echo "=============================="
echo ""

# 检查模型路径是否存在
if [[ ! -d "$MODEL_NAME" ]]; then
    echo "错误: 模型目录不存在: $MODEL_NAME"
    echo ""
    echo "请下载 DeepSeek-R1-Distill-Qwen-14B-AWQ 模型:"
    echo "  huggingface-cli download casperhansen/deepseek-r1-distill-qwen-14b-awq --local-dir /data/models/deepseek-r1-distill-qwen-14b-awq"
    echo ""
    echo "或修改此脚本中的 MODEL_NAME 为 HuggingFace 模型ID:"
    echo '  MODEL_NAME="casperhansen/deepseek-r1-distill-qwen-14b-awq"'
    exit 1
fi

# 检查关键文件
if [[ ! -f "$MODEL_NAME/config.json" ]]; then
    echo "错误: 模型目录缺少 config.json，可能不是有效的 HuggingFace 模型目录"
    exit 1
fi

# 构建 vLLM 启动参数
# ⚠️ 避坑: 必须显式指定 --quantization awq，否则 vLLM 可能误判
# ⚠️ 避坑: 必须设置 --served-model-name，客户端调用更简洁
VLLM_ARGS=(
  --host 0.0.0.0
  --port "$PORT"
  --quantization awq
  --served-model-name "deepseek-r1-14b"
  --tensor-parallel-size 1
  --gpu-memory-utilization "$GPU_UTIL"
  --max-model-len "$CTX"
  --enable-reasoning
  --reasoning-parser deepseek_r1
  --chat-template-content-format auto
)

# DeepSeek-R1-Distill-Qwen 原生支持 128K，不需要 YaRN
# 但 3080 20GB 只能跑 16K 安全 / 32K 紧张
if [[ "$CTX" -gt 32768 ]]; then
    echo "⚠️  警告: $CTX 上下文在 RTX 3080 20GB 上极大概率 OOM"
    echo "    R1 思考链很长，建议保持 16K 配置"
fi

echo "启动命令: $VLLM_BIN serve \"$MODEL_NAME\" ${VLLM_ARGS[*]}"
echo ""

exec "$VLLM_BIN" serve "$MODEL_NAME" "${VLLM_ARGS[@]}"

# vLLM 会自动处理 AWQ 量化和 Qwen2 chat template
# DeepSeek-R1-Distill 始终输出 <think>...</think> 思考块
