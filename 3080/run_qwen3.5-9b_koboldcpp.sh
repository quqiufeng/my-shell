#!/bin/bash
#
# 【模型信息】
# 模型: Jackrong/Qwopus3.5-9B-v3-GGUF (GGUF Q5_K_S)
# 框架: KoboldCpp (优化版，目标 100+ tok/s)
# 显存占用: ~7GB (RTX 3080 10GB)
# 上下文: 8K (减少KV缓存提高速度)
#
# 【优化策略】
# 1. 减小上下文到 8K
# 2. 使用 smartcontext 优化
# 3. 禁用不必要的功能
# 4. 使用合适的量化级别
#

MODEL_DIR="/opt/image/Qwopus3.5-9B-v3-GGUF/Qwen3.5-9B.Q5_K_S.gguf"
KOBOLDCPP_DIR="/opt/koboldcpp"

export LD_LIBRARY_PATH=/usr/lib/wsl/lib:$LD_LIBRARY_PATH

# 优化参数
GPULAYERS=33        # GPU层数
CONTEXTSIZE=8192    # 上下文 8K (从128K减少)
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
  --quiet \
  --usemlock \
  --nommap
