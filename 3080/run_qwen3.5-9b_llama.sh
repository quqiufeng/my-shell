#!/bin/bash
#
# 【模型信息】
# 模型: Jackrong/Qwopus3.5-9B-v3-GGUF (GGUF Q5_K_S)
# 框架: llama.cpp (优化版，目标 100+ tok/s)
# 显存占用: ~8GB (RTX 3080 10GB)
# 上下文: 8K (8192 tokens) - 减少KV缓存提高速度
#
# 【优化策略】
# 1. 减小上下文到 8K，减少KV缓存占用
# 2. 增大 batch size 到 512
# 3. 使用 f16 KV cache 而非 bf16
# 4. 减少 GPU 层数到 33 (刚好全部加载)
# 5. 启用 CUDA graphs
# 6. 使用更大的 ubatch
#

MODEL_DIR="/opt/image/Qwopus3.5-9B-v3-GGUF/Qwen3.5-9B.Q5_K_S.gguf"
LLAMA_SERVER="$HOME/llama.cpp/build/bin/llama-server"

export LD_LIBRARY_PATH=/usr/lib/wsl/lib:$LD_LIBRARY_PATH

# 优化参数
NGL=33              # GPU层数 (全部加载)
CTX=8192            # 上下文 (8K，平衡速度和内存)
BATCH=512           # batch size (增大)
UBATCH=512          # micro batch size
THREADS=8           # CPU线程数

PORT=11434

echo "=============================="
echo "启动 Qwen3.5-9B 优化版 (llama.cpp)"
echo "地址: http://0.0.0.0:$PORT"
echo "模型: Qwen3.5-9B.Q5_K_S.gguf"
echo "上下文: $CTX"
echo "GPU层数: $NGL"
echo "Batch Size: $BATCH"
echo "uBatch Size: $UBATCH"
echo "Threads: $THREADS"
echo "目标: 100+ tok/s"
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
  --no-mmap \
  --mlock \
  --temp 0.6 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.00 \
  --cache-type-k f16 \
  --cache-type-v f16 \
  --metrics

# 注意: 使用模型内置的chat template，不指定自定义模板
