#!/bin/bash
set -euo pipefail
#
# =============================================================
# Qwen3.5-9B (llama.cpp) API 启动脚本 (RTX 3080 10GB) - 优化版
# =============================================================
#
# 【模型信息】
# 模型: Jackrong/Qwopus3.5-9B-v3-GGUF (GGUF Q4_K_M)
# 框架: llama.cpp
# 显存占用: ~8.0GB (RTX 3080 10GB)
# 上下文: 128K (131072 tokens)
# KV量化: q4_0 (--cache-type-k q4_0 --cache-type-v q4_0)
#
# 【实测性能】2026-04-16 RTX 3080 10GB (当前脚本参数: Q4_K_M, BATCH=1024, CTX=128K)
#   快速排序: 77.7, 线程安全: 69.5, 二分查找: 86.8, 数据库索引: 86.6
#   Python性能优化: 68.6, 归并排序: 86.5, HTTP/HTTPS: 69.2, LRU缓存: 86.8
#   堆排序: 84.3, Dijkstra算法: 86.4, 一致性哈希: 63.2, 令牌桶: 85.3
#   阻塞队列: 79.7, 红黑树: 73.7, B+树: 83.3, A*算法: 85.8
#   KMP算法: 68.9, 布隆过滤器: 82.8, 跳表: 67.0, 并查集: 83.4
#   线段树: 83.2, 字典树: 66.4, 最小生成树: 85.6, 拓扑排序: 69.0
#   最长公共子序列: 85.4, 编辑距离: 82.2, 滑动窗口: 67.7, 双指针: 84.0
#   动态规划: 83.2, 贪心算法: 67.2
#   平均约: 77.4 tok/s (test_api.py 30题, max_tokens=1024, 总token数: 30720, 显存: 8136MiB)
#
# 【历史对照数据】
#   [2026-04-16 Q5_K_S, BATCH=1024, CTX=128K] 平均约: 72.6 tok/s (显存: 8777MiB)
#   [2026-04-16 Q5_K_S, BATCH=1024, CTX=64K] 平均约: 79.0 tok/s
#   [2026-04-16 Q5_K_S, BATCH=2048, CTX=128K] 平均约: 69.9 tok/s (显存爆满 9463MiB)
#   [2026-04-16 Q5_K_S, BATCH=512, CTX=128K] 平均约: 57.5 tok/s (后半段暴跌)
#   [2026-04-13 Q5_K_S 旧参数] 平均约: 75.1 tok/s
#   [编译优化选项] GGML_CUDA_FA=ON, GGML_CUDA_GRAPHS=ON, GGML_CUDA_FORCE_MMQ=ON, GGML_LTO=ON
#
# 【优化策略】(参考 4090D 脚本优化)
# 1. 上下文固定 128K (强制要求)
# 2. batch size 从 512 提升到 1024 (单人使用无需 2048，避免 128K 下显存吃紧)
# 3. ubatch size 同步提升到 1024
# 4. 使用 q4_0 KV cache 控制显存 (10GB 显存必须保留)
# 5. GPU 层数 33 (全部加载)
# 6. 启用 Flash Attention
# 7. 增加 --prio 2 (高优先级)
# 8. 增加 --no-warmup (跳过启动 warmup，大幅缩短启动时间)
# 9. 增加 --parallel 1 --slots 1 (减少 slot 开销)
# 10. 温度从 0.6 降到 0.4 (与 4090D 保持一致)
#
# 【启动方式】
#   cd /opt/my-shell/3080
#   nohup ./run_qwen3.5-9b_llama.sh > /tmp/9b_llama_3080.log 2>&1 &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/9b_llama_3080.log
#
# 【停止服务】
#   pkill -f llama-server
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
if [[ ! -x "$HOME/llama.cpp/build/bin/llama-server" ]]; then
    echo "错误: $HOME/llama.cpp/build/bin/llama-server 不存在或不可执行"
    exit 1
fi

export LD_LIBRARY_PATH=/usr/lib/wsl/lib:${LD_LIBRARY_PATH:-}

# 3080 10GB 显存优化参数
MODEL_DIR="/opt/image/Qwopus3.5-9B-v3-GGUF/Qwopus3.5-9B-v3.Q5_K_S.gguf"
LLAMA_SERVER="$HOME/llama.cpp/build/bin/llama-server"

NGL=33              # GPU层数 (全部加载)
CTX=131072          # 上下文 128K (强制要求)
BATCH=1024          # batch size (128K 下 1024 最佳，512 后半段性能暴跌)
UBATCH=1024         # micro batch size
THREADS=8           # CPU线程数 (3080 为 8C16T，8 线程较稳)

PORT=11434

echo "=============================="
echo "启动 Qwen3.5-9B Q5_K_S (llama.cpp) API 服务"
echo "地址: http://0.0.0.0:$PORT"
echo "模型: Qwopus3.5-9B-v3.Q5_K_S.gguf"
echo "上下文: $CTX"
echo "GPU层数: $NGL"
echo "Batch Size: $BATCH"
echo "uBatch Size: $UBATCH"
echo "Threads: $THREADS"
echo "目标: 75+ tok/s"
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
  --temp 0.4 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.00 \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --metrics

# 注意: 使用模型内置的chat template，不指定自定义模板
