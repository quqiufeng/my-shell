#!/usr/bin/env python3
"""
Qwen2.5-Coder-14B EXL2 - RTX 3080 10G 极限优化版本

【优化配置】
- 上下文: 8k (显存极限，10GB满载运行)
- KV Cache: Q4 (必须量化以节省显存)
- 量化: 3.5bpw (低比特以适配显存)
- CUDA Graph: 禁用 (防止JIT hang)

【实测性能数据】(2025-04-02, RTX 3080 10G)
- 平均速度: 53.9 tokens/s
- 速度范围: 41.1 - 58.4 tokens/s
- 最快测试: 字典树(58.4), HTTP/HTTPS(58.3), 一致性哈希(58.3), Dijkstra(57.9)
- 最慢测试: 快速排序(41.1), 红黑树(49.0), 最长公共子序列(51.7)

【测试方法】
1. 启动模型:
   nohup python3 run_qwen_coder14b_exllamav2.py > /tmp/model.log 2>&1 &

2. 性能测试:
   cd /home/dministrator/my-shell
   python3 branch.py 11434 qwen2.5-coder-14b-exl2 200

3. 关闭服务:
   pkill -f run_qwen_coder14b_exllamav2.py

警告: 此配置在10GB显存上运行接近极限，如遇OOM请切换到7B模型
"""

import sys
import time
import socket
import os
import json

import torch
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse
from exllamav2 import (
    ExLlamaV2,
    ExLlamaV2Config,
    ExLlamaV2Cache_Q4,
    ExLlamaV2Tokenizer,
)
from exllamav2.generator import ExLlamaV2StreamingGenerator, ExLlamaV2Sampler

# 导入共享库（从上级目录）
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from api_handlers import (
    parse_tool_calls,
    build_prompt,
    build_prompt_from_jinja,
    generate_completion,
    responses_endpoint,
)

app = FastAPI()

MAIN_MODEL_DIR = "/opt/image/Qwen2.5-Coder-14B-Instruct-exl2/3_5"
MAX_SEQ_LEN = 8192  # 8k context - 3080 10G极限，避免OOM
PORT = 11434

print("Loading Qwen2.5-Coder-14B model...")
print(f"Model: {MAIN_MODEL_DIR}")
print(f"Max sequence length: {MAX_SEQ_LEN}")
print("⚠️  警告: 14B在10GB显存上运行接近极限")

config = ExLlamaV2Config(MAIN_MODEL_DIR)
config.max_seq_len = MAX_SEQ_LEN
config.no_flash_attn = False
config.no_sdpa = False
config.no_xformers = False
config.no_cuda_graph = True  # 禁用CUDA Graph防止JIT hang

model = ExLlamaV2(config)
cache = ExLlamaV2Cache_Q4(model, lazy=True)  # Q4缓存必须节省显存
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
print("🚀 Qwen2.5-Coder-14B 服务已启动! (3080)")
print("=" * 60)
print(f"模型: 14B EXL2 (3.5bpw)")
print(f"对内地址: http://localhost:{PORT}")
print(f"对外地址: http://{instance_id}-{PORT}.container.x-gpu.com/v1/chat/completions")
print("=" * 60)
print(f"显存占用: ~9.5GB / 10GB ⚠️ 极限运行")
print(f"预估速度: 50-60 tok/s")
print("=" * 60)
print("⚠️ 如遇OOM错误，请切换到7B模型")
print("=" * 60)
sys.stdout.flush()


@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [
            {
                "id": "qwen2.5-coder-14b-exl2",
                "object": "model",
                "created": int(time.time()),
                "owned_by": "qwen",
                "permission": [],
                "root": "qwen2.5-coder-14b-exl2",
            }
        ],
    }


@app.post("/v1/responses")
async def responses(request: Request):
    """OpenAI Responses API - 使用共享库"""
    return await responses_endpoint(
        request,
        lambda data: generate_completion(
            data, generator, tokenizer, settings, MAX_SEQ_LEN, "qwen2.5-coder-14b-exl2"
        ),
        "qwen2.5-coder-14b-exl2",
    )


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    """OpenAI Chat Completions API - 支持流式"""
    data = await request.json()
    messages = data.get("messages", [])
    tools = data.get("tools", [])
    model_name = data.get("model", "qwen2.5-coder-14b-exl2")
    max_tokens = data.get("max_tokens", MAX_SEQ_LEN - 1024)
    stream = data.get("stream", False)
    temperature = data.get("temperature", 0.0)

    settings.temperature = temperature

    if stream:
        # 流式响应
        async def generate_stream():
            prompt = build_prompt_from_jinja(messages, tools)
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
            "qwen2.5-coder-14b-exl2",
        )


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)
