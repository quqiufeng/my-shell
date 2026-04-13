#!/bin/bash
#
# 【模型信息】
# 模型: Jackrong/Qwopus3.5-9B-v3-GGUF (GGUF Q5_K_S)
# 框架: llama.cpp (优化版，目标 100+ tok/s)
# 显存占用: ~8GB (RTX 3080 10GB)
# 上下文: 128K (131072 tokens)
# KV量化: q4_0 (--cache-type-k q4_0 --cache-type-v q4_0)
#
# 【实测性能】2026-04-13 RTX 3080 10GB
#   [基础编译] 快速排序: 68.0, 线程安全: 81.7, 二分查找: 70.0, 数据库索引: 80.0
#              Python性能优化: 80.0, 归并排序: 65.2, HTTP/HTTPS: 77.9, LRU缓存: 78.1
#              平均约: 75.1 tok/s
#   [优化编译] 快速排序: 78.0, 线程安全: 78.3, 二分查找: 69.8, 数据库索引: 78.9
#              Python性能优化: 65.1, 归并排序: 80.3, HTTP/HTTPS: 76.6, LRU缓存: 69.5
#              平均约: 74.6 tok/s (编译优化边际递减，75 tok/s 左右为 3080 极限)
#   [编译优化选项] GGML_CUDA_FA=ON, GGML_CUDA_GRAPHS=ON, GGML_CUDA_FORCE_MMQ=ON, GGML_LTO=ON
#
# 【优化策略】
# 1. 增大上下文到 128K
# 2. 增大 batch size 到 512
# 3. 使用 q4_0 KV cache 控制显存
# 4. GPU 层数 33 (全部加载)
# 5. 启用 Flash Attention
# 6. 使用更大的 ubatch
#

MODEL_DIR="/opt/image/Qwopus3.5-9B-v3-GGUF/Qwen3.5-9B.Q5_K_S.gguf"
LLAMA_SERVER="$HOME/llama.cpp/build/bin/llama-server"

export LD_LIBRARY_PATH=/usr/lib/wsl/lib:$LD_LIBRARY_PATH

# 优化参数
NGL=33              # GPU层数 (全部加载)
CTX=131072          # 上下文 (128K)
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
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --metrics

# 注意: 使用模型内置的chat template，不指定自定义模板
