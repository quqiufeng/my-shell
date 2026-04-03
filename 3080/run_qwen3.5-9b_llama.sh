#!/bin/bash
#
# 【模型信息】
# 模型: Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled (GGUF Q4_K_M)
# 框架: llama.cpp
# 显存占用: ~6GB (RTX 3080 10GB)
# 上下文: 64K (262144 tokens, 实际可用 ~64K)
#
# 【性能测试数据 - 30个高难度提示词】
# 平均速度: 67.5 tokens/s
# 最快: Dijkstra算法 77.2 tokens/s
# 最慢: 快速排序 53.0 tokens/s (首次加载)
# 典型速度: 65-75 tokens/s
#
# 【测试方法】
# cd /home/dministrator/my-shell
# python3 branch.py 11434 "Qwen3.5-9B.Q4_K_M.gguf" 200
#
# 【对比其他框架】
# llama.cpp: 67.5 tokens/s (当前)
# KoboldCpp: 60.2 tokens/s
# ExLlamaV2 7B: 78.4 tokens/s
#

MODEL_DIR="/opt/image/Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled/Qwen3.5-9B.Q5_K_S.gguf"
LLAMA_SERVER="$HOME/llama.cpp/build/bin/llama-server"

export LD_LIBRARY_PATH=/usr/lib/wsl/lib:$LD_LIBRARY_PATH

echo "=============================="
echo "启动 Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled API 服务 (3080)"
echo "地址: http://0.0.0.0:11434"
echo "模型: Qwen3.5-9B-Q5_K_S.gguf"
echo "上下文参数: -c 262144"
echo "实际上下文: ~64K"
echo "GPU层数: 35"
echo "Batch Size: 256"
echo "Max Output: 4096 tokens (~200行代码)"
echo "Flash Attention: on"
echo "KV Cache: q4_0"
echo "Threads: 12"
echo "Parallel: 1"
echo "=============================="
echo ""
# echo "📝 上下文参数说明:"
# echo "| -c 参数值 | 实际上下文 |"
# echo "|-----------|------------|"
# echo "| 65536     | 16384      |"
# echo "| 131072    | 32768      |"
# echo "| 262144    | 65536      |"
# echo ""
echo "⚠️ Windows 端口转发命令 (在 Windows PowerShell 管理员运行):"
echo "# 删除旧转发:"
echo "netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=11434"
echo ""
echo "# 添加新转发 (转发到 WSL2):"
echo "netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=11434 connectaddress=172.23.212.172 connectport=11434"
echo ""
echo "# 查看转发状态:"
echo "netsh interface portproxy show all"
echo "=============================="
echo ""

$LLAMA_SERVER \
  -m "$MODEL_DIR" \
  --host 0.0.0.0 \
  --port 11434 \
  -ngl 35 \
  -c 262144 \
  --batch-size 256 \
  --flash-attn on \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --threads 12 \
  --parallel 1 \
  --n-predict 4096 \
  --no-mmap \
  --mlock \
  --jinja \
  --temp 0

# =============================================================================
# 性能测试代码 - 用于评估模型推理性能
# 注意：使用 usage 字段获取准确 token 数，而非字符数
# 使用方法: 每次运行下面的 python 命令跑一个提示词，连续运行15次
# =============================================================================

# 测试1: 红黑树
# python3 -c "
# import requests, time
# url = 'http://localhost:11434/v1/chat/completions'
# data = {'model': 'qwen3.5-9b', 'messages': [{'role': 'user', 'content': '用Python实现一个红黑树数据结构'}], 'max_tokens': 800, 'stream': False}
# t = time.time()
# r = requests.post(url, json=data, timeout=60).json()
# elapsed = time.time() - t
# gen_tokens = r['usage']['completion_tokens']
# print(f'{gen_tokens} tokens / {elapsed:.2f}s = {gen_tokens/elapsed:.1f} tokens/s')
# "

# 测试2: B+树
# python3 -c "
# import requests, time
# url = 'http://localhost:11434/v1/chat/completions'
# data = {'model': 'qwen3.5-9b', 'messages': [{'role': 'user', 'content': '用Python实现一个B+树'}], 'max_tokens': 800, 'stream': False}
# t = time.time()
# r = requests.post(url, json=data, timeout=60).json()
# elapsed = time.time() - t
# gen_tokens = r['usage']['completion_tokens']
# print(f'{gen_tokens} tokens / {elapsed:.2f}s = {gen_tokens/elapsed:.1f} tokens/s')
# "

# 测试3: A*寻路
# python3 -c "
# import requests, time
# url = 'http://localhost:11434/v1/chat/completions'
# data = {'model': 'qwen3.5-9b', 'messages': [{'role': 'user', 'content': '用Python实现一个A*寻路算法'}], 'max_tokens': 800, 'stream': False}
# t = time.time()
# r = requests.post(url, json=data, timeout=60).json()
# elapsed = time.time() - t
# gen_tokens = r['usage']['completion_tokens']
# print(f'{gen_tokens} tokens / {elapsed:.2f}s = {gen_tokens/elapsed:.1f} tokens/s')
# "

# 测试4: 布隆过滤器
# python3 -c "
# import requests, time
# url = 'http://localhost:11434/v1/chat/completions'
# data = {'model': 'qwen3.5-9b', 'messages': [{'role': 'user', 'content': '用Python实现一个布隆过滤器'}], 'max_tokens': 800, 'stream': False}
# t = time.time()
# r = requests.post(url, json=data, timeout=60).json()
# elapsed = time.time() - t
# gen_tokens = r['usage']['completion_tokens']
# print(f'{gen_tokens} tokens / {elapsed:.2f}s = {gen_tokens/elapsed:.1f} tokens/s')
# "

# 测试5: LRU-K缓存
# python3 -c "
# import requests, time
# url = 'http://localhost:11434/v1/chat/completions'
# data = {'model': 'qwen3.5-9b', 'messages': [{'role': 'user', 'content': '用Python实现一个LRU-K缓存淘汰算法'}], 'max_tokens': 800, 'stream': False}
# t = time.time()
# r = requests.post(url, json=data, timeout=60).json()
# elapsed = time.time() - t
# gen_tokens = r['usage']['completion_tokens']
# print(f'{gen_tokens} tokens / {elapsed:.2f}s = {gen_tokens/elapsed:.1f} tokens/s')
# "

# 测试6: 阻塞队列
# python3 -c "
# import requests, time
# url = 'http://localhost:11434/v1/chat/completions'
# data = {'model': 'qwen3.5-9b', 'messages': [{'role': 'user', 'content': '用Python实现一个线程安全的阻塞队列'}], 'max_tokens': 800, 'stream': False}
# t = time.time()
# r = requests.post(url, json=data, timeout=60).json()
# elapsed = time.time() - t
# gen_tokens = r['usage']['completion_tokens']
# print(f'{gen_tokens} tokens / {elapsed:.2f}s = {gen_tokens/elapsed:.1f} tokens/s')
# "

# 测试7: CAS队列
# python3 -c "
# import requests, time
# url = 'http://localhost:11434/v1/chat/completions'
# data = {'model': 'qwen3.5-9b', 'messages': [{'role': 'user', 'content': '用Python实现一个无锁CAS队列'}], 'max_tokens': 800, 'stream': False}
# t = time.time()
# r = requests.post(url, json=data, timeout=60).json()
# elapsed = time.time() - t
# gen_tokens = r['usage']['completion_tokens']
# print(f'{gen_tokens} tokens / {elapsed:.2f}s = {gen_tokens/elapsed:.1f} tokens/s')
# "

# 测试8: 外排序
# python3 -c "
# import requests, time
# url = 'http://localhost:11434/v1/chat/completions'
# data = {'model': 'qwen3.5-9b', 'messages': [{'role': 'user', 'content': '用Python实现一个支持亿级数据排序的外排序算法'}], 'max_tokens': 800, 'stream': False}
# t = time.time()
# r = requests.post(url, json=data, timeout=60).json()
# elapsed = time.time() - t
# gen_tokens = r['usage']['completion_tokens']
# print(f'{gen_tokens} tokens / {elapsed:.2f}s = {gen_tokens/elapsed:.1f} tokens/s')
# "

# 测试9: 协程调度器
# python3 -c "
# import requests, time
# url = 'http://localhost:11434/v1/chat/completions'
# data = {'model': 'qwen3.5-9b', 'messages': [{'role': 'user', 'content': '用Python实现一个协程调度器'}], 'max_tokens': 800, 'stream': False}
# t = time.time()
# r = requests.post(url, json=data, timeout=60).json()
# elapsed = time.time() - t
# gen_tokens = r['usage']['completion_tokens']
# print(f'{gen_tokens} tokens / {elapsed:.2f}s = {gen_tokens/elapsed:.1f} tokens/s')
# "

# 测试10: vector容器
# python3 -c "
# import requests, time
# url = 'http://localhost:11434/v1/chat/completions'
# data = {'model': 'qwen3.5-9b', 'messages': [{'role': 'user', 'content': '用Python实现一个STL风格的vector容器'}], 'max_tokens': 800, 'stream': False}
# t = time.time()
# r = requests.post(url, json=data, timeout=60).json()
# elapsed = time.time() - t
# gen_tokens = r['usage']['completion_tokens']
# print(f'{gen_tokens} tokens / {elapsed:.2f}s = {gen_tokens/elapsed:.1f} tokens/s')
# "

# 测试11: 堆排序
# python3 -c "
# import requests, time
# url = 'http://localhost:11434/v1/chat/completions'
# data = {'model': 'qwen3.5-9b', 'messages': [{'role': 'user', 'content': '用Python实现一个堆排序'}], 'max_tokens': 800, 'stream': False}
# t = time.time()
# r = requests.post(url, json=data, timeout=60).json()
# elapsed = time.time() - t
# gen_tokens = r['usage']['completion_tokens']
# print(f'{gen_tokens} tokens / {elapsed:.2f}s = {gen_tokens/elapsed:.1f} tokens/s')
# "

# 测试12: Dijkstra
# python3 -c "
# import requests, time
# url = 'http://localhost:11434/v1/chat/completions'
# data = {'model': 'qwen3.5-9b', 'messages': [{'role': 'user', 'content': '用Python实现一个图的最短路径Dijkstra算法'}], 'max_tokens': 800, 'stream': False}
# t = time.time()
# r = requests.post(url, json=data, timeout=60).json()
# elapsed = time.time() - t
# gen_tokens = r['usage']['completion_tokens']
# print(f'{gen_tokens} tokens / {elapsed:.2f}s = {gen_tokens/elapsed:.1f} tokens/s')
# "

# 测试13: 布隆过滤器(重复)
# python3 -c "
# import requests, time
# url = 'http://localhost:11434/v1/chat/completions'
# data = {'model': 'qwen3.5-9b', 'messages': [{'role': 'user', 'content': '用Python实现一个布隆过滤器'}], 'max_tokens': 800, 'stream': False}
# t = time.time()
# r = requests.post(url, json=data, timeout=60).json()
# elapsed = time.time() - t
# gen_tokens = r['usage']['completion_tokens']
# print(f'{gen_tokens} tokens / {elapsed:.2f}s = {gen_tokens/elapsed:.1f} tokens/s')
# "

# 测试14: 令牌桶
# python3 -c "
# import requests, time
# url = 'http://localhost:11434/v1/chat/completions'
# data = {'model': 'qwen3.5-9b', 'messages': [{'role': 'user', 'content': '用Python实现一个实现限流令牌桶算法'}], 'max_tokens': 800, 'stream': False}
# t = time.time()
# r = requests.post(url, json=data, timeout=60).json()
# elapsed = time.time() - t
# gen_tokens = r['usage']['completion_tokens']
# print(f'{gen_tokens} tokens / {elapsed:.2f}s = {gen_tokens/elapsed:.1f} tokens/s')
# "

# 测试15: 一致性哈希
# python3 -c "
# import requests, time
# url = 'http://localhost:11434/v1/chat/completions'
# data = {'model': 'qwen3.5-9b', 'messages': [{'role': 'user', 'content': '用Python实现一个一致性哈希算法'}], 'max_tokens': 800, 'stream': False}
# t = time.time()
# r = requests.post(url, json=data, timeout=60).json()
# elapsed = time.time() - t
# gen_tokens = r['usage']['completion_tokens']
# print(f'{gen_tokens} tokens / {elapsed:.2f}s = {gen_tokens/elapsed:.1f} tokens/s')
# "
