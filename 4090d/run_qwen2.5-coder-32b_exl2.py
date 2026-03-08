#!/usr/bin/env python3

# =============================================================================
# 依赖安装 (首次运行前执行)
# =============================================================================
# ⚠️ 重要: 安装 FlashAttention 可提升 50%+ 速度
# 编译安装 (针对 RTX 4090D):
#   bash /opt/my-shell/4090d/build_flash_attention.sh
#
# 验证安装:
# python3 -c "import flash_attn; print(flash_attn.__version__)"
# =============================================================================

import sys
import time
import socket
import os
import torch
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse
from exllamav2 import ExLlamaV2, ExLlamaV2Config, ExLlamaV2Cache_Q4, ExLlamaV2Tokenizer, ExLlamaV2Cache
from exllamav2.generator import ExLlamaV2StreamingGenerator, ExLlamaV2Sampler

app = FastAPI()

MAIN_MODEL_DIR = "/opt/gguf/exl2_4_0"
DRAFT_MODEL_DIR = "/opt/gguf/Qwen2.5-Coder-0.5B-exl2"

MAX_SEQ_LEN = 32768
PORT = 11434
NUM_SPECULATIVE_TOKENS = 6  # 最优配置: 8投机反而下降

print("Loading main model...")

config = ExLlamaV2Config(MAIN_MODEL_DIR)
config.max_seq_len = MAX_SEQ_LEN
config.no_flash_attn = False  # 确保启用FlashAttention
config.no_sdpa = False         # 禁用SDPA，强制用FlashAttention
config.no_xformers = False     # 禁用xformers
model = ExLlamaV2(config)
cache = ExLlamaV2Cache_Q4(model, lazy=True)  # Q4 KV Cache (速度最快)
model.load_autosplit(cache)

print("Loading draft model...")

draft_config = ExLlamaV2Config(DRAFT_MODEL_DIR)
draft_config.max_seq_len = MAX_SEQ_LEN
draft_config.no_flash_attn = False
draft_config.no_sdpa = False
draft_model = ExLlamaV2(draft_config)
draft_cache = ExLlamaV2Cache(draft_model)  # 草稿模型用默认 cache
draft_model.load_autosplit(draft_cache)

tokenizer = ExLlamaV2Tokenizer(config)

generator = ExLlamaV2StreamingGenerator(
    model=model,
    cache=cache,
    tokenizer=tokenizer,
    draft_model=draft_model,
    draft_cache=draft_cache,
    num_speculative_tokens=NUM_SPECULATIVE_TOKENS,
)

settings = ExLlamaV2Sampler.Settings()
settings.temperature = 0.0
settings.token_repetition_penalty = 1.0

print(f"VRAM: {torch.cuda.memory_allocated()/1024**3:.2f} GB")
import sys
sys.stdout.flush()

hostname = socket.gethostname()
instance_id = os.environ.get('XGC_INSTANCE_ID', hostname)
ip = socket.gethostbyname(hostname)

print("")
print("==============================")
print("服务已启动!")
print("==============================")
print(f"对内地址: http://localhost:{PORT}")
print(f"对外地址: http://{instance_id}-{PORT}.container.x-gpu.com/v1/chat/completions")
print(f"IP: {ip}")
print("==============================")
sys.stdout.flush()

@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    data = await request.json()
    messages = data.get("messages", [])
    prompt = messages[-1]["content"] if messages else ""
    max_tokens = data.get("max_tokens", MAX_SEQ_LEN - 1024)
    stream = data.get("stream", False)
    
    input_ids = tokenizer.encode(prompt)

    if stream:
        def generate():
            eos = False
            generated = 0
            generator.begin_stream(input_ids, settings)
            
            while generated < max_tokens:
                result = generator.stream_ex()
                chunk = result['chunk']
                eos = result['eos']
                tokens = result['chunk_token_ids']
                
                if chunk:
                    generated += tokens.shape[1]
                    yield f"data: {{\"choices\": [ {{\"delta\": {{\"content\": \"{chunk}\"}}, \"finish_reason\": null}} ] }}\n\n"
                
                if eos:
                    yield "data: [DONE]\n\n"
                    break
            
            if not eos:
                yield "data: [DONE]\n\n"

        return StreamingResponse(generate(), media_type="text/event-stream")
    else:
        full_text = ""
        eos = False
        generated = 0
        generator.begin_stream(input_ids, settings)
        
        while generated < max_tokens:
            result = generator.stream_ex()
            chunk = result['chunk']
            eos = result['eos']
            tokens = result['chunk_token_ids']
            
            if chunk:
                full_text += chunk
                generated += tokens.shape[1]
            
            if eos:
                break
        
        import json
        return {"choices": [{"message": {"content": full_text}, "finish_reason": "stop"}]}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)


# =============================================================================
# 性能测试代码 - 用于评估模型推理性能
# 使用方法: 每次运行下面的 python -c 命令跑一个提示词，连续运行15次
# 每次 python -c 只跑一个，防止超时
# =============================================================================

# 性能测试 - 高难度Python代码生成任务
# 共15个测试，每次运行一条命令

# 测试1: 红黑树
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个红黑树数据结构'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试2: B+树
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个B+树'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试3: A*寻路
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个A*寻路算法'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试4: 布隆过滤器
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个布隆过滤器'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试5: LRU-K缓存
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个LRU-K缓存淘汰算法'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试6: 阻塞队列
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个线程安全的阻塞队列'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试7: CAS队列
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个无锁CAS队列'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试8: 外排序
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个支持亿级数据排序的外排序算法'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试9: 协程调度器
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个协程调度器'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试10: vector容器
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个STL风格的vector容器'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试11: 堆排序
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个堆排序'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试12: Dijkstra
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个图的最短路径Dijkstra算法'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试13: 布隆过滤器(重复)
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个布隆过滤器'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试14: 令牌桶
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个实现限流令牌桶算法'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试15: 一致性哈希
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个一致性哈希算法'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"


# =============================================================================
# 优化记录:
# - 2026-03-08: 初始版本
#   - NUM_SPECULATIVE_TOKENS = 4 (从2调整)
#   - 模型: exl2_4_0 (4bit量化)
#   - 草稿模型: Qwen2.5-Coder-0.5B-exl2
#   - 测试结果: ~100-110 tok/s
#
# 可优化方向:
# 1. NUM_SPECULATIVE_TOKENS: 尝试 3-6 (当前4)
# 2. KV Cache: 尝试 Q6/Q8 (当前Q4) - 需要更多VRAM
# 3. 草稿模型: 尝试更大尺寸的草稿模型 (如1.5B)
# 4. Batch Size: 调整批处理大小
# 5. Flash Attention: 确保启用
# 6. TensorRT: 当前不支持
# =============================================================================


# =============================================================================
# 投机采样接受率测试
# 使用方法: 每次运行一条命令
# =============================================================================

# 测试1: 红黑树 (带接受率)
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个红黑树数据结构'}],'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); d=r.json()['choices'][0]['message']['content']; print(f\"{time.time()-t:.2f}s | {len(d)} | {len(d)/(time.time()-t):.1f} tok/s\")"

# =============================================================================
# FlashAttention-2 确认方法
# 运行以下命令检查是否安装:
# python3 -c "from flash_attn import flash_attn_func; print('FlashAttention 已安装')"
# =============================================================================
