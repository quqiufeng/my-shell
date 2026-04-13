#!/bin/bash
#
# 【模型信息】
# 模型: Jackrong/Qwopus3.5-9B-v3-GGUF (GGUF Q5_K_S)
# 框架: KoboldCpp (优化版，目标 100+ tok/s)
# 显存占用: ~7GB (RTX 3080 10GB)
# 上下文: 128K (131072 tokens)
# KV量化: q4_0 (--quantkv 1)
#
# 【实测性能】2026-04-13 RTX 3080 10GB
#   快速排序: 53.6 tok/s
#   线程安全: 58.1 tok/s
#   二分查找: 59.1 tok/s
#   数据库索引: 57.8 tok/s
#   Python性能优化: 55.4 tok/s
#   归并排序: 58.7 tok/s
#   平均约: 57 tok/s
#
# 【优化策略】
# 1. 增大上下文到 128K
# 2. 使用 KV 量化 q4_0 控制显存
# 3. 启用 Flash Attention
# 4. 禁用不必要的功能
#

MODEL_DIR="/opt/image/Qwopus3.5-9B-v3-GGUF/Qwen3.5-9B.Q5_K_S.gguf"
KOBOLDCPP_DIR="/opt/koboldcpp"

export LD_LIBRARY_PATH=/usr/lib/wsl/lib:$LD_LIBRARY_PATH

# 优化参数
GPULAYERS=33        # GPU层数
CONTEXTSIZE=131072  # 上下文 128K
PORT=11434

echo "=============================="
echo "启动 Qwen3.5-9B 优化版 (KoboldCpp)"
echo "地址: http://0.0.0.0:$PORT"
echo "模型: Qwen3.5-9B.Q5_K_S.gguf"
echo "上下文: $CONTEXTSIZE"
echo "GPU层数: $GPULAYERS"
echo "目标: 100+ tok/s"
echo "=============================="
echo ""

cd "$KOBOLDCPP_DIR"

python koboldcpp.py \
  --model "$MODEL_DIR" \
  --port $PORT \
  --host 0.0.0.0 \
  --gpulayers $GPULAYERS \
  --contextsize $CONTEXTSIZE \
  --flashattention \
  --quantkv 1 \
  --quiet \
  --usemlock \
  --nommap
