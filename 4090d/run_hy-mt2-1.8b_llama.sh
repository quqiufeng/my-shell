#!/bin/bash
set -euo pipefail
#
# =============================================================
# Hy-MT2-1.8B (llama.cpp) API 启动脚本 (4090D 24GB) - 翻译专用
# =============================================================
#
# 模型: Hy-MT2-1.8B-Q8_0.gguf
# 来源: Tencent Hunyuan Hy-MT2 系列
# 类型: 专业多语言翻译模型 (fast-thinking translation model)
# 大小: ~1.8GB
# 支持: 36 种语言互译 (中/英/法/日/德/俄/韩/阿拉伯等)
#
# 【官方推荐参数】(1.8B/7B)
#   - temperature: 0.7
#   - top_p: 0.6
#   - top_k: 20
#   - repetition_penalty: 1.05
#   - max_tokens: 4096
#   - 无默认 system_prompt
#
# 【模型特点】
#   - "快思考"翻译模型，专为复杂真实场景设计
#   - 1.8B 轻量版即可超越主流商业 API (微软、豆包)
#   - 支持术语、风格、个性化、分隔符、结构化数据等翻译指令
#   - AngelSlim 1.25bit 量化可压缩至 440MB
#
# 【优化要点】
#   - ctx-size: 262144 (256K, 1.8B 模型显存占用极低)
#   - batch-size: 4096
#   - ubatch-size: 4096
#   - threads: 16
#   - --parallel 1 --slots 1: 减少slot开销
#   - --prio 2: 高优先级
#   - --flash-attn on + cache-type-k/v f16
#   - --mlock + --no-mmap
#   - --no-warmup: 跳过启动warmup, 大幅缩短启动时间
# =============================================================
#
# 【启动方式】
#   cd /opt/my-shell/4090d
#   nohup ./run_hy-mt2-1.8b_llama.sh > /tmp/hy_mt2_1.8b_llama.log 2>&1 &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/hy_mt2_1.8b_llama.log
#
# 【停止服务】
#   pkill -f llama-server
#
# 【测试API - 翻译示例】
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{
#       "model": "Hy-MT2-1.8B-Q8_0.gguf",
#       "messages": [
#         {"role": "user", "content": "将以下文本翻译成英语，注意只需要输出翻译后的结果，不要额外解释：\n\n今天天气真好。"}
#       ],
#       "max_tokens": 4096,
#       "temperature": 0.7,
#       "top_p": 0.6,
#       "top_k": 20
#     }'
#
# 【术语翻译示例】
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{
#       "model": "Hy-MT2-1.8B-Q8_0.gguf",
#       "messages": [
#         {"role": "user", "content": "参考下面的翻译：\n人工智能 翻译成 Artificial Intelligence\n机器学习 翻译成 Machine Learning\n将以下文本翻译为英语，注意只需要输出翻译后的结果，不要额外解释：\n\n深度学习是机器学习的一个子集。"}
#       ],
#       "max_tokens": 4096
#     }'
#
# =============================================================
# OpenCode 配置文件 (~/.config/opencode/opencode.json)
# =============================================================
# {
#   "$schema": "https://opencode.ai/config.json",
#   "model": "openai/Hy-MT2-1.8B-Q8_0.gguf",
#   "provider": {
#     "openai": {
#       "npm": "@ai-sdk/openai-compatible",
#       "name": "Local Models",
#       "options": {
#         "baseURL": "http://localhost:11434/v1",
#         "apiKey": "dummy"
#       },
#       "models": {
#         "Hy-MT2-1.8B-Q8_0.gguf": {
#           "name": "Hy-MT2-1.8B Q8_0 (Tencent Translation)",
#           "maxContextWindow": 262144,
#           "maxOutputTokens": 4096
#         }
#       }
#     }
#   }
# }
#
# 【使用 opencode】
#   opencode -m openai/Hy-MT2-1.8B-Q8_0.gguf
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
MODEL_DIR="/opt/gguf/Hy-MT2-1.8B-Q8_0.gguf"
LLAMA_SERVER="/opt/llama.cpp/bin/llama-server"

# 1.8B 翻译模型参数 (显存占用极低, 可支持大上下文)
NGL=99              # GPU层数 (全部加载到GPU)
CTX=65536           # 上下文 64K (翻译任务通常不需要太长上下文)
BATCH=2048          # batch size
UBATCH=2048         # micro batch size
THREADS=16          # CPU线程数

PORT=11434

echo "=============================="
echo "启动 Hy-MT2-1.8B Q8_0 (llama.cpp) API 服务"
echo "地址: http://0.0.0.0:$PORT"
echo "模型: Hy-MT2-1.8B-Q8_0.gguf"
echo "类型: 腾讯混元翻译模型 (36语言)"
echo "上下文: $CTX"
echo "GPU层数: $NGL"
echo "Batch Size: $BATCH"
echo "uBatch Size: $UBATCH"
echo "Threads: $THREADS"
echo "采样参数: temp=0.7, top_p=0.6, top_k=20"
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
  --temp 0.7 \
  --top-p 0.6 \
  --top-k 20 \
  --repeat-penalty 1.05 \
  --min-p 0.00 \
  --cache-type-k f16 \
  --cache-type-v f16 \
  --metrics

# 注意: 使用模型内置的chat template，不指定自定义模板
# 注意: 该模型无默认 system_prompt，翻译指令需放在 user message 中
