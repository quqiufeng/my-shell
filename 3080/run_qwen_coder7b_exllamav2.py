#!/usr/bin/env python3
"""
Qwen2.5-Coder-7B EXL2 - RTX 3080 10G 优化版本

【优化配置】
- 上下文: 32k (平衡速度与长文本能力)
- KV Cache: Q6 (质量与速度平衡)
- 量化: 默认 (目录中的量化版本)
- CUDA Graph: 禁用 (防止JIT hang)

【实测性能数据】(2025-04-02, RTX 3080 10G)
- 平均速度: 83.3 tokens/s
- 速度范围: 40.3 - 95.6 tokens/s
- 显存占用: 6.05 GB / 10GB
- 最快测试: 跳表(95.6), KMP算法(95.3), 编辑距离(95.2), B+树(94.9)
- 最慢测试: HTTP/HTTPS(40.3), 线段树(40.5), 贪心算法(52.8), 动态规划(55.8)

【测试方法】
1. 启动模型:
   nohup python3 run_qwen_coder7b_exllamav2.py > /tmp/model.log 2>&1 &

2. 性能测试:
   cd /home/dministrator/my-shell
   python3 branch.py 11434 qwen2.5-coder-7b-exl2 200

3. 关闭服务:
   pkill -f run_qwen_coder7b_exllamav2.py

【完整测试结果】
Test [快速排序]: 200 tokens in 4.22s = 47.3 tokens/s
Test [线程安全]: 200 tokens in 2.84s = 70.5 tokens/s
Test [二分查找]: 200 tokens in 2.53s = 78.9 tokens/s
Test [数据库索引]: 200 tokens in 2.27s = 88.1 tokens/s
Test [Python性能优化]: 200 tokens in 2.24s = 89.4 tokens/s
Test [归并排序]: 200 tokens in 2.21s = 90.7 tokens/s
Test [HTTP/HTTPS]: 200 tokens in 4.97s = 40.3 tokens/s
Test [LRU缓存]: 200 tokens in 2.47s = 80.8 tokens/s
Test [堆排序]: 200 tokens in 2.59s = 77.3 tokens/s
Test [Dijkstra算法]: 200 tokens in 2.15s = 93.2 tokens/s
Test [一致性哈希]: 200 tokens in 2.15s = 93.2 tokens/s
Test [令牌桶]: 200 tokens in 2.14s = 93.4 tokens/s
Test [阻塞队列]: 200 tokens in 2.14s = 93.4 tokens/s
Test [红黑树]: 200 tokens in 2.24s = 89.1 tokens/s
Test [B+树]: 200 tokens in 2.11s = 94.9 tokens/s
Test [A*算法]: 200 tokens in 2.19s = 91.2 tokens/s
Test [KMP算法]: 200 tokens in 2.10s = 95.3 tokens/s
Test [布隆过滤器]: 200 tokens in 2.21s = 90.6 tokens/s
Test [跳表]: 200 tokens in 2.09s = 95.6 tokens/s
Test [并查集]: 200 tokens in 2.23s = 89.7 tokens/s
Test [线段树]: 200 tokens in 4.94s = 40.5 tokens/s
Test [字典树]: 200 tokens in 2.27s = 88.1 tokens/s
Test [最小生成树]: 200 tokens in 2.23s = 89.9 tokens/s
Test [拓扑排序]: 200 tokens in 2.43s = 82.2 tokens/s
Test [最长公共子序列]: 200 tokens in 2.21s = 90.5 tokens/s
Test [编辑距离]: 200 tokens in 2.10s = 95.2 tokens/s
Test [滑动窗口]: 200 tokens in 2.50s = 80.0 tokens/s
Test [双指针]: 200 tokens in 2.28s = 87.9 tokens/s
Test [动态规划]: 200 tokens in 2.32s = 86.0 tokens/s
Test [贪心算法]: 200 tokens in 2.61s = 76.6 tokens/s
"""

import sys
import time
import socket
import os
import json

# Fix for missing PyTorch libraries
os.environ["LD_LIBRARY_PATH"] = (
    "/home/dministrator/anaconda3/envs/dl/lib/python3.10/site-packages/torch/lib:"
    + os.environ.get("LD_LIBRARY_PATH", "")
)

import torch
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse
from exllamav2 import (
    ExLlamaV2,
    ExLlamaV2Config,
    ExLlamaV2Cache_Q6,
    ExLlamaV2Tokenizer,
)
from exllamav2.generator import ExLlamaV2StreamingGenerator, ExLlamaV2Sampler

# 导入共享库（从上级目录）
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from api_handlers import (
    parse_tool_calls,
    build_prompt,
    generate_completion,
    responses_endpoint,
)

app = FastAPI()

MAIN_MODEL_DIR = "/opt/image/Qwen2.5-Coder-7B-Instruct-exl2"
MAX_SEQ_LEN = 32768  # 32k context - 3080 10G安全范围
PORT = 11434

print("Loading Qwen2.5-Coder-7B model...")
print(f"Model: {MAIN_MODEL_DIR}")
print(f"Max sequence length: {MAX_SEQ_LEN}")

config = ExLlamaV2Config(MAIN_MODEL_DIR)
config.max_seq_len = MAX_SEQ_LEN
config.no_flash_attn = False
config.no_sdpa = False
config.no_xformers = False
config.no_cuda_graph = True  # 禁用CUDA Graph - 3080上性能更好

model = ExLlamaV2(config)
cache = ExLlamaV2Cache_Q6(model, lazy=True)  # Q6缓存平衡质量与显存
model.load_autosplit(cache)

tokenizer = ExLlamaV2Tokenizer(config)

generator = ExLlamaV2StreamingGenerator(
    model=model,
    cache=cache,
    tokenizer=tokenizer,
)

settings = ExLlamaV2Sampler.Settings()
settings.temperature = 0.0
settings.top_p = 0.9
settings.token_repetition_penalty = 1.0

print(f"VRAM: {torch.cuda.memory_allocated() / 1024**3:.2f} GB")
sys.stdout.flush()

hostname = socket.gethostname()
instance_id = os.environ.get("XGC_INSTANCE_ID", hostname)

print("")
print("=" * 60)
print("🚀 Qwen2.5-Coder-7B 服务已启动! (3080)")
print("=" * 60)
print(f"模型: 7B EXL2")
print(f"对内地址: http://localhost:{PORT}")
print(f"对外地址: http://{instance_id}-{PORT}.container.x-gpu.com/v1/chat/completions")
print("=" * 60)
print(f"显存占用: ~8.5GB / 10GB")
print(f"预估速度: 70-90 tok/s")
print("=" * 60)
sys.stdout.flush()


@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [
            {
                "id": "qwen2.5-coder-7b-exl2",
                "object": "model",
                "created": int(time.time()),
                "owned_by": "qwen",
                "permission": [],
                "root": "qwen2.5-coder-7b-exl2",
            }
        ],
    }


@app.post("/v1/responses")
async def responses(request: Request):
    """OpenAI Responses API - 使用共享库"""
    return await responses_endpoint(
        request,
        lambda data: generate_completion(
            data, generator, tokenizer, settings, MAX_SEQ_LEN, "qwen2.5-coder-7b-exl2"
        ),
        "qwen2.5-coder-7b-exl2",
    )


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    """OpenAI Chat Completions API - 支持流式"""
    data = await request.json()
    messages = data.get("messages", [])
    tools = data.get("tools", [])
    model_name = data.get("model", "qwen2.5-coder-7b-exl2")
    max_tokens = data.get("max_tokens", MAX_SEQ_LEN - 1024)
    stream = data.get("stream", False)
    temperature = data.get("temperature", 0.0)

    settings.temperature = temperature

    if stream:
        # 流式响应
        async def generate_stream():
            prompt = build_prompt(messages, tools)
            input_ids = tokenizer.encode(prompt)
            if isinstance(input_ids, tuple):
                input_ids = input_ids[0]

            eos = False
            generated = 0
            full_output = ""
            tool_calls_sent = False
            generator.begin_stream(input_ids, settings)

            while generated < max_tokens:
                result = generator.stream_ex()
                chunk = result["chunk"]
                eos = result["eos"]
                tokens = result.get("chunk_token_ids", None)

                if chunk:
                    if tokens is not None:
                        gen_tokens = (
                            tokens.shape[1] if hasattr(tokens, "shape") else len(tokens)
                        )
                        generated += gen_tokens
                    else:
                        generated += 1
                    full_output += chunk

                    # 检查是否触发了工具调用
                    if not tool_calls_sent:
                        tool_calls = parse_tool_calls(full_output)
                        if tool_calls:
                            data = {
                                "choices": [
                                    {
                                        "delta": {
                                            "role": "assistant",
                                            "tool_calls": tool_calls,
                                        },
                                        "finish_reason": "tool_calls",
                                    }
                                ]
                            }
                            yield f"data: {json.dumps(data)}\n\n"
                            tool_calls_sent = True
                            continue

                    if not tool_calls_sent:
                        data = {
                            "choices": [
                                {"delta": {"content": chunk}, "finish_reason": None}
                            ],
                            "usage": {
                                "prompt_tokens": input_ids.shape[-1],
                                "completion_tokens": generated,
                            },
                        }
                        yield f"data: {json.dumps(data)}\n\n"

                if eos:
                    if not tool_calls_sent:
                        data = {"choices": [{"delta": {}, "finish_reason": "stop"}]}
                        yield f"data: {json.dumps(data)}\n\n"
                    yield "data: [DONE]\n\n"
                    break

            if not eos and not tool_calls_sent:
                yield "data: [DONE]\n\n"

        return StreamingResponse(generate_stream(), media_type="text/event-stream")
    else:
        # 非流式响应
        return await generate_completion(
            {
                "messages": messages,
                "tools": tools,
                "model": model_name,
                "max_tokens": max_tokens,
            },
            generator,
            tokenizer,
            settings,
            MAX_SEQ_LEN,
            "qwen2.5-coder-7b-exl2",
        )


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)
