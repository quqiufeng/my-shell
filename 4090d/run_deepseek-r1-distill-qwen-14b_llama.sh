#!/bin/bash
set -euo pipefail
#
# =============================================================
# DeepSeek-R1-Distill-Qwen-14B (llama.cpp) API 启动脚本 (4090D 24GB)
# =============================================================
#
# 【模型主页】https://huggingface.co/unsloth/DeepSeek-R1-Distill-Qwen-14B-GGUF
#
# 【模型介绍】
#   DeepSeek-R1-Distill-Qwen-14B 是基于 Qwen2.5-14B 的推理蒸馏模型
#   - 基础模型: Qwen2.5-14B, Architecture: qwen2
#   - 训练数据: 使用 DeepSeek-R1 生成的 800k 样本进行微调
#   - 核心能力: 数学推理、代码生成、逻辑推理、长思维链 (CoT)
#   - 特点: 14B 参数量，Q5_K_M 量化约 10.5GB，平衡质量与速度
#   - 评估数据:
#     * AIME 2024: 69.7% (pass@1), 80.0% (cons@64)
#     * MATH-500: 93.9% (pass@1)
#     * GPQA Diamond: 59.1%
#     * LiveCodeBench: 53.1%
#     * CodeForces Rating: 1481
#   - 论文: arXiv:2501.12948
#   - 许可证: MIT (代码和权重) + Apache 2.0 (Qwen 基础模型)
#
# 【推荐】4090D 上 14B 模型高效方案
# llama.cpp 全载 GPU，128K 上下文无压力
# =============================================================
#
# 【上下文配置】(4090D 24GB)
#   - 128K: 轻松运行, 14B Q5_K_M 权重约 9.5GB
#   - 无需 KV cache 量化即可跑满 128K
#   - 若需更大上下文可尝试 192K 或 256K
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
#   --temp 0.6: 推理模型需要一定创造性 (官方建议 0.5-0.7, 推荐 0.6)
#   --top-p 0.95: 官方推荐参数
#   --min-p 0.05
#   --repeat-penalty 1.1
#
# 【Chat Template 配置】(重要!)
#   DeepSeek-R1-Distill-Qwen 使用特殊对话格式:
#     - User token:    <｜User｜>
#     - Assistant token: <｜Assistant｜>
#   官方建议: 使用 chat template formatter 或手动添加这些 token
#   本脚本已配置 jinja chat template，自动处理这些特殊 token
#
#   Chat Template 文件: /opt/my-shell/4090d/deepseek-r1-qwen-chat-template.jinja
#   - 自动将 system prompt 合并到第一个 user prompt (符合官方建议)
#   - 正确处理 <｜User｜> 和 <｜Assistant｜> token
#   - 支持多轮对话
#
# 【使用建议】(来自官方 Model Card)
#   1. 温度建议 0.5-0.7 (本脚本使用 0.6)，避免无限重复或不连贯输出
#   2. 避免添加 system prompt，所有指令应放在 user prompt 中
#   3. 数学问题建议在 prompt 中加入: "Please reason step by step, and put your final answer within \boxed{}"
#   4. 评估时建议多次测试取平均结果
#   5. 由于模型使用 <think>...</think> 输出推理过程，客户端需正确处理 thinking block
# =============================================================
#
# 【启动方式】(必须用 setsid，否则终端关闭会终止服务)
#   cd /opt/my-shell/4090d
#   setsid nohup ./run_deepseek-r1-distill-qwen-14b_llama.sh > /tmp/14b_deepseek_llama.log 2>&1 < /dev/null &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/14b_deepseek_llama.log
#
# 【停止服务】
#   pkill -f "llama-server.*DeepSeek-R1-Distill-Qwen-14B"
#
# 【测试API】(注意: 不要包含 system prompt)
#   curl http://localhost:11434/v1/models
#
#   # 基础对话 (无 system prompt)
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "DeepSeek-R1-Distill-Qwen-14B-Q5_K_M.gguf", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'
#
#   # 数学问题 (包含推理指令，模型会输出 <think>...</think> 推理过程)
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{
#       "model": "DeepSeek-R1-Distill-Qwen-14B-Q5_K_M.gguf",
#       "messages": [{"role": "user", "content": "Please reason step by step, and put your final answer within \\boxed{}. What is 1+1?"}],
#       "max_tokens": 1024,
#       "temperature": 0.6
#     }'
#
# =============================================================
# OpenCode 配置文件 (~/.config/opencode/opencode.json)
# =============================================================
# {
#   "$schema": "https://opencode.ai/config.json",
#   "model": "openai/DeepSeek-R1-Distill-Qwen-14B-Q5_K_M.gguf",
#   "provider": {
#     "openai": {
#       "npm": "@ai-sdk/openai-compatible",
#       "name": "Local Models",
#       "options": {
#         "baseURL": "http://localhost:11434/v1",
#         "apiKey": "dummy"
#       },
#       "models": {
#         "DeepSeek-R1-Distill-Qwen-14B-Q5_K_M.gguf": {
#           "name": "DeepSeek-R1-Distill-Qwen-14B Q5_K_M (4090D)",
#           "maxContextWindow": 131072,
#           "maxOutputTokens": 32768
#         }
#       }
#     }
#   }
# }
#
# 【使用 opencode】
#   opencode -m openai/DeepSeek-R1-Distill-Qwen-14B-Q5_K_M.gguf
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
MODEL_DIR="/opt/gguf/DeepSeek-R1-Distill-Qwen-14B-Q5_K_M.gguf"
LLAMA_SERVER="/opt/llama.cpp/bin/llama-server"
CHAT_TEMPLATE="/opt/my-shell/4090d/deepseek-r1-qwen-chat-template.jinja"

# 4090D 14B 模型参数 (24GB 显存充裕, 128K 上下文轻松运行)
NGL=99              # GPU层数 (全部加载到GPU)
CTX=131072          # 上下文 128K (4090D 24GB 轻松胜任)
BATCH=1024          # batch size (14B模型可适当增大)
UBATCH=1024         # micro batch size
THREADS=16          # CPU线程数

PORT=11434

echo "=============================="
echo "启动 DeepSeek-R1-Distill-Qwen-14B Q5_K_M (llama.cpp) API 服务"
echo "地址: http://0.0.0.0:$PORT"
echo "模型: DeepSeek-R1-Distill-Qwen-14B-Q5_K_M.gguf"
echo "上下文: $CTX"
echo "GPU层数: $NGL"
echo "Batch Size: $BATCH"
echo "uBatch Size: $UBATCH"
echo "Threads: $THREADS"
echo "Chat Template: $CHAT_TEMPLATE"
echo "=============================="
echo ""

# 构建 llama-server 参数
LLAMA_ARGS=(
  -m "$MODEL_DIR"
  --host 0.0.0.0
  --port $PORT
  -ngl $NGL
  -c $CTX
  --batch-size $BATCH
  --ubatch-size $UBATCH
  --flash-attn on
  --threads $THREADS
  --threads-batch $THREADS
  --prio 2
  --no-mmap
  --no-warmup
  --parallel 1
  --temp 0.6
  --top-p 0.95
  --top-k 20
  --min-p 0.05
  --repeat-penalty 1.1
  --metrics
  --jinja
)

# 如果外部 chat template 文件存在，使用它
if [[ -f "$CHAT_TEMPLATE" ]]; then
  echo "使用外部 Chat Template: $CHAT_TEMPLATE"
  CHAT_TEMPLATE_CONTENT=$(cat "$CHAT_TEMPLATE")
  LLAMA_ARGS+=(--chat-template "$CHAT_TEMPLATE_CONTENT")
else
  echo "外部 Chat Template 文件不存在，使用 GGUF 内置模板"
fi

exec $LLAMA_SERVER "${LLAMA_ARGS[@]}"
