#!/bin/bash

export LD_LIBRARY_PATH=/opt/llama.cpp/bin:/opt/llama.cpp/build/lib:$LD_LIBRARY_PATH

MODEL_TYPE="${1:-q4}"

if [ "$MODEL_TYPE" = "q3" ]; then
  MODEL_DIR="/opt/gguf/qwen2.5-coder-32b-instruct-q3_k_m.gguf"
  MODEL_NAME="qwen2.5-coder-32b-instruct-q3_k_m.gguf"
  KV_CACHE="q4_0"
  CTX_SIZE=65536
else
  MODEL_DIR="/opt/gguf/qwen2.5-coder-32b-instruct-q4_k_m.gguf"
  MODEL_NAME="qwen2.5-coder-32b-instruct-q4_k_m.gguf"
  KV_CACHE="q4_0"
  CTX_SIZE=65536
fi

if [ ! -f "$MODEL_DIR" ]; then
  echo "错误: 模型文件不存在: $MODEL_DIR"
  exit 1
fi

LLAMA_SERVER="/opt/llama.cpp/bin/llama-server"

echo "=============================="
echo "启动 Qwen2.5-Coder-32B API 服务"
echo "模型: $MODEL_NAME"
echo "地址: http://0.0.0.0:11434"
echo "上下文: $CTX_SIZE"
echo "GPU层数: 99"
echo "=============================="

$LLAMA_SERVER \
  -m "$MODEL_DIR" \
  --host 0.0.0.0 \
  --port 11434 \
  --n-gpu-layers 80 \
  --ctx-size $CTX_SIZE \
  --batch-size 1024 \
  --ubatch-size 512 \
  --flash-attn on \
  --cache-type-k "$KV_CACHE" \
  --cache-type-v "$KV_CACHE" \
  --threads 14 \
  --no-mmap \
  --mlock \
  --jinja \
  --temp 0 \
  2>&1 | tee /opt/my-shell/4090d/qwen_api.log &

sleep 40

export OPENAI_API_KEY=dummy
nohup litellm \
  --model openai/qwen2.5-coder \
  --api_base http://localhost:11434/v1 \
  --port 4000 \
  > /tmp/litellm.log 2>&1 &

sleep 3

INSTANCE_ID=${XGC_INSTANCE_ID:-$(hostname)}

echo ""
echo "=============================="
echo "服务已启动!"
echo "=============================="
echo "llama.cpp: http://localhost:11434"
echo "LiteLLM:   http://localhost:4000 (OpenCode用这个)"
echo "对外地址:  http://${INSTANCE_ID}-4000.container.x-gpu.com/v1/"
echo "=============================="
echo ""
echo "OpenCode 配置:"
echo '  BaseURL: http://localhost:4000/v1'
echo "  Model:   openai/qwen2.5-coder"
echo ""
echo "调试命令:"
echo "curl -s http://localhost:4000/v1/chat/completions \\"
echo '  -H "Content-Type: application/json" \\'
echo '  -d '"'"'{"model": "openai/qwen2.5-coder", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'"'"''
echo ""
echo "性能参数:"
echo "  模型: $MODEL_NAME"
echo "  上下文: $CTX_SIZE"
echo "  GPU层数: 99"
echo "  KV缓存: $KV_CACHE"
echo "  Flash Attention: on"

# ==========================================
# 性能测试 (使用 usage 字段获取准确 token 数)
# ==========================================
# 测试1: 红黑树
# python3 -c "
# import requests, time
# url = 'http://localhost:11434/v1/chat/completions'
# data = {'model': '"$MODEL_NAME"', 'messages': [{'role': 'user', 'content': '用Python实现一个红黑树'}], 'max_tokens': 800, 'stream': False}
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
# data = {'model': '"$MODEL_NAME"', 'messages': [{'role': 'user', 'content': '用Python实现一个B+树'}], 'max_tokens': 800, 'stream': False}
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
# data = {'model': '"$MODEL_NAME"', 'messages': [{'role': 'user', 'content': '用Python实现一个A*寻路算法'}], 'max_tokens': 800, 'stream': False}
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
# data = {'model': '"$MODEL_NAME"', 'messages': [{'role': 'user', 'content': '用Python实现一个布隆过滤器'}], 'max_tokens': 800, 'stream': False}
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
# data = {'model': '"$MODEL_NAME"', 'messages': [{'role': 'user', 'content': '用Python实现一个LRU-K缓存淘汰算法'}], 'max_tokens': 800, 'stream': False}
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
# data = {'model': '"$MODEL_NAME"', 'messages': [{'role': 'user', 'content': '用Python实现一个线程安全的阻塞队列'}], 'max_tokens': 800, 'stream': False}
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
# data = {'model': '"$MODEL_NAME"', 'messages': [{'role': 'user', 'content': '用Python实现一个无锁CAS队列'}], 'max_tokens': 800, 'stream': False}
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
# data = {'model': '"$MODEL_NAME"', 'messages': [{'role': 'user', 'content': '用Python实现一个支持亿级数据排序的外排序算法'}], 'max_tokens': 800, 'stream': False}
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
# data = {'model': '"$MODEL_NAME"', 'messages': [{'role': 'user', 'content': '用Python实现一个协程调度器'}], 'max_tokens': 800, 'stream': False}
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
# data = {'model': '"$MODEL_NAME"', 'messages': [{'role': 'user', 'content': '用Python实现一个STL风格的vector容器'}], 'max_tokens': 800, 'stream': False}
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
# data = {'model': '"$MODEL_NAME"', 'messages': [{'role': 'user', 'content': '用Python实现一个堆排序'}], 'max_tokens': 800, 'stream': False}
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
# data = {'model': '"$MODEL_NAME"', 'messages': [{'role': 'user', 'content': '用Python实现一个图的最短路径Dijkstra算法'}], 'max_tokens': 800, 'stream': False}
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
# data = {'model': '"$MODEL_NAME"', 'messages': [{'role': 'user', 'content': '用Python实现一个布隆过滤器'}], 'max_tokens': 800, 'stream': False}
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
# data = {'model': '"$MODEL_NAME"', 'messages': [{'role': 'user', 'content': '用Python实现一个限流令牌桶算法'}], 'max_tokens': 800, 'stream': False}
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
# data = {'model': '"$MODEL_NAME"', 'messages': [{'role': 'user', 'content': '用Python实现一个一致性哈希算法'}], 'max_tokens': 800, 'stream': False}
# t = time.time()
# r = requests.post(url, json=data, timeout=60).json()
# elapsed = time.time() - t
# gen_tokens = r['usage']['completion_tokens']
# print(f'{gen_tokens} tokens / {elapsed:.2f}s = {gen_tokens/elapsed:.1f} tokens/s')
# "
