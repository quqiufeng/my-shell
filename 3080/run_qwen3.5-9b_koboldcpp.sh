#!/bin/bash
set -euo pipefail
#
# =============================================================
# Qwen3.5-9B (KoboldCpp) API 启动脚本 (RTX 3080 10GB) - 优化版
# =============================================================
#
# 【模型信息】
# 模型: Jackrong/Qwopus3.5-9B-v3-GGUF (GGUF Q5_K_S)
# 框架: KoboldCpp
# 显存占用: ~7.5GB (RTX 3080 10GB)
# 上下文: 128K (131072 tokens)
# KV量化: q4_0 (--quantkv 1)
#
# 【最新实测性能】2026-04-20 RTX 3080 10GB (Q5_K_S, BATCH=1024, CTX=128K, smartcache=0)
#   快速排序: 62.6, 线程安全: 52.8, 二分查找: 62.1, 数据库索引: 53.1
#   Python性能优化: 62.8, 归并排序: 53.1, HTTP/HTTPS: 62.8, LRU缓存: 52.6
#   堆排序: 61.5, Dijkstra算法: 51.5, 一致性哈希: 60.7, 令牌桶: 51.5
#   阻塞队列: 61.1, 红黑树: 52.0, B+树: 61.3, A*算法: 51.3
#   平均约: 57.5 tok/s (前16题, 显存: ~9788MiB)
#
# 【历史对照数据】
#   [2026-04-20 Q5_K_S 优化后] 平均约: 57.5 tok/s (当前基准)
#   [2026-04-16 Q5_K_S, BATCH=1024, CTX=128K, smartcache=0] 约 56.0 tok/s
#   [2026-04-16 Q4_K_M, BATCH=1024, CTX=128K, smartcache=0] 约 55.0 tok/s
#
# 【优化策略】(参考 llama.cpp 成功配置优化 KoboldCpp)
# 1. 上下文固定 128K (强制要求)
# 2. batchsize 从 2048 降到 1024 (2048 显存爆满 9699MiB，性能暴跌至 20-26 tok/s)
# 3. 显式启用 --usecuda 0，确保 CUDA 后端被调用
# 4. 关闭 --smartcache 0，消除 KV Save State 的重复开销
# 5. 增加 --highpriority (类似 llama.cpp 的 --prio 2)
# 6. 增加 --nopipelineparallel，单人使用减少并行开销
# 7. 去掉 --usemlock --nommap，避免拖慢速度
# 8. 使用 KV 量化 q4_0 控制显存
# 9. 启用 Flash Attention
# 10. 增加 threads/blasthreads 到 8 (与 CPU 核心匹配)
# 11. 注意: KoboldCpp 在 3080 10GB 上性能仍显著低于 llama.cpp (约 55 vs 77.4 tok/s)
#
# 【启动方式】
#   cd /opt/my-shell/3080
#   setsid ./run_qwen3.5-9b_koboldcpp.sh > /tmp/9b_koboldcpp_3080.log 2>&1 &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/9b_koboldcpp_3080.log
#
# 【停止服务】
#   pkill -f koboldcpp.py
#
# 【测试API】
#   curl http://localhost:11434/v1/models
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "Qwopus3.5-9B-v3.Q4_K_M.gguf", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'
#
# =============================================================

# 快速环境检查
if ! command -v nvidia-smi &> /dev/null; then
    echo "警告: nvidia-smi 未找到, 请确认 CUDA 驱动已安装"
fi
if [[ ! -f "/opt/koboldcpp/koboldcpp.py" ]]; then
    echo "错误: /opt/koboldcpp/koboldcpp.py 不存在"
    exit 1
fi

export LD_LIBRARY_PATH=/usr/lib/wsl/lib:${LD_LIBRARY_PATH:-}

# 3080 10GB 显存优化参数
MODEL_DIR="/opt/image/Qwopus3.5-9B-v3-GGUF/Qwopus3.5-9B-v3.Q5_K_S.gguf"
KOBOLDCPP_DIR="/opt/koboldcpp"

GPULAYERS=33          # GPU层数 (全部加载)
CONTEXTSIZE=131072    # 上下文 128K
BATCHSIZE=1024        # batch size (512/1024 速度接近，1024 能完整跑完 30 题)
THREADS=8             # CPU线程数
BLASTHREADS=8         # BLAS线程数
PORT=11434

echo "=============================="
echo "启动 Qwen3.5-9B Q5_K_S (KoboldCpp) API 服务"
echo "地址: http://0.0.0.0:$PORT"
echo "模型: Qwopus3.5-9B-v3.Q5_K_S.gguf"
echo "上下文: $CONTEXTSIZE"
echo "GPU层数: $GPULAYERS"
echo "Batch Size: $BATCHSIZE"
echo "Threads: $THREADS"
echo "Flash Attention: on"
echo "=============================="
echo ""

cd "$KOBOLDCPP_DIR"

python koboldcpp.py \
  "$MODEL_DIR" \
  $PORT \
  --host 0.0.0.0 \
  --gpulayers $GPULAYERS \
  --contextsize $CONTEXTSIZE \
  --batchsize $BATCHSIZE \
  --threads $THREADS \
  --blasthreads $BLASTHREADS \
  --usecuda 0 \
  --flashattention \
  --quantkv 1 \
  --highpriority \
  --smartcache 0 \
  --nopipelineparallel \
  --quiet
