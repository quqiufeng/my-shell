#!/bin/bash

MODEL_DIR="$HOME/Qwen3.5-9B-Q4_K_M.gguf"
LLAMA_SERVER="$HOME/llama.cpp/build/bin/llama-server"

export LD_LIBRARY_PATH=/usr/lib/wsl/lib:$LD_LIBRARY_PATH

echo "=============================="
echo "启动 Qwen3.5-9B API 服务 (3080 10GB 满血版)"
echo "地址: http://0.0.0.0:11434"
echo "模型: Qwen3.5-9B-Q4_K_M.gguf"
echo "上下文参数: -c 131072"
echo "实际上下文: ~32K (约为参数的1/4)"
echo "GPU层数: 60"
echo "Batch Size: 1024"
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
  -m "$MODEL_DIR" \                             # [稳定性] 模型文件路径
  --host 0.0.0.0 \                           # [稳定性] 监听地址 (0.0.0.0允许外部访问)
  --port 11434 \                               # [稳定性] API端口
  -ngl 60 \                                  # [性能] GPU加载层数 (全部60层,越多越快越显存)
  -c 131072 \                                # [性能] 上下文大小 (实际约32K,影响长对话)
  --batch-size 1024 \                        # [性能] 批处理大小 (越大越快越显存)
  --flash-attn on \                          # [性能] Flash Attention加速 (省显存,提升性能)
  --cache-type-k q4_0 \                      # [性能] KV Cache量化K值 (q4省显存,q8更准)
  --cache-type-v q4_0 \                      # [性能] KV Cache量化V值 (q4省显存,q8更准)
  --threads 12 \                               # [性能] CPU线程数 (越多越快,建议8-16)
  --parallel 1 \                             # [稳定性] 并行slot数量 (越多并发但显存高,建议1)
  --n-predict 4096 \                        # [稳定性] 最大输出tokens (决定单次生成最长长度)
  --log-disable &                           # [稳定性] 禁用日志输出

# =============================================================================
# 性能测试代码 - 用于评估模型推理性能
# 使用方法: 每次运行下面的 python 命令跑一个提示词，连续运行15次
# =============================================================================

# 测试1: 红黑树
# python3 -c "
# import requests, time
# url = 'http://localhost:11434'
# data = {'messages': [{'role': 'user', 'content': '用Python实现一个红黑树数据结构'}], 'max_tokens': 800}
# t = time.time()
# r = requests.post(url + '/v1/chat/completions', json=data, timeout=60)
# elapsed = time.time() - t
# content = r.json()['choices'][0]['message']['content']
# print(f'{elapsed:.2f}s | {len(content)} | {len(content)/elapsed:.1f}')
# "

# 测试2: B+树
# python3 -c "
# import requests, time
# url = 'http://localhost:11434'
# data = {'messages': [{'role': 'user', 'content': '用Python实现一个B+树'}], 'max_tokens': 800}
# t = time.time()
# r = requests.post(url + '/v1/chat/completions', json=data, timeout=60)
# elapsed = time.time() - t
# content = r.json()['choices'][0]['message']['content']
# print(f'{elapsed:.2f}s | {len(content)} | {len(content)/elapsed:.1f}')
# "

# 测试3: A*寻路
# python3 -c "
# import requests, time
# url = 'http://localhost:11434'
# data = {'messages': [{'role': 'user', 'content': '用Python实现一个A*寻路算法'}], 'max_tokens': 800}
# t = time.time()
# r = requests.post(url + '/v1/chat/completions', json=data, timeout=60)
# elapsed = time.time() - t
# content = r.json()['choices'][0]['message']['content']
# print(f'{elapsed:.2f}s | {len(content)} | {len(content)/elapsed:.1f}')
# "

# 测试4: 布隆过滤器
# python3 -c "
# import requests, time
# url = 'http://localhost:11434'
# data = {'messages': [{'role': 'user', 'content': '用Python实现一个布隆过滤器'}], 'max_tokens': 800}
# t = time.time()
# r = requests.post(url + '/v1/chat/completions', json=data, timeout=60)
# elapsed = time.time() - t
# content = r.json()['choices'][0]['message']['content']
# print(f'{elapsed:.2f}s | {len(content)} | {len(content)/elapsed:.1f}')
# "

# 测试5: LRU-K缓存
# python3 -c "
# import requests, time
# url = 'http://localhost:11434'
# data = {'messages': [{'role': 'user', 'content': '用Python实现一个LRU-K缓存淘汰算法'}], 'max_tokens': 800}
# t = time.time()
# r = requests.post(url + '/v1/chat/completions', json=data, timeout=60)
# elapsed = time.time() - t
# content = r.json()['choices'][0]['message']['content']
# print(f'{elapsed:.2f}s | {len(content)} | {len(content)/elapsed:.1f}')
# "

# 测试6: 阻塞队列
# python3 -c "
# import requests, time
# url = 'http://localhost:11434'
# data = {'messages': [{'role': 'user', 'content': '用Python实现一个线程安全的阻塞队列'}], 'max_tokens': 800}
# t = time.time()
# r = requests.post(url + '/v1/chat/completions', json=data, timeout=60)
# elapsed = time.time() - t
# content = r.json()['choices'][0]['message']['content']
# print(f'{elapsed:.2f}s | {len(content)} | {len(content)/elapsed:.1f}')
# "

# 测试7: CAS队列
# python3 -c "
# import requests, time
# url = 'http://localhost:11434'
# data = {'messages': [{'role': 'user', 'content': '用Python实现一个无锁CAS队列'}], 'max_tokens': 800}
# t = time.time()
# r = requests.post(url + '/v1/chat/completions', json=data, timeout=60)
# elapsed = time.time() - t
# content = r.json()['choices'][0]['message']['content']
# print(f'{elapsed:.2f}s | {len(content)} | {len(content)/elapsed:.1f}')
# "

# 测试8: 外排序
# python3 -c "
# import requests, time
# url = 'http://localhost:11434'
# data = {'messages': [{'role': 'user', 'content': '用Python实现一个支持亿级数据排序的外排序算法'}], 'max_tokens': 800}
# t = time.time()
# r = requests.post(url + '/v1/chat/completions', json=data, timeout=60)
# elapsed = time.time() - t
# content = r.json()['choices'][0]['message']['content']
# print(f'{elapsed:.2f}s | {len(content)} | {len(content)/elapsed:.1f}')
# "

# 测试9: 协程调度器
# python3 -c "
# import requests, time
# url = 'http://localhost:11434'
# data = {'messages': [{'role': 'user', 'content': '用Python实现一个协程调度器'}], 'max_tokens': 800}
# t = time.time()
# r = requests.post(url + '/v1/chat/completions', json=data, timeout=60)
# elapsed = time.time() - t
# content = r.json()['choices'][0]['message']['content']
# print(f'{elapsed:.2f}s | {len(content)} | {len(content)/elapsed:.1f}')
# "

# 测试10: vector容器
# python3 -c "
# import requests, time
# url = 'http://localhost:11434'
# data = {'messages': [{'role': 'user', 'content': '用Python实现一个STL风格的vector容器'}], 'max_tokens': 800}
# t = time.time()
# r = requests.post(url + '/v1/chat/completions', json=data, timeout=60)
# elapsed = time.time() - t
# content = r.json()['choices'][0]['message']['content']
# print(f'{elapsed:.2f}s | {len(content)} | {len(content)/elapsed:.1f}')
# "

# 测试11: 堆排序
# python3 -c "
# import requests, time
# url = 'http://localhost:11434'
# data = {'messages': [{'role': 'user', 'content': '用Python实现一个堆排序'}], 'max_tokens': 800}
# t = time.time()
# r = requests.post(url + '/v1/chat/completions', json=data, timeout=60)
# elapsed = time.time() - t
# content = r.json()['choices'][0]['message']['content']
# print(f'{elapsed:.2f}s | {len(content)} | {len(content)/elapsed:.1f}')
# "

# 测试12: Dijkstra
# python3 -c "
# import requests, time
# url = 'http://localhost:11434'
# data = {'messages': [{'role': 'user', 'content': '用Python实现一个图的最短路径Dijkstra算法'}], 'max_tokens': 800}
# t = time.time()
# r = requests.post(url + '/v1/chat/completions', json=data, timeout=60)
# elapsed = time.time() - t
# content = r.json()['choices'][0]['message']['content']
# print(f'{elapsed:.2f}s | {len(content)} | {len(content)/elapsed:.1f}')
# "

# 测试13: 布隆过滤器(重复)
# python3 -c "
# import requests, time
# url = 'http://localhost:11434'
# data = {'messages': [{'role': 'user', 'content': '用Python实现一个布隆过滤器'}], 'max_tokens': 800}
# t = time.time()
# r = requests.post(url + '/v1/chat/completions', json=data, timeout=60)
# elapsed = time.time() - t
# content = r.json()['choices'][0]['message']['content']
# print(f'{elapsed:.2f}s | {len(content)} | {len(content)/elapsed:.1f}')
# "

# 测试14: 令牌桶
# python3 -c "
# import requests, time
# url = 'http://localhost:11434'
# data = {'messages': [{'role': 'user', 'content': '用Python实现一个实现限流令牌桶算法'}], 'max_tokens': 800}
# t = time.time()
# r = requests.post(url + '/v1/chat/completions', json=data, timeout=60)
# elapsed = time.time() - t
# content = r.json()['choices'][0]['message']['content']
# print(f'{elapsed:.2f}s | {len(content)} | {len(content)/elapsed:.1f}')
# "

# 测试15: 一致性哈希
# python3 -c "
# import requests, time
# url = 'http://localhost:11434'
# data = {'messages': [{'role': 'user', 'content': '用Python实现一个一致性哈希算法'}], 'max_tokens': 800}
# t = time.time()
# r = requests.post(url + '/v1/chat/completions', json=data, timeout=60)
# elapsed = time.time() - t
# content = r.json()['choices'][0]['message']['content']
# print(f'{elapsed:.2f}s | {len(content)} | {len(content)/elapsed:.1f}')
# "
